CREATE TABLE public.merchant_upi_ids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider public.upi_provider NOT NULL DEFAULT 'phonepe',
  upi_id text NOT NULL,
  payee_name text NOT NULL DEFAULT '',
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX merchant_upi_ids_user_upi ON public.merchant_upi_ids (user_id, lower(upi_id));
CREATE UNIQUE INDEX merchant_upi_ids_one_primary ON public.merchant_upi_ids (user_id) WHERE is_primary;
GRANT SELECT ON public.merchant_upi_ids TO authenticated;
GRANT ALL ON public.merchant_upi_ids TO service_role;
ALTER TABLE public.merchant_upi_ids ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own upi ids" ON public.merchant_upi_ids FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE public.merchant_upi_routing (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.merchant_upi_routing TO authenticated;
GRANT ALL ON public.merchant_upi_routing TO service_role;
ALTER TABLE public.merchant_upi_routing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own upi routing" ON public.merchant_upi_routing FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.list_upi_ids() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'routing', COALESCE((SELECT enabled FROM merchant_upi_routing WHERE user_id = auth.uid()), false),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'provider', provider, 'upi_id', upi_id, 'payee_name', payee_name, 'is_primary', is_primary) ORDER BY created_at)
                       FROM merchant_upi_ids WHERE user_id = auth.uid()), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.add_upi_id(_upi_id text, _payee_name text DEFAULT '', _provider text DEFAULT 'phonepe') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); v text := lower(btrim(COALESCE(_upi_id, ''))); n int; rid uuid;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v !~ '^[a-z0-9._-]{2,256}@[a-z0-9.-]{2,64}$' THEN RAISE EXCEPTION 'INVALID_UPI_ID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_u::text, 11));
  SELECT count(*) INTO n FROM merchant_upi_ids WHERE user_id = _u;
  IF n >= 10 THEN RAISE EXCEPTION 'UPI_LIMIT_REACHED'; END IF;
  IF EXISTS (SELECT 1 FROM merchant_upi_ids WHERE user_id = _u AND lower(upi_id) = v) THEN RAISE EXCEPTION 'UPI_ALREADY_ADDED'; END IF;
  INSERT INTO merchant_upi_ids (user_id, provider, upi_id, payee_name, is_primary)
  VALUES (_u, CASE WHEN _provider = 'paytm' THEN 'paytm'::upi_provider ELSE 'phonepe'::upi_provider END,
          v, left(btrim(COALESCE(_payee_name, '')), 100), n = 0)
  RETURNING id INTO rid;
  RETURN jsonb_build_object('id', rid);
END $$;

CREATE OR REPLACE FUNCTION public.remove_upi_id(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); was boolean;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  DELETE FROM merchant_upi_ids WHERE id = _id AND user_id = _u RETURNING is_primary INTO was;
  IF was THEN
    UPDATE merchant_upi_ids SET is_primary = true
     WHERE id = (SELECT id FROM merchant_upi_ids WHERE user_id = _u ORDER BY created_at LIMIT 1);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_primary_upi(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid();
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM merchant_upi_ids WHERE id = _id AND user_id = _u) THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  UPDATE merchant_upi_ids SET is_primary = false WHERE user_id = _u AND is_primary;
  UPDATE merchant_upi_ids SET is_primary = true WHERE id = _id;
END $$;

