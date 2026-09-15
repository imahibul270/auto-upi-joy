-- Plan tiers
DO $$ BEGIN
  CREATE TYPE public.plan_tier AS ENUM ('free','pro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- One subscription row per user
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL UNIQUE,
  plan        public.plan_tier NOT NULL DEFAULT 'free',
  started_at  TIMESTAMPTZ,
  expires_at  TIMESTAMPTZ,
  amount_inr  NUMERIC(10,2),
  reference   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Every generated QR is recorded here; this is the single source of truth for usage
CREATE TABLE IF NOT EXISTS public.qr_codes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL,
  label       TEXT NOT NULL DEFAULT '',
  upi_id      TEXT NOT NULL DEFAULT '',
  amount      NUMERIC(12,2),
  payload     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS qr_codes_user_created_idx ON public.qr_codes (user_id, created_at DESC);

-- Grants: read-only for the signed-in owner. No direct INSERT/UPDATE/DELETE,
-- so usage can only grow through the quota-checked function below.
GRANT SELECT ON public.subscriptions TO authenticated;
GRANT ALL    ON public.subscriptions TO service_role;
GRANT SELECT ON public.qr_codes TO authenticated;
GRANT ALL    ON public.qr_codes TO service_role;

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qr_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own subscription" ON public.subscriptions;
CREATE POLICY "Users read own subscription" ON public.subscriptions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read own qr codes" ON public.qr_codes;
CREATE POLICY "Users read own qr codes" ON public.qr_codes
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS subscriptions_set_updated_at ON public.subscriptions;
CREATE TRIGGER subscriptions_set_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------------
-- Quota reader
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_qr_quota()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
    tier := 'pro'; lim := 3000; pstart := s.started_at; pend := s.expires_at;
    since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    -- free tier: 3 lifetime QRs, counted after any expired paid period
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
$$;

-- ------------------------------------------------------------------
-- The ONLY way a QR row can be created: quota is checked inside the
-- same transaction, under a per-user advisory lock (no race bypass).
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_qr(_payload TEXT, _label TEXT DEFAULT '', _upi_id TEXT DEFAULT '', _amount NUMERIC DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
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
    lim := 3000; since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := 3; since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;

  SELECT count(*) INTO used FROM public.qr_codes
   WHERE user_id = _user AND created_at >= since;

  IF used >= lim THEN
    RAISE EXCEPTION 'QUOTA_EXCEEDED';
  END IF;

  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label,''), COALESCE(_upi_id,''), _amount, _payload)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object(
    'id', row_id,
    'payload', _payload,
    'used', used + 1,
    'limit', lim,
    'remaining', lim - used - 1
  );
END;
$$;

-- ------------------------------------------------------------------
-- Activation: privileged only (payment webhook / admin), never the client.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.activate_pro_subscription(_user UUID, _reference TEXT DEFAULT NULL, _amount NUMERIC DEFAULT 299)
RETURNS public.subscriptions
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  out_row public.subscriptions%ROWTYPE;
BEGIN
  INSERT INTO public.subscriptions (user_id, plan, started_at, expires_at, amount_inr, reference)
  VALUES (_user, 'pro', now(), now() + interval '30 days', _amount, _reference)
  ON CONFLICT (user_id) DO UPDATE
    SET plan = 'pro',
        started_at = now(),
        expires_at = GREATEST(COALESCE(public.subscriptions.expires_at, now()), now()) + interval '30 days',
        amount_inr = EXCLUDED.amount_inr,
        reference = EXCLUDED.reference
  RETURNING * INTO out_row;
  RETURN out_row;
END;
$$;

REVOKE ALL ON FUNCTION public.get_qr_quota() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.generate_qr(TEXT, TEXT, TEXT, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_pro_subscription(UUID, TEXT, NUMERIC) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_qr_quota() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.generate_qr(TEXT, TEXT, TEXT, NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_pro_subscription(UUID, TEXT, NUMERIC) TO service_role;
