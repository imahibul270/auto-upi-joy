-- Admin-managed sending mailbox (SMTP app password) + signup OTP codes.

CREATE TABLE IF NOT EXISTS public.email_source (
  id text PRIMARY KEY DEFAULT 'smtp',
  host text NOT NULL DEFAULT 'smtp.gmail.com',
  port int NOT NULL DEFAULT 465,
  email text NOT NULL,
  app_password text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.email_source TO service_role;
ALTER TABLE public.email_source ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: only service_role and SECURITY DEFINER functions may touch it.

CREATE TABLE IF NOT EXISTS public.signup_otps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempts int NOT NULL DEFAULT 0,
  consumed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS signup_otps_email_idx ON public.signup_otps (email, created_at DESC);

GRANT ALL ON public.signup_otps TO service_role;
ALTER TABLE public.signup_otps ENABLE ROW LEVEL SECURITY;
-- No policies: OTP rows are only read/written by the server.

CREATE OR REPLACE FUNCTION public.admin_get_email_source()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r public.email_source;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;
  SELECT * INTO r FROM public.email_source WHERE id = 'smtp';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('connected', false);
  END IF;
  RETURN jsonb_build_object(
    'connected', true,
    'email', r.email,
    'host', r.host,
    'port', r.port,
    'updated_at', r.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_email_source(
  _email text,
  _password text,
  _host text DEFAULT 'smtp.gmail.com',
  _port int DEFAULT 465
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;
  IF _email IS NULL OR length(trim(_email)) < 5 OR _password IS NULL OR length(trim(_password)) < 6 THEN
    RAISE EXCEPTION 'email and app password are required';
  END IF;
  INSERT INTO public.email_source (id, host, port, email, app_password, updated_at)
  VALUES ('smtp', COALESCE(NULLIF(trim(_host), ''), 'smtp.gmail.com'), COALESCE(_port, 465), lower(trim(_email)), trim(_password), now())
  ON CONFLICT (id) DO UPDATE
    SET host = EXCLUDED.host,
        port = EXCLUDED.port,
        email = EXCLUDED.email,
        app_password = EXCLUDED.app_password,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_clear_email_source()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;
  DELETE FROM public.email_source WHERE id = 'smtp';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_email_source() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_email_source(text, text, text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clear_email_source() TO authenticated;