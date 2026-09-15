-- =====================================================================
-- Auto Upi — Complete Backend Setup (Supabase / PostgreSQL)
-- =====================================================================
-- HOW TO USE
--   1. Create a Supabase project (cloud or self-hosted).
--   2. Open SQL Editor -> New query.
--   3. Paste this ENTIRE file and press RUN.
--   4. Done. No other SQL file needs to be run.
--
-- This script is IDEMPOTENT: running it twice is safe.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY,
  full_name   TEXT NOT NULL DEFAULT '',
  mobile      TEXT NOT NULL DEFAULT '',
  business_logo TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS business_logo TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_business_logo_size'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_business_logo_size
      CHECK (business_logo IS NULL OR length(business_logo) <= 700000);
  END IF;
END $$;

COMMENT ON TABLE public.profiles IS 'One row per registered user. id matches auth.users.id';

-- ---------------------------------------------------------------------
-- 2. Grants (REQUIRED — PostgREST has no default privileges on public)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;

-- ---------------------------------------------------------------------
-- 3. Row Level Security
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own profile"   ON public.profiles;
DROP POLICY IF EXISTS "Users can create their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;

CREATE POLICY "Users can read their own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can create their own profile"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ---------------------------------------------------------------------
-- 4. Auto-fill updated_at
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------
-- 5. Create a profile automatically on sign-up
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, mobile)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'mobile', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =====================================================================
-- Setup complete.
-- =====================================================================

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

-- =====================================================================
-- Plan / QR quota system added.
-- =====================================================================

-- ============================================================
-- 0006 Gmail payment detection
-- ============================================================

-- Payment link lifecycle columns
ALTER TABLE public.payment_links
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS payer_email text,
  ADD COLUMN IF NOT EXISTS detected_at timestamptz;

UPDATE public.payment_links SET expires_at = created_at + interval '24 hours' WHERE expires_at IS NULL;

ALTER TABLE public.payment_links
  ALTER COLUMN expires_at SET DEFAULT (now() + interval '15 minutes'),
  ALTER COLUMN expires_at SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS payment_links_paid_email_id_key
  ON public.payment_links (paid_email_id) WHERE paid_email_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS payment_links_active_amount_idx
  ON public.payment_links (user_id, status, payable_amount);

-- Per-user Gmail OAuth connection (server-only table)
CREATE TABLE IF NOT EXISTS public.gmail_connections (
  user_id uuid PRIMARY KEY,
  oauth_client_id text,
  oauth_client_secret text,
  access_token text,
  refresh_token text,
  token_expires_at timestamptz,
  scope text,
  email text,
  status text NOT NULL DEFAULT 'credentials_only',
  connected_at timestamptz,
  last_polled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.gmail_connections TO service_role;
ALTER TABLE public.gmail_connections ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS gmail_connections_set_updated_at ON public.gmail_connections;
CREATE TRIGGER gmail_connections_set_updated_at
  BEFORE UPDATE ON public.gmail_connections
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Dedupe ledger for processed payment alert emails (server-only table)
CREATE TABLE IF NOT EXISTS public.processed_emails (
  message_id text PRIMARY KEY,
  user_id uuid,
  link_id uuid,
  amount numeric(12,2),
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.processed_emails TO service_role;
ALTER TABLE public.processed_emails ENABLE ROW LEVEL SECURITY;

-- Expire stale active links
CREATE OR REPLACE FUNCTION public.expire_stale_payment_links(_user uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE n integer;
BEGIN
  UPDATE public.payment_links
     SET status = 'expired'
   WHERE status = 'active'
     AND expires_at < now()
     AND (_user IS NULL OR user_id = _user);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

REVOKE ALL ON FUNCTION public.expire_stale_payment_links(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_payment_links(uuid) TO service_role;
-- ============================================================
-- 0010 Signed webhook delivery for paid orders
-- ============================================================
ALTER TABLE public.payment_links
  ADD COLUMN IF NOT EXISTS webhook_url text,
  ADD COLUMN IF NOT EXISTS webhook_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS webhook_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS webhook_last_error text;
