-- Free tier counting must never depend on a future-dated expiry date.
-- A 'free' row with expires_at in the future previously made the used-count
-- window start in the future, so every free user counted 0 used QR codes
-- and could generate unlimited links from the dashboard and the API.

CREATE OR REPLACE FUNCTION public.quota_window_start(s public.subscriptions)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now()
      THEN COALESCE(s.started_at, '-infinity'::timestamptz)
    WHEN s.expires_at IS NOT NULL AND s.expires_at <= now()
      THEN s.expires_at
    ELSE '-infinity'::timestamptz
  END
$$;

CREATE OR REPLACE FUNCTION public.get_qr_quota()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _user UUID := auth.uid();
  s public.subscriptions%ROWTYPE;
  tier TEXT := 'free'; lim INT := 3; used INT := 0;
  pstart TIMESTAMPTZ; pend TIMESTAMPTZ; since TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    tier := 'pro'; lim := COALESCE(NULLIF(s.qr_limit, 0), 3000); pstart := s.started_at; pend := s.expires_at;
  ELSE
    tier := 'free'; lim := 3;
  END IF;
  since := public.quota_window_start(s);
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  RETURN jsonb_build_object(
    'plan', tier, 'limit', lim, 'used', used,
    'remaining', GREATEST(lim - used, 0),
    'period_start', pstart, 'period_end', pend,
    'price_inr', public.get_pro_price(), 'can_generate', (lim - used) > 0
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.consume_qr_quota(_user uuid, _payload text, _upi_id text DEFAULT ''::text, _amount numeric DEFAULT NULL::numeric, _label text DEFAULT 'Payment link'::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE s public.subscriptions%ROWTYPE; lim INT := 3; used INT := 0; since TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 0));
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    lim := COALESCE(NULLIF(s.qr_limit, 0), 3000);
  ELSE
    lim := 3;
  END IF;
  since := public.quota_window_start(s);
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  IF used >= lim THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label, 'Payment link'), COALESCE(_upi_id, ''), _amount, _payload);
END $function$;

CREATE OR REPLACE FUNCTION public.generate_qr(_payload text, _label text DEFAULT ''::text, _upi_id text DEFAULT ''::text, _amount numeric DEFAULT NULL::numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _user UUID := auth.uid();
  s public.subscriptions%ROWTYPE;
  lim INT := 3; used INT := 0; since TIMESTAMPTZ; row_id UUID;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _payload IS NULL OR length(btrim(_payload)) = 0 THEN RAISE EXCEPTION 'INVALID_PAYLOAD'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 0));
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    lim := COALESCE(NULLIF(s.qr_limit, 0), 3000);
  ELSE
    lim := 3;
  END IF;
  since := public.quota_window_start(s);
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  IF used >= lim THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label,''), COALESCE(_upi_id,''), _amount, _payload)
  RETURNING id INTO row_id;
  RETURN jsonb_build_object('id', row_id, 'plan', CASE WHEN lim > 3 THEN 'pro' ELSE 'free' END,
    'limit', lim, 'used', used + 1, 'remaining', GREATEST(lim - used - 1, 0));
END; $function$;

-- A paid upgrade always gets the full Pro allowance.
CREATE OR REPLACE FUNCTION public.activate_pro_subscription(_user uuid, _reference text DEFAULT NULL::text, _amount numeric DEFAULT 299)
RETURNS subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE out_row public.subscriptions%ROWTYPE;
BEGIN
  INSERT INTO public.subscriptions (user_id, plan, started_at, expires_at, amount_inr, reference, qr_limit)
  VALUES (_user, 'pro', now(), now() + interval '30 days', _amount, _reference, NULL)
  ON CONFLICT (user_id) DO UPDATE
    SET plan = 'pro',
        started_at = now(),
        expires_at = GREATEST(COALESCE(public.subscriptions.expires_at, now()), now()) + interval '30 days',
        amount_inr = EXCLUDED.amount_inr,
        reference = EXCLUDED.reference,
        qr_limit = NULL
  RETURNING * INTO out_row;
  RETURN out_row;
END; $function$;

-- Admin downgrades to Free must clear the paid validity and custom limit.
CREATE OR REPLACE FUNCTION public.admin_set_plan(_user uuid, _plan text, _days integer DEFAULT 30, _qr_limit integer DEFAULT NULL::integer, _amount numeric DEFAULT 299, _reset_usage boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE lim INT := NULLIF(_qr_limit, 0);
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
    VALUES (_user, 'free', now(), CASE WHEN _reset_usage THEN now() ELSE NULL END, 0, 'admin_manual', NULL)
    ON CONFLICT (user_id) DO UPDATE
      SET plan = 'free',
          expires_at = CASE WHEN _reset_usage THEN now() ELSE NULL END,
          amount_inr = 0,
          reference = 'admin_manual',
          qr_limit = NULL;
  END IF;

  RETURN jsonb_build_object('ok', true);
END; $function$;

-- Repair existing bad rows: free plans must not carry a future validity date.
UPDATE public.subscriptions
   SET expires_at = NULL, qr_limit = NULL
 WHERE plan = 'free' AND expires_at IS NOT NULL AND expires_at > now();