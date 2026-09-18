-- Plan validity now ends at midnight (00:00 Asia/Kolkata), not at the clock time of purchase.

CREATE OR REPLACE FUNCTION public.plan_expiry_at(_base timestamptz, _days integer)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (date_trunc('day', _base AT TIME ZONE 'Asia/Kolkata')
          + make_interval(days => GREATEST(COALESCE(_days, 30), 1))) AT TIME ZONE 'Asia/Kolkata';
$$;

GRANT EXECUTE ON FUNCTION public.plan_expiry_at(timestamptz, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.activate_pro_subscription(_user uuid, _reference text DEFAULT NULL::text, _amount numeric DEFAULT 299)
RETURNS subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE out_row public.subscriptions%ROWTYPE;
BEGIN
  INSERT INTO public.subscriptions (user_id, plan, started_at, expires_at, amount_inr, reference, qr_limit)
  VALUES (_user, 'pro', now(), public.plan_expiry_at(now(), 30), _amount, _reference, NULL)
  ON CONFLICT (user_id) DO UPDATE
    SET plan = 'pro',
        started_at = now(),
        expires_at = public.plan_expiry_at(
          GREATEST(COALESCE(public.subscriptions.expires_at, now()), now()), 30),
        amount_inr = EXCLUDED.amount_inr,
        reference = EXCLUDED.reference,
        qr_limit = NULL
  RETURNING * INTO out_row;
  RETURN out_row;
END; $function$;

REVOKE ALL ON FUNCTION public.activate_pro_subscription(UUID, TEXT, NUMERIC) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_pro_subscription(UUID, TEXT, NUMERIC) TO service_role;

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
    VALUES (_user, 'pro', now(), public.plan_expiry_at(now(), _days),
            COALESCE(_amount, 299), 'admin_manual', lim)
    ON CONFLICT (user_id) DO UPDATE
      SET plan = 'pro',
          started_at = CASE WHEN _reset_usage OR public.subscriptions.plan <> 'pro' THEN now() ELSE public.subscriptions.started_at END,
          expires_at = public.plan_expiry_at(now(), _days),
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
  secs BIGINT := 0; dleft INT := 0;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    tier := 'pro'; lim := COALESCE(NULLIF(s.qr_limit, 0), 3000); pstart := s.started_at; pend := s.expires_at;
    secs := GREATEST(EXTRACT(EPOCH FROM (s.expires_at - now()))::BIGINT, 0);
    -- Calendar days (India time): the day ends at midnight, not at the purchase clock time.
    dleft := GREATEST(
      ((s.expires_at AT TIME ZONE 'Asia/Kolkata')::date - (now() AT TIME ZONE 'Asia/Kolkata')::date), 0);
  ELSE
    tier := 'free'; lim := CASE WHEN public.is_free_plan_enabled() THEN 3 ELSE 0 END;
    secs := 0; dleft := 0;
  END IF;
  since := public.quota_window_start(s);
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  RETURN jsonb_build_object(
    'plan', tier, 'limit', lim, 'used', used,
    'remaining', GREATEST(lim - used, 0),
    'period_start', pstart, 'period_end', pend,
    'days_left', dleft, 'seconds_left', secs, 'server_now', now(),
    'price_inr', public.get_pro_price(), 'can_generate', (lim - used) > 0
  );
END;
$function$;

-- Backfill: move every running Pro plan to the midnight after its current expiry (never shortens a plan).
UPDATE public.subscriptions
   SET expires_at = (date_trunc('day', expires_at AT TIME ZONE 'Asia/Kolkata') + interval '1 day') AT TIME ZONE 'Asia/Kolkata'
 WHERE plan = 'pro'
   AND expires_at IS NOT NULL
   AND expires_at > now()
   AND expires_at <> (date_trunc('day', expires_at AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata';