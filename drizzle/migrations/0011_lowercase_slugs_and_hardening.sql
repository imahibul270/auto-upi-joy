-- 1) Slugs must be unique and lowercase-only.
CREATE UNIQUE INDEX IF NOT EXISTS payment_links_slug_key ON public.payment_links (slug);
CREATE INDEX IF NOT EXISTS payment_links_user_status_idx ON public.payment_links (user_id, status);
CREATE INDEX IF NOT EXISTS merchant_accounts_user_connected_idx ON public.merchant_accounts (user_id, connected);

CREATE OR REPLACE FUNCTION public.new_payment_slug()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s text; i int;
BEGIN
  FOR i IN 1..12 LOOP
    s := lower(encode(extensions.gen_random_bytes(6), 'hex'));
    IF NOT EXISTS (SELECT 1 FROM public.payment_links WHERE slug = s) THEN
      RETURN s;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'SLUG_GENERATION_FAILED';
END $function$;

-- 2) Rebuild link creation with lowercase slug + safer amount slotting.
CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
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
  IF acct.id IS NULL THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 7));
  PERFORM public.expire_stale_payment_links(_user);

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ord' || to_char(now(), 'yyyymmdd') || lower(encode(extensions.gen_random_bytes(3), 'hex'));
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
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  acct public.merchant_accounts%ROWTYPE;
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
  IF acct.id IS NULL THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 7));
  PERFORM public.expire_stale_payment_links(_user);

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ord' || to_char(now(), 'yyyymmdd') || lower(encode(extensions.gen_random_bytes(3), 'hex'));
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

-- 3) Public lookups are case-insensitive so old mixed-case links keep working.
CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.payment_links WHERE slug = _slug LIMIT 1;
  IF r.id IS NULL THEN
    SELECT * INTO r FROM public.payment_links WHERE lower(slug) = lower(_slug) LIMIT 1;
  END IF;
  IF r.id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;

  IF r.status = 'active' AND r.expires_at <= now() THEN
    UPDATE public.payment_links SET status = 'expired' WHERE id = r.id AND status = 'active';
    r.status := 'expired';
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'order_id', r.order_id,
    'slug', r.slug,
    'customer_name', r.customer_name,
    'amount', r.amount,
    'payable_amount', r.payable_amount,
    'upi_id', r.upi_id,
    'payee_name', r.payee_name,
    'status', r.status,
    'expires_at', r.expires_at,
    'server_now', now()
  );
END $function$;

CREATE OR REPLACE FUNCTION public.register_payment_link_click(_slug text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE public.payment_links SET clicks = clicks + 1 WHERE lower(slug) = lower(_slug);
$function$;