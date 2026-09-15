-- Every active payment link of a merchant must have a globally unique payable
-- amount, so an alert email can only ever settle exactly one order.

CREATE UNIQUE INDEX IF NOT EXISTS payment_links_active_amount_uniq
  ON public.payment_links (user_id, payable_amount)
  WHERE status = 'active';

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2);
  candidate numeric(12,2);
  taken numeric[];
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

  -- Always append a unique paise marker: the exact base amount is never used,
  -- so a random incoming payment of the plain amount can never be captured.
  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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

-- Detection helper used by the mail poller: amount must match to the paisa and
-- the email must be newer than the link, else nothing is settled.
CREATE OR REPLACE FUNCTION public.record_detected_payment(_user uuid, _amount numeric, _payer text DEFAULT NULL::text, _email_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE; n int;
BEGIN
  IF _email_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.payment_links WHERE paid_email_id = _email_id) THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'duplicate_email');
  END IF;

  SELECT count(*) INTO n FROM public.payment_links
   WHERE user_id = _user AND status = 'active' AND payable_amount = round(_amount, 2);
  IF n <> 1 THEN
    RETURN jsonb_build_object('matched', false, 'reason', CASE WHEN n = 0 THEN 'no_match' ELSE 'ambiguous' END);
  END IF;

  SELECT * INTO r FROM public.payment_links
   WHERE user_id = _user AND status = 'active' AND payable_amount = round(_amount, 2)
   LIMIT 1;

  UPDATE public.payment_links
     SET status = CASE WHEN link_type = 'reusable' THEN status ELSE 'paid'::public.link_status END,
         paid_at = now(), detected_at = now(), paid_count = paid_count + 1,
         payer_name = _payer, paid_email_id = _email_id
   WHERE id = r.id AND status = 'active' AND paid_email_id IS NULL;

  IF NOT FOUND THEN RETURN jsonb_build_object('matched', false, 'reason', 'race'); END IF;
  RETURN jsonb_build_object('matched', true, 'order_id', r.order_id, 'amount', r.payable_amount);
END $function$;