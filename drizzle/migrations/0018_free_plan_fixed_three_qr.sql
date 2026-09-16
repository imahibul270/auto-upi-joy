-- Free plan is always exactly 3 QR codes, regardless of any manual qr_limit.
CREATE OR REPLACE FUNCTION public.consume_qr_quota(_user uuid, _payload text, _upi_id text DEFAULT '', _amount numeric DEFAULT NULL, _label text DEFAULT 'Payment link')
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE s public.subscriptions%ROWTYPE; lim INT := 3; used INT := 0; since TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 0));
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    lim := COALESCE(s.qr_limit, 3000); since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := 3; since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  IF used >= lim THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label, 'Payment link'), COALESCE(_upi_id, ''), _amount, _payload);
END $function$;

CREATE OR REPLACE FUNCTION public.get_qr_quota()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _user UUID := auth.uid();
  s public.subscriptions%ROWTYPE;
  tier TEXT := 'free'; lim INT := 3; used INT := 0;
  pstart TIMESTAMPTZ; pend TIMESTAMPTZ; since TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;
  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    tier := 'pro'; lim := COALESCE(s.qr_limit, 3000); pstart := s.started_at; pend := s.expires_at;
    since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    tier := 'free'; lim := 3;
    since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  RETURN jsonb_build_object(
    'plan', tier, 'limit', lim, 'used', used,
    'remaining', GREATEST(lim - used, 0),
    'period_start', pstart, 'period_end', pend,
    'price_inr', 299, 'can_generate', (lim - used) > 0
  );
END; $$;
REVOKE ALL ON FUNCTION public.get_qr_quota() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_qr_quota() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.generate_qr(_payload TEXT, _label TEXT DEFAULT '', _upi_id TEXT DEFAULT '', _amount NUMERIC DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $$
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
    lim := COALESCE(s.qr_limit, 3000); since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := 3; since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;
  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  IF used >= lim THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label,''), COALESCE(_upi_id,''), _amount, _payload)
  RETURNING id INTO row_id;
  RETURN jsonb_build_object('id', row_id, 'plan', CASE WHEN lim > 3 THEN 'pro' ELSE 'free' END, 'limit', lim, 'used', used + 1, 'remaining', GREATEST(lim - used - 1, 0));
END; $$;
REVOKE ALL ON FUNCTION public.generate_qr(TEXT, TEXT, TEXT, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_qr(TEXT, TEXT, TEXT, NUMERIC) TO authenticated, service_role;