CREATE OR REPLACE FUNCTION public.set_upi_routing(_enabled boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid();
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  INSERT INTO merchant_upi_routing (user_id, enabled, updated_at) VALUES (_u, COALESCE(_enabled, false), now())
  ON CONFLICT (user_id) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
  RETURN COALESCE(_enabled, false);
END $$;

-- Picks the UPI for a new link: random when routing is on, otherwise primary.
CREATE OR REPLACE FUNCTION public.pick_merchant_upi(_user uuid) RETURNS public.merchant_upi_ids
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r merchant_upi_ids%ROWTYPE;
BEGIN
  IF COALESCE((SELECT enabled FROM merchant_upi_routing WHERE user_id = _user), false) THEN
    SELECT * INTO r FROM merchant_upi_ids WHERE user_id = _user ORDER BY random() LIMIT 1;
  ELSE
    SELECT * INTO r FROM merchant_upi_ids WHERE user_id = _user ORDER BY is_primary DESC, created_at LIMIT 1;
  END IF;
  RETURN r;
END $$;

REVOKE EXECUTE ON FUNCTION public.pick_merchant_upi(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pick_merchant_upi(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.list_upi_ids(), public.add_upi_id(text,text,text), public.remove_upi_id(uuid), public.set_primary_upi(uuid), public.set_upi_routing(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_upi_ids(), public.add_upi_id(text,text,text), public.remove_upi_id(uuid), public.set_primary_upi(uuid), public.set_upi_routing(boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  pick public.merchant_upi_ids%ROWTYPE;
  base numeric(12,2); candidate numeric(12,2); taken numeric[];
  oid text; sl text; row_id uuid; i int; exp timestamptz;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _amount IS NULL OR _amount <= 0 OR _amount > 1000000 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO acct FROM public.merchant_accounts
   WHERE user_id = _user AND connected ORDER BY connected_at DESC NULLS LAST LIMIT 1;
  IF acct.id IS NULL THEN
    SELECT * INTO acct FROM public.merchant_accounts
     WHERE user_id = _user AND length(btrim(upi_id)) > 0 ORDER BY updated_at DESC LIMIT 1;
  END IF;
  pick := public.pick_merchant_upi(_user);
  IF pick.id IS NOT NULL THEN
    acct.id := COALESCE(acct.id, pick.id);
    acct.provider := pick.provider; acct.upi_id := pick.upi_id;
    acct.payee_name := CASE WHEN pick.payee_name <> '' THEN pick.payee_name ELSE COALESCE(acct.payee_name, '') END;
  END IF;
  IF acct.id IS NULL OR length(btrim(COALESCE(acct.upi_id, ''))) = 0 THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 7));
  PERFORM public.expire_stale_payment_links(_user);

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 0.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 99) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  PERFORM public.consume_qr_quota(_user, 'upi://pay?pa=' || acct.upi_id, acct.upi_id, base, 'Payment link');
  sl  := public.new_payment_slug();
  exp := now() + interval '5 minutes';

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type, expires_at)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END, exp)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active', 'expires_at', exp);
END $function$;

CREATE OR REPLACE FUNCTION public.api_create_payment_link(_user uuid, _amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  acct public.merchant_accounts%ROWTYPE;
  pick public.merchant_upi_ids%ROWTYPE;
  base numeric(12,2); candidate numeric(12,2); taken numeric[];
  oid text; sl text; row_id uuid; i int; exp timestamptz;
BEGIN
  IF current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role'
     AND auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _amount IS NULL OR _amount <= 0 OR _amount > 1000000 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO acct FROM public.merchant_accounts
   WHERE user_id = _user AND connected ORDER BY connected_at DESC NULLS LAST LIMIT 1;
  IF acct.id IS NULL THEN
    SELECT * INTO acct FROM public.merchant_accounts
     WHERE user_id = _user AND length(btrim(upi_id)) > 0 ORDER BY updated_at DESC LIMIT 1;
  END IF;
  pick := public.pick_merchant_upi(_user);
  IF pick.id IS NOT NULL THEN
    acct.id := COALESCE(acct.id, pick.id);
    acct.provider := pick.provider; acct.upi_id := pick.upi_id;
    acct.payee_name := CASE WHEN pick.payee_name <> '' THEN pick.payee_name ELSE COALESCE(acct.payee_name, '') END;
  END IF;
  IF acct.id IS NULL OR length(btrim(COALESCE(acct.upi_id, ''))) = 0 THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 7));
  PERFORM public.expire_stale_payment_links(_user);

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 0.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 99) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  PERFORM public.consume_qr_quota(_user, 'upi://pay?pa=' || acct.upi_id, acct.upi_id, base, 'Payment link');
  sl  := public.new_payment_slug();
  exp := now() + interval '5 minutes';

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type, expires_at)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END, exp)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active', 'expires_at', exp);
END $function$;