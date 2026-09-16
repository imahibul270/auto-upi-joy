-- Per-user manual QR limit override, managed from the admin panel.
ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS qr_limit INT;

-- Hardcoded single admin. No table, no role assignment: nobody else can ever be admin.
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT lower(coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''))
         = 'aminulislam78131@gmail.com'
     AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'authenticated';
$$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated, service_role;

-- Quota now honours the manual override set by the admin.
CREATE OR REPLACE FUNCTION public.get_qr_quota()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _user   UUID := auth.uid();
  s       public.subscriptions%ROWTYPE;
  tier    TEXT := 'free';
  lim     INT  := 3;
  used    INT  := 0;
  pstart  TIMESTAMPTZ;
  pend    TIMESTAMPTZ;
  since   TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;

  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    tier := 'pro'; lim := COALESCE(s.qr_limit, 3000); pstart := s.started_at; pend := s.expires_at;
    since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := COALESCE(s.qr_limit, 3);
    since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;

  SELECT count(*) INTO used FROM public.qr_codes
   WHERE user_id = _user AND created_at >= since;

  RETURN jsonb_build_object(
    'plan', tier,
    'limit', lim,
    'used', used,
    'remaining', GREATEST(lim - used, 0),
    'period_start', pstart,
    'period_end', pend,
    'price_inr', 299,
    'can_generate', (lim - used) > 0
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.generate_qr(_payload text, _label text DEFAULT ''::text, _upi_id text DEFAULT ''::text, _amount numeric DEFAULT NULL::numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _user UUID := auth.uid();
  s     public.subscriptions%ROWTYPE;
  lim   INT := 3;
  used  INT := 0;
  since TIMESTAMPTZ;
  row_id UUID;
BEGIN
  IF _user IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  IF _payload IS NULL OR length(btrim(_payload)) = 0 THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 0));

  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;

  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    lim := COALESCE(s.qr_limit, 3000); since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := COALESCE(s.qr_limit, 3); since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;

  SELECT count(*) INTO used FROM public.qr_codes
   WHERE user_id = _user AND created_at >= since;

  IF used >= lim THEN
    RAISE EXCEPTION 'QUOTA_EXCEEDED';
  END IF;

  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label,''), COALESCE(_upi_id,''), _amount, _payload)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'payload', _payload, 'used', used + 1, 'limit', lim, 'remaining', lim - used - 1);
END;
$function$;

-- Admin: full user list with plan + usage.
CREATE OR REPLACE FUNCTION public.admin_list_users()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.is_platform_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC), '[]'::jsonb) INTO result
  FROM (
    SELECT
      u.id AS user_id,
      u.email,
      u.created_at,
      COALESCE(p.full_name, '') AS full_name,
      COALESCE(p.mobile, '') AS mobile,
      CASE WHEN s.plan = 'pro' AND s.expires_at > now() THEN 'pro' ELSE 'free' END AS plan,
      s.started_at,
      s.expires_at,
      COALESCE(s.qr_limit, CASE WHEN s.plan = 'pro' AND s.expires_at > now() THEN 3000 ELSE 3 END) AS qr_limit,
      s.amount_inr,
      (SELECT count(*) FROM public.qr_codes q
        WHERE q.user_id = u.id
          AND q.created_at >= CASE WHEN s.plan = 'pro' AND s.expires_at > now()
                                   THEN COALESCE(s.started_at, '-infinity'::timestamptz)
                                   ELSE COALESCE(s.expires_at, '-infinity'::timestamptz) END) AS qr_used,
      (SELECT count(*) FROM public.payment_links l WHERE l.user_id = u.id) AS links_total,
      (SELECT count(*) FROM public.payment_links l WHERE l.user_id = u.id AND l.status = 'paid') AS links_paid,
      (SELECT COALESCE(sum(l.amount), 0) FROM public.payment_links l WHERE l.user_id = u.id AND l.status = 'paid') AS revenue,
      (SELECT count(*) FROM public.merchant_accounts m WHERE m.user_id = u.id AND m.connected) AS connected_accounts
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    LEFT JOIN public.subscriptions s ON s.user_id = u.id
  ) t;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users() TO authenticated, service_role;

-- Admin: platform-wide totals.
CREATE OR REPLACE FUNCTION public.admin_overview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  RETURN jsonb_build_object(
    'users', (SELECT count(*) FROM auth.users),
    'pro_users', (SELECT count(*) FROM public.subscriptions WHERE plan = 'pro' AND expires_at > now()),
    'qr_codes', (SELECT count(*) FROM public.qr_codes),
    'links', (SELECT count(*) FROM public.payment_links),
    'paid_links', (SELECT count(*) FROM public.payment_links WHERE status = 'paid'),
    'revenue', (SELECT COALESCE(sum(amount), 0) FROM public.payment_links WHERE status = 'paid'),
    'subscription_revenue', (SELECT COALESCE(sum(amount_inr), 0) FROM public.subscriptions WHERE plan = 'pro')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_overview() TO authenticated, service_role;

-- Admin: set a user's plan, validity days, QR limit and paid amount manually.
CREATE OR REPLACE FUNCTION public.admin_set_plan(
  _user uuid,
  _plan text,
  _days int DEFAULT 30,
  _qr_limit int DEFAULT NULL,
  _amount numeric DEFAULT 299,
  _reset_usage boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  lim INT := NULLIF(_qr_limit, 0);
BEGIN
  IF NOT public.is_platform_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  IF _user IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = _user) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF _plan NOT IN ('free', 'pro') THEN RAISE EXCEPTION 'INVALID_PLAN'; END IF;
  IF lim IS NOT NULL AND (lim < 0 OR lim > 1000000) THEN RAISE EXCEPTION 'INVALID_LIMIT'; END IF;

  IF _plan = 'pro' THEN
    INSERT INTO public.subscriptions (user_id, plan, started_at, expires_at, amount_inr, reference, qr_limit)
    VALUES (_user, 'pro', now(), now() + make_interval(days => GREATEST(COALESCE(_days, 30), 1)),
            COALESCE(_amount, 299), 'admin_manual', lim)
    ON CONFLICT (user_id) DO UPDATE
      SET plan = 'pro',
          started_at = CASE WHEN _reset_usage OR public.subscriptions.plan <> 'pro' THEN now() ELSE public.subscriptions.started_at END,
          expires_at = now() + make_interval(days => GREATEST(COALESCE(_days, 30), 1)),
          amount_inr = COALESCE(_amount, 299),
          reference = 'admin_manual',
          qr_limit = lim;
  ELSE
    INSERT INTO public.subscriptions (user_id, plan, started_at, expires_at, amount_inr, reference, qr_limit)
    VALUES (_user, 'free', now(), CASE WHEN _reset_usage THEN now() ELSE NULL END, 0, 'admin_manual', lim)
    ON CONFLICT (user_id) DO UPDATE
      SET plan = 'free',
          expires_at = CASE WHEN _reset_usage THEN now() ELSE public.subscriptions.expires_at END,
          amount_inr = 0,
          reference = 'admin_manual',
          qr_limit = lim;
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_plan(uuid, text, int, int, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_plan(uuid, text, int, int, numeric, boolean) TO authenticated, service_role;