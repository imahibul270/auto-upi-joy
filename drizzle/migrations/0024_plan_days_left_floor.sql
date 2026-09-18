CREATE OR REPLACE FUNCTION public.get_qr_quota()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
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
    dleft := FLOOR(secs / 86400.0)::INT;
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
$$;