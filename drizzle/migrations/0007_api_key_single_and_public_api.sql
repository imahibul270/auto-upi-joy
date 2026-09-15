-- Keep only one API key per user: regenerating removes the old row entirely.
CREATE OR REPLACE FUNCTION public.issue_api_key(_label text DEFAULT 'Default key')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _user uuid := auth.uid(); raw text; secret text; pfx text; row_id uuid;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  raw := 'aupi_live_' || encode(extensions.gen_random_bytes(24), 'hex');
  secret := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
  pfx := left(raw, 18);

  DELETE FROM public.api_keys WHERE user_id = _user;

  INSERT INTO public.api_keys (user_id, label, key_prefix, key_hash, webhook_secret)
  VALUES (_user, COALESCE(NULLIF(btrim(_label), ''), 'Default key'), pfx,
          encode(extensions.digest(raw, 'sha256'), 'hex'), secret)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'api_key', raw, 'key_prefix', pfx, 'webhook_secret', secret);
END $$;

-- Clear historic revoked keys.
DELETE FROM public.api_keys WHERE active = false;

-- Server-side payment link creation for the public REST API (service role only).
CREATE OR REPLACE FUNCTION public.api_create_payment_link(_user uuid, _amount numeric, _customer_name text DEFAULT '', _link_type text DEFAULT 'one_time')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2); candidate numeric(12,2); taken numeric[];
  oid text; sl text; row_id uuid; i int;
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

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN 1..299 LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active');
END $$;

REVOKE ALL ON FUNCTION public.api_create_payment_link(uuid, numeric, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_create_payment_link(uuid, numeric, text, text) TO service_role;