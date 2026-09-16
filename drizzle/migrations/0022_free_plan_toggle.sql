CREATE OR REPLACE FUNCTION public.is_free_plan_enabled()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT value FROM public.platform_settings WHERE key = 'free_plan_enabled'), 1) <> 0;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_free_plan_enabled(_enabled boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  INSERT INTO public.platform_settings (key, value, updated_at)
  VALUES ('free_plan_enabled', CASE WHEN _enabled THEN 1 ELSE 0 END, now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  RETURN _enabled;
END;
$function$;

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
    tier := 'free'; lim := CASE WHEN public.is_free_plan_enabled() THEN 3 ELSE 0 END;
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
    lim := CASE WHEN public.is_free_plan_enabled() THEN 3 ELSE 0 END;
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
    lim := CASE WHEN public.is_free_plan_enabled() THEN 3 ELSE 0 END;
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