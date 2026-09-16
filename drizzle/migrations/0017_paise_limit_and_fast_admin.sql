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

CREATE INDEX IF NOT EXISTS payment_links_user_status_idx ON public.payment_links (user_id, status);
CREATE INDEX IF NOT EXISTS qr_codes_user_created_idx ON public.qr_codes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS merchant_accounts_user_connected_idx ON public.merchant_accounts (user_id, connected);

CREATE OR REPLACE FUNCTION public.admin_list_users(_search text DEFAULT ''::text, _limit int DEFAULT 100, _plan text DEFAULT ''::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  result jsonb;
  q text := btrim(COALESCE(_search, ''));
  lim int := LEAST(GREATEST(COALESCE(_limit, 100), 1), 500);
BEGIN
  IF NOT public.is_platform_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;

  WITH picked AS (
    SELECT u.id, u.email, u.created_at,
           COALESCE(p.full_name, '') AS full_name,
           COALESCE(p.mobile, '') AS mobile,
           s.plan, s.started_at, s.expires_at, s.qr_limit, s.amount_inr
      FROM auth.users u
      LEFT JOIN public.profiles p ON p.id = u.id
      LEFT JOIN public.subscriptions s ON s.user_id = u.id
     WHERE (q = '' OR u.email ILIKE '%' || q || '%'
                   OR COALESCE(p.full_name, '') ILIKE '%' || q || '%'
                   OR COALESCE(p.mobile, '') ILIKE '%' || q || '%')
       AND (COALESCE(_plan, '') <> 'pro' OR (s.plan = 'pro' AND s.expires_at > now()))
     ORDER BY u.created_at DESC
     LIMIT lim
  ),
  links AS (
    SELECT l.user_id,
           count(*) AS links_total,
           count(*) FILTER (WHERE l.status = 'paid') AS links_paid,
           COALESCE(sum(l.amount) FILTER (WHERE l.status = 'paid'), 0) AS revenue
      FROM public.payment_links l
      JOIN picked ON picked.id = l.user_id
     GROUP BY l.user_id
  ),
  qrs AS (
    SELECT c.user_id, count(*) AS qr_used
      FROM public.qr_codes c
      JOIN picked ON picked.id = c.user_id
     WHERE c.created_at >= CASE WHEN picked.plan = 'pro' AND picked.expires_at > now()
                                THEN COALESCE(picked.started_at, '-infinity'::timestamptz)
                                ELSE COALESCE(picked.expires_at, '-infinity'::timestamptz) END
     GROUP BY c.user_id
  ),
  accts AS (
    SELECT m.user_id, count(*) AS connected_accounts
      FROM public.merchant_accounts m
      JOIN picked ON picked.id = m.user_id
     WHERE m.connected
     GROUP BY m.user_id
  )
  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC), '[]'::jsonb) INTO result
  FROM (
    SELECT picked.id AS user_id, picked.email, picked.created_at, picked.full_name, picked.mobile,
           CASE WHEN picked.plan = 'pro' AND picked.expires_at > now() THEN 'pro' ELSE 'free' END AS plan,
           picked.started_at, picked.expires_at,
           COALESCE(picked.qr_limit, CASE WHEN picked.plan = 'pro' AND picked.expires_at > now() THEN 3000 ELSE 3 END) AS qr_limit,
           picked.amount_inr,
           COALESCE(qrs.qr_used, 0) AS qr_used,
           COALESCE(links.links_total, 0) AS links_total,
           COALESCE(links.links_paid, 0) AS links_paid,
           COALESCE(links.revenue, 0) AS revenue,
           COALESCE(accts.connected_accounts, 0) AS connected_accounts
      FROM picked
      LEFT JOIN links ON links.user_id = picked.id
      LEFT JOIN qrs ON qrs.user_id = picked.id
      LEFT JOIN accts ON accts.user_id = picked.id
  ) t;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users(text, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, int, text) TO authenticated, service_role;