-- =====================================================================
-- Auto Upi — COMPLETE DATABASE SETUP (run once on a NEW, empty Supabase project)
-- Paste this whole file in Supabase > SQL Editor > New query > Run.
-- ADMIN EMAIL: search this file for  aminulislam78131@gmail.com  and replace it
-- with your own email (only one place). See database/GUIDE.md section 6.
-- =====================================================================

-- ---------- 0000_create_user_profiles.sql ----------
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY,
  full_name TEXT NOT NULL DEFAULT '',
  mobile TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own profile"
ON public.profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Users can create their own profile"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
ON public.profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);
-- ---------- 0001_add_profile_triggers.sql ----------
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
-- ---------- 0002_add_business_logo_to_profiles.sql ----------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS business_logo TEXT;

COMMENT ON COLUMN public.profiles.business_logo IS 'Merchant-provided business logo stored as a validated image data URL.';
-- ---------- 0003_validate_business_logo_size.sql ----------
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
-- ---------- 0004_qr_quota_and_subscriptions.sql ----------
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

-- ---------- 0005_gateway_accounts_api_keys_payment_links.sql ----------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ============ merchant accounts (PhonePe / Paytm) ============
DO $$ BEGIN
  CREATE TYPE public.upi_provider AS ENUM ('phonepe','paytm');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.merchant_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  provider public.upi_provider NOT NULL,
  upi_id text NOT NULL DEFAULT '',
  payee_name text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  app_password text NOT NULL DEFAULT '',
  connected boolean NOT NULL DEFAULT false,
  connected_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, provider)
);

GRANT SELECT (id, user_id, provider, upi_id, payee_name, email, connected, connected_at, created_at, updated_at)
  ON public.merchant_accounts TO authenticated;
GRANT ALL ON public.merchant_accounts TO service_role;
ALTER TABLE public.merchant_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own merchant accounts" ON public.merchant_accounts;
CREATE POLICY "Users read own merchant accounts" ON public.merchant_accounts
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS merchant_accounts_set_updated_at ON public.merchant_accounts;
CREATE TRIGGER merchant_accounts_set_updated_at BEFORE UPDATE ON public.merchant_accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.save_merchant_account(_provider text, _upi_id text, _payee_name text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid(); r public.merchant_accounts%ROWTYPE;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _upi_id IS NULL OR _upi_id !~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z][a-zA-Z0-9.-]{1,32}$' THEN
    RAISE EXCEPTION 'INVALID_UPI_ID';
  END IF;
  INSERT INTO public.merchant_accounts (user_id, provider, upi_id, payee_name)
  VALUES (_user, _provider::public.upi_provider, btrim(_upi_id), COALESCE(btrim(_payee_name),''))
  ON CONFLICT (user_id, provider) DO UPDATE
    SET upi_id = EXCLUDED.upi_id, payee_name = EXCLUDED.payee_name
  RETURNING * INTO r;
  RETURN jsonb_build_object('provider', r.provider, 'upi_id', r.upi_id, 'payee_name', r.payee_name,
    'email', r.email, 'connected', r.connected, 'connected_at', r.connected_at);
END $$;

CREATE OR REPLACE FUNCTION public.connect_merchant_account(_provider text, _email text, _app_password text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid(); r public.merchant_accounts%ROWTYPE;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _email IS NULL OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'INVALID_EMAIL'; END IF;
  IF _app_password IS NULL OR length(replace(btrim(_app_password),' ','')) < 12 THEN RAISE EXCEPTION 'INVALID_APP_PASSWORD'; END IF;

  SELECT * INTO r FROM public.merchant_accounts WHERE user_id = _user AND provider = _provider::public.upi_provider;
  IF r.id IS NULL OR length(btrim(r.upi_id)) = 0 THEN RAISE EXCEPTION 'UPI_NOT_SAVED'; END IF;

  UPDATE public.merchant_accounts
     SET email = btrim(_email), app_password = replace(btrim(_app_password),' ',''),
         connected = true, connected_at = now()
   WHERE id = r.id
   RETURNING * INTO r;

  RETURN jsonb_build_object('provider', r.provider, 'upi_id', r.upi_id, 'payee_name', r.payee_name,
    'email', r.email, 'connected', r.connected, 'connected_at', r.connected_at);
END $$;

CREATE OR REPLACE FUNCTION public.disconnect_merchant_account(_provider text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid(); r public.merchant_accounts%ROWTYPE;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  UPDATE public.merchant_accounts
     SET email = '', app_password = '', connected = false, connected_at = NULL
   WHERE user_id = _user AND provider = _provider::public.upi_provider
   RETURNING * INTO r;
  IF r.id IS NULL THEN RAISE EXCEPTION 'ACCOUNT_NOT_FOUND'; END IF;
  RETURN jsonb_build_object('provider', r.provider, 'upi_id', r.upi_id, 'payee_name', r.payee_name,
    'email', r.email, 'connected', r.connected, 'connected_at', r.connected_at);
END $$;

CREATE OR REPLACE FUNCTION public.list_merchant_accounts()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'provider', provider, 'upi_id', upi_id, 'payee_name', payee_name,
    'email', email, 'connected', connected, 'connected_at', connected_at
  ) ORDER BY provider), '[]'::jsonb)
  FROM public.merchant_accounts WHERE user_id = auth.uid();
$$;

-- ============ API keys ============
CREATE TABLE IF NOT EXISTS public.api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  label text NOT NULL DEFAULT 'Default key',
  key_prefix text NOT NULL,
  key_hash text NOT NULL,
  webhook_secret text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT (id, user_id, label, key_prefix, webhook_secret, active, last_used_at, created_at)
  ON public.api_keys TO authenticated;
GRANT ALL ON public.api_keys TO service_role;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own api keys" ON public.api_keys;
CREATE POLICY "Users read own api keys" ON public.api_keys
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.issue_api_key(_label text DEFAULT 'Default key')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid(); raw text; secret text; pfx text; row_id uuid;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  raw := 'aupi_live_' || encode(extensions.gen_random_bytes(24), 'hex');
  secret := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
  pfx := left(raw, 18);

  UPDATE public.api_keys SET active = false WHERE user_id = _user AND active;

  INSERT INTO public.api_keys (user_id, label, key_prefix, key_hash, webhook_secret)
  VALUES (_user, COALESCE(NULLIF(btrim(_label), ''), 'Default key'), pfx,
          encode(extensions.digest(raw, 'sha256'), 'hex'), secret)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'api_key', raw, 'key_prefix', pfx, 'webhook_secret', secret);
END $$;

CREATE OR REPLACE FUNCTION public.revoke_api_key(_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid();
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  UPDATE public.api_keys SET active = false WHERE id = _id AND user_id = _user;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ============ payment links ============
DO $$ BEGIN
  CREATE TYPE public.link_status AS ENUM ('active','paid','expired');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.payment_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  order_id text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  customer_name text NOT NULL DEFAULT '',
  amount numeric(12,2) NOT NULL,
  payable_amount numeric(12,2) NOT NULL,
  provider public.upi_provider,
  upi_id text NOT NULL DEFAULT '',
  payee_name text NOT NULL DEFAULT '',
  link_type text NOT NULL DEFAULT 'one_time',
  status public.link_status NOT NULL DEFAULT 'active',
  clicks integer NOT NULL DEFAULT 0,
  paid_count integer NOT NULL DEFAULT 0,
  paid_at timestamptz,
  payer_name text,
  paid_email_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_links_user_created_idx ON public.payment_links (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS payment_links_active_amount_idx ON public.payment_links (payable_amount) WHERE status = 'active';

GRANT SELECT ON public.payment_links TO authenticated;
GRANT ALL ON public.payment_links TO service_role;
ALTER TABLE public.payment_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own payment links" ON public.payment_links;
CREATE POLICY "Users read own payment links" ON public.payment_links
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT '', _link_type text DEFAULT 'one_time')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2);
  candidate numeric(12,2);
  taken numeric[];
  oid text; sl text; row_id uuid; i int;
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

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN 1..299 LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100);
      EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active');
END $$;

CREATE OR REPLACE FUNCTION public.expire_payment_link(_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _user uuid := auth.uid();
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  UPDATE public.payment_links SET status = 'expired'
   WHERE id = _id AND user_id = _user AND status = 'active';
  RETURN jsonb_build_object('ok', true);
END $$;

-- public (anon) read for the pay page + click counter
CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.payment_links%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.payment_links WHERE slug = _slug;
  IF r.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('order_id', r.order_id, 'amount', r.amount, 'payable_amount', r.payable_amount,
    'status', r.status, 'upi_id', r.upi_id, 'payee_name', r.payee_name, 'customer_name', r.customer_name,
    'created_at', r.created_at, 'paid_at', r.paid_at);
END $$;

CREATE OR REPLACE FUNCTION public.register_payment_link_click(_slug text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  UPDATE public.payment_links SET clicks = clicks + 1 WHERE slug = _slug AND status = 'active';
$$;

-- detection entry point: called by the email reader with a matched amount
CREATE OR REPLACE FUNCTION public.record_detected_payment(_user uuid, _amount numeric, _payer text DEFAULT NULL, _email_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.payment_links%ROWTYPE;
BEGIN
  IF _email_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.payment_links WHERE paid_email_id = _email_id) THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'duplicate_email');
  END IF;

  SELECT * INTO r FROM public.payment_links
   WHERE user_id = _user AND status = 'active' AND payable_amount = round(_amount, 2)
   ORDER BY created_at ASC LIMIT 1;
  IF r.id IS NULL THEN RETURN jsonb_build_object('matched', false, 'reason', 'no_match'); END IF;

  UPDATE public.payment_links
     SET status = CASE WHEN link_type = 'reusable' THEN status ELSE 'paid'::public.link_status END,
         paid_at = now(), paid_count = paid_count + 1, payer_name = _payer, paid_email_id = _email_id
   WHERE id = r.id;

  RETURN jsonb_build_object('matched', true, 'order_id', r.order_id, 'amount', r.payable_amount);
END $$;

REVOKE ALL ON FUNCTION public.record_detected_payment(uuid, numeric, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_detected_payment(uuid, numeric, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_public_payment_link(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_payment_link_click(text) TO anon, authenticated;
-- ---------- 0006_gmail_payment_detection.sql ----------
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
-- ---------- 0007_api_key_single_and_public_api.sql ----------
-- Keep only one API key per user: regenerating removes the old row entirely.
CREATE OR REPLACE FUNCTION public.issue_api_key(_label text DEFAULT 'Default key')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _user uuid := auth.uid(); raw text; secret text; pfx text; row_id uuid;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  raw := 'aupi_live_' || encode(extensions.gen_random_bytes(24), 'hex');
  secret := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
  pfx := left(raw, 18);

  DELETE FROM public.api_keys WHERE user_id = _user;

  INSERT INTO public.api_keys (user_id, label, key_prefix, key_hash, webhook_secret)
  VALUES (_user, COALESCE(NULLIF(btrim(_label), ''), 'Default key'), pfx,
          encode(extensions.digest(raw, 'sha256'), 'hex'), secret)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'api_key', raw, 'key_prefix', pfx, 'webhook_secret', secret);
END $$;

-- Clear historic revoked keys.
DELETE FROM public.api_keys WHERE active = false;

-- Server-side payment link creation for the public REST API (service role only).
CREATE OR REPLACE FUNCTION public.api_create_payment_link(_user uuid, _amount numeric, _customer_name text DEFAULT '', _link_type text DEFAULT 'one_time')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2); candidate numeric(12,2); taken numeric[];
  oid text; sl text; row_id uuid; i int;
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

  base := round(_amount, 2);
  SELECT COALESCE(array_agg(payable_amount), '{}') INTO taken
    FROM public.payment_links
   WHERE user_id = _user AND status = 'active'
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN 1..299 LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active');
END $$;

REVOKE ALL ON FUNCTION public.api_create_payment_link(uuid, numeric, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_create_payment_link(uuid, numeric, text, text) TO service_role;
-- ---------- 0008_fixed_5min_expiry_and_exact_amounts.sql ----------
ALTER TABLE public.payment_links ALTER COLUMN expires_at SET DEFAULT (now() + interval '5 minutes');

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2);
  candidate numeric(12,2);
  taken numeric[];
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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  IF NOT (base = ANY (taken)) THEN
    candidate := base;
  ELSE
    FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
      IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
        candidate := base + (i::numeric / 100); EXIT;
      END IF;
    END LOOP;
  END IF;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  IF NOT (base = ANY (taken)) THEN
    candidate := base;
  ELSE
    FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
      IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
        candidate := base + (i::numeric / 100); EXIT;
      END IF;
    END LOOP;
  END IF;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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

CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.payment_links WHERE slug = _slug;
  IF r.id IS NULL THEN RETURN NULL; END IF;

  IF r.status = 'active' AND r.expires_at < now() THEN
    UPDATE public.payment_links SET status = 'expired'
     WHERE id = r.id AND status = 'active'
     RETURNING * INTO r;
  END IF;

  RETURN jsonb_build_object('order_id', r.order_id, 'amount', r.amount, 'payable_amount', r.payable_amount,
    'status', r.status, 'upi_id', r.upi_id, 'payee_name', r.payee_name, 'customer_name', r.customer_name,
    'created_at', r.created_at, 'paid_at', r.paid_at, 'expires_at', r.expires_at, 'server_now', now());
END $function$;
-- ---------- 0009_unique_payable_amount_per_link.sql ----------
-- Every active payment link of a merchant must have a globally unique payable
-- amount, so an alert email can only ever settle exactly one order.

CREATE UNIQUE INDEX IF NOT EXISTS payment_links_active_amount_uniq
  ON public.payment_links (user_id, payable_amount)
  WHERE status = 'active';

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  base numeric(12,2);
  candidate numeric(12,2);
  taken numeric[];
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
     AND payable_amount BETWEEN base AND base + 2.99;

  -- Always append a unique paise marker: the exact base amount is never used,
  -- so a random incoming payment of the plain amount can never be captured.
  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := encode(extensions.gen_random_bytes(6), 'base64');
  sl  := replace(replace(replace(sl, '+', ''), '/', ''), '=', '');
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

-- Detection helper used by the mail poller: amount must match to the paisa and
-- the email must be newer than the link, else nothing is settled.
CREATE OR REPLACE FUNCTION public.record_detected_payment(_user uuid, _amount numeric, _payer text DEFAULT NULL::text, _email_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE; n int;
BEGIN
  IF _email_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.payment_links WHERE paid_email_id = _email_id) THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'duplicate_email');
  END IF;

  SELECT count(*) INTO n FROM public.payment_links
   WHERE user_id = _user AND status = 'active' AND payable_amount = round(_amount, 2);
  IF n <> 1 THEN
    RETURN jsonb_build_object('matched', false, 'reason', CASE WHEN n = 0 THEN 'no_match' ELSE 'ambiguous' END);
  END IF;

  SELECT * INTO r FROM public.payment_links
   WHERE user_id = _user AND status = 'active' AND payable_amount = round(_amount, 2)
   LIMIT 1;

  UPDATE public.payment_links
     SET status = CASE WHEN link_type = 'reusable' THEN status ELSE 'paid'::public.link_status END,
         paid_at = now(), detected_at = now(), paid_count = paid_count + 1,
         payer_name = _payer, paid_email_id = _email_id
   WHERE id = r.id AND status = 'active' AND paid_email_id IS NULL;

  IF NOT FOUND THEN RETURN jsonb_build_object('matched', false, 'reason', 'race'); END IF;
  RETURN jsonb_build_object('matched', true, 'order_id', r.order_id, 'amount', r.payable_amount);
END $function$;
-- ---------- 0010_payment_link_webhooks.sql ----------
ALTER TABLE public.payment_links
  ADD COLUMN IF NOT EXISTS webhook_url text,
  ADD COLUMN IF NOT EXISTS webhook_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS webhook_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS webhook_last_error text;
-- ---------- 0011_lowercase_slugs_and_hardening.sql ----------
-- 1) Slugs must be unique and lowercase-only.
CREATE UNIQUE INDEX IF NOT EXISTS payment_links_slug_key ON public.payment_links (slug);
CREATE INDEX IF NOT EXISTS payment_links_user_status_idx ON public.payment_links (user_id, status);
CREATE INDEX IF NOT EXISTS merchant_accounts_user_connected_idx ON public.merchant_accounts (user_id, connected);

CREATE OR REPLACE FUNCTION public.new_payment_slug()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE s text; i int;
BEGIN
  FOR i IN 1..12 LOOP
    s := lower(encode(extensions.gen_random_bytes(6), 'hex'));
    IF NOT EXISTS (SELECT 1 FROM public.payment_links WHERE slug = s) THEN
      RETURN s;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'SLUG_GENERATION_FAILED';
END $function$;

-- 2) Rebuild link creation with lowercase slug + safer amount slotting.
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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ord' || to_char(now(), 'yyyymmdd') || lower(encode(extensions.gen_random_bytes(3), 'hex'));
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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ord' || to_char(now(), 'yyyymmdd') || lower(encode(extensions.gen_random_bytes(3), 'hex'));
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

-- 3) Public lookups are case-insensitive so old mixed-case links keep working.
CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.payment_links WHERE slug = _slug LIMIT 1;
  IF r.id IS NULL THEN
    SELECT * INTO r FROM public.payment_links WHERE lower(slug) = lower(_slug) LIMIT 1;
  END IF;
  IF r.id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;

  IF r.status = 'active' AND r.expires_at <= now() THEN
    UPDATE public.payment_links SET status = 'expired' WHERE id = r.id AND status = 'active';
    r.status := 'expired';
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'order_id', r.order_id,
    'slug', r.slug,
    'customer_name', r.customer_name,
    'amount', r.amount,
    'payable_amount', r.payable_amount,
    'upi_id', r.upi_id,
    'payee_name', r.payee_name,
    'status', r.status,
    'expires_at', r.expires_at,
    'server_now', now()
  );
END $function$;

CREATE OR REPLACE FUNCTION public.register_payment_link_click(_slug text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE public.payment_links SET clicks = clicks + 1 WHERE lower(slug) = lower(_slug);
$function$;
-- ---------- 0012_poll_throttle_claim.sql ----------
ALTER TABLE public.merchant_accounts ADD COLUMN IF NOT EXISTS last_polled_at timestamptz;

-- Atomically claim a mailbox poll slot for a merchant: at most one IMAP scan
-- every 6 seconds no matter how many payers have the pay page open.
CREATE OR REPLACE FUNCTION public.try_claim_mail_poll(_user uuid, _min_gap_seconds int DEFAULT 6)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE claimed boolean := false;
BEGIN
  UPDATE public.merchant_accounts
     SET last_polled_at = now()
   WHERE user_id = _user
     AND connected
     AND (last_polled_at IS NULL OR last_polled_at < now() - make_interval(secs => _min_gap_seconds))
  RETURNING true INTO claimed;
  RETURN COALESCE(claimed, false);
END $function$;
-- ---------- 0013_function_grant_hardening.sql ----------
-- Internal helpers must never be callable from the browser.
REVOKE ALL ON FUNCTION public.new_payment_slug() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.new_payment_slug() TO service_role;

REVOKE ALL ON FUNCTION public.try_claim_mail_poll(uuid, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.try_claim_mail_poll(uuid, int) TO service_role;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Merchant-only actions: signed-in users only, never anonymous callers.
REVOKE ALL ON FUNCTION public.create_payment_link(numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_payment_link(numeric, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.connect_merchant_account(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.connect_merchant_account(text, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.disconnect_merchant_account(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.disconnect_merchant_account(text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.save_merchant_account(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_merchant_account(text, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.list_merchant_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_merchant_accounts() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.issue_api_key(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_api_key(text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.revoke_api_key(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_api_key(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.expire_payment_link(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_payment_link(uuid) TO authenticated, service_role;

-- Public pay page needs exactly these two.
GRANT EXECUTE ON FUNCTION public.get_public_payment_link(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_payment_link_click(text) TO anon, authenticated, service_role;

-- Trigger helper: pin search_path.
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $function$;

-- Legacy OAuth table is no longer used; lock it down instead of dropping it.
REVOKE ALL ON TABLE public.gmail_connections FROM PUBLIC, anon, authenticated;
-- ---------- 0014_admin_panel_controls.sql ----------
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
         = 'dexst12@gmail.com'
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
-- ---------- 0015_payment_link_quota_and_uppercase_order_id.sql ----------
-- Every payment link now consumes one QR from the user's plan quota.
CREATE OR REPLACE FUNCTION public.consume_qr_quota(_user uuid, _payload text, _upi_id text DEFAULT '', _amount numeric DEFAULT NULL, _label text DEFAULT 'Payment link')
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  s public.subscriptions%ROWTYPE;
  lim INT := 3; used INT := 0; since TIMESTAMPTZ;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_user::text, 0));
  SELECT * INTO s FROM public.subscriptions WHERE user_id = _user;

  IF s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now() THEN
    lim := COALESCE(s.qr_limit, 3000); since := COALESCE(s.started_at, '-infinity'::timestamptz);
  ELSE
    lim := COALESCE(s.qr_limit, 3); since := COALESCE(s.expires_at, '-infinity'::timestamptz);
  END IF;

  SELECT count(*) INTO used FROM public.qr_codes WHERE user_id = _user AND created_at >= since;
  IF used >= lim THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;

  INSERT INTO public.qr_codes (user_id, label, upi_id, amount, payload)
  VALUES (_user, COALESCE(_label, 'Payment link'), COALESCE(_upi_id, ''), _amount, _payload);
END $function$;

REVOKE ALL ON FUNCTION public.consume_qr_quota(uuid, text, text, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_qr_quota(uuid, text, text, numeric, text) TO service_role;

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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := public.new_payment_slug();
  exp := now() + interval '5 minutes';

  -- Plan enforcement: raises QUOTA_EXCEEDED when the plan limit is reached.
  PERFORM public.consume_qr_quota(_user, 'upi://pay?pa=' || acct.upi_id || '&am=' || candidate::text, acct.upi_id, base, 'Payment link ' || oid);

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
     AND payable_amount BETWEEN base AND base + 2.99;

  candidate := NULL;
  FOR i IN SELECT g FROM generate_series(1, 299) g ORDER BY random() LOOP
    IF NOT (base + (i::numeric / 100)) = ANY (taken) THEN
      candidate := base + (i::numeric / 100); EXIT;
    END IF;
  END LOOP;
  IF candidate IS NULL THEN RAISE EXCEPTION 'ALL_PAYMENT_SLOTS_BUSY'; END IF;

  oid := 'ORD' || to_char(now(), 'YYYYMMDD') || upper(encode(extensions.gen_random_bytes(3), 'hex'));
  sl  := public.new_payment_slug();
  exp := now() + interval '5 minutes';

  PERFORM public.consume_qr_quota(_user, 'upi://pay?pa=' || acct.upi_id || '&am=' || candidate::text, acct.upi_id, base, 'Payment link ' || oid);

  INSERT INTO public.payment_links
    (user_id, order_id, slug, customer_name, amount, payable_amount, provider, upi_id, payee_name, link_type, expires_at)
  VALUES (_user, oid, sl, COALESCE(btrim(_customer_name), ''), base, candidate,
          acct.provider, acct.upi_id, acct.payee_name,
          CASE WHEN _link_type = 'reusable' THEN 'reusable' ELSE 'one_time' END, exp)
  RETURNING id INTO row_id;

  RETURN jsonb_build_object('id', row_id, 'order_id', oid, 'slug', sl,
    'amount', base, 'payable_amount', candidate, 'status', 'active', 'expires_at', exp);
END $function$;
-- ---------- 0016_admin_payment_logs.sql ----------
create or replace function public.admin_payment_logs(_search text default '', _limit int default 200)
returns json
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json)
  from (
    select
      pl.id,
      pl.order_id,
      pl.slug,
      pl.amount,
      pl.payable_amount,
      pl.status::text as status,
      pl.customer_name,
      pl.payer_name,
      pl.clicks,
      pl.created_at,
      pl.paid_at,
      pl.expires_at,
      pl.user_id,
      coalesce(p.full_name, '') as merchant_name,
      coalesce(u.email, '') as merchant_email
    from public.payment_links pl
    left join public.profiles p on p.id = pl.user_id
    left join auth.users u on u.id = pl.user_id
    where public.is_platform_admin()
      and (
        coalesce(_search, '') = ''
        or pl.order_id ilike '%' || _search || '%'
        or coalesce(u.email, '') ilike '%' || _search || '%'
        or coalesce(p.full_name, '') ilike '%' || _search || '%'
        or coalesce(pl.customer_name, '') ilike '%' || _search || '%'
      )
    order by pl.created_at desc
    limit least(greatest(coalesce(_limit, 200), 1), 1000)
  ) t;
$$;

revoke all on function public.admin_payment_logs(text, int) from public, anon;
grant execute on function public.admin_payment_logs(text, int) to authenticated, service_role;
-- ---------- 0017_paise_limit_and_fast_admin.sql ----------
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
-- ---------- 0018_free_plan_fixed_three_qr.sql ----------
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

-- ---------- 0019_plan_upgrade_orders.sql ----------
CREATE TABLE public.plan_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  order_id text NOT NULL UNIQUE,
  slug text NOT NULL,
  amount numeric NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.plan_orders TO authenticated;
GRANT ALL ON public.plan_orders TO service_role;

ALTER TABLE public.plan_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own plan orders"
ON public.plan_orders FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX plan_orders_user_idx ON public.plan_orders (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.complete_plan_order(_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _row public.plan_orders;
BEGIN
  SELECT * INTO _row FROM public.plan_orders WHERE order_id = _order_id FOR UPDATE;
  IF _row.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF _row.status = 'paid' THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;

  UPDATE public.plan_orders
     SET status = 'paid', paid_at = now()
   WHERE id = _row.id;

  PERFORM public.activate_pro_subscription(_row.user_id, 'gateway:' || _row.order_id, _row.amount);

  RETURN jsonb_build_object('ok', true, 'already', false);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_plan_order(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_plan_order(text) TO service_role;
-- ---------- 0020_platform_plan_price_setting.sql ----------
CREATE TABLE IF NOT EXISTS public.platform_settings (
  key text PRIMARY KEY,
  value numeric NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.platform_settings TO anon;
GRANT SELECT ON public.platform_settings TO authenticated;
GRANT ALL ON public.platform_settings TO service_role;

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Platform settings are public" ON public.platform_settings;
CREATE POLICY "Platform settings are public"
  ON public.platform_settings FOR SELECT
  TO anon, authenticated
  USING (true);

INSERT INTO public.platform_settings (key, value)
VALUES ('pro_price', 299)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_pro_price()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM public.platform_settings WHERE key = 'pro_price'), 299);
$$;

GRANT EXECUTE ON FUNCTION public.get_pro_price() TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_set_pro_price(_price numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF _price IS NULL OR _price < 1 OR _price > 100000 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  INSERT INTO public.platform_settings (key, value, updated_at)
  VALUES ('pro_price', round(_price, 2), now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

  RETURN round(_price, 2);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_pro_price(numeric) TO authenticated, service_role;
-- ---------- 0021_fix_qr_quota_enforcement.sql ----------
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
-- ---------- 0022_free_plan_toggle.sql ----------
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
-- ---------- 0023_plan_days_countdown_fix.sql ----------
-- 1) quota_window_start uses now(), so it must be STABLE, not IMMUTABLE.
--    As IMMUTABLE the planner could fold it and keep a stale window.
CREATE OR REPLACE FUNCTION public.quota_window_start(s public.subscriptions)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $function$
  SELECT CASE
    WHEN s.user_id IS NOT NULL AND s.plan = 'pro' AND s.expires_at IS NOT NULL AND s.expires_at > now()
      THEN COALESCE(s.started_at, '-infinity'::timestamptz)
    WHEN s.expires_at IS NOT NULL AND s.expires_at <= now()
      THEN s.expires_at
    ELSE '-infinity'::timestamptz
  END
$function$;

-- 2) get_qr_quota now also returns a server-computed live countdown.
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
    dleft := CEIL(secs / 86400.0)::INT;
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
END; $function$;
-- ---------- 0024_plan_days_left_floor.sql ----------
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
-- ---------- 0025_plan_calendar_day_expiry_ist.sql ----------
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
-- ---------- 0026_signup_otp_email_source.sql ----------
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
-- ---------- 0027_legacy_email_verification.sql ----------
CREATE TABLE IF NOT EXISTS public.email_verifications (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  verified_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.email_verifications TO authenticated;
GRANT ALL ON public.email_verifications TO service_role;

ALTER TABLE public.email_verifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own verification" ON public.email_verifications;
CREATE POLICY "Users read own verification"
ON public.email_verifications FOR SELECT TO authenticated
USING (auth.uid() = user_id);
-- ---------- 0029_mailbox_health_status.sql ----------
ALTER TABLE public.merchant_accounts
  ADD COLUMN IF NOT EXISTS mail_error text,
  ADD COLUMN IF NOT EXISTS mail_error_at timestamptz,
  ADD COLUMN IF NOT EXISTS mail_ok_at timestamptz;

CREATE OR REPLACE FUNCTION public.list_merchant_accounts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'provider', provider, 'upi_id', upi_id, 'payee_name', payee_name,
    'email', email, 'connected', connected, 'connected_at', connected_at,
    'mail_error', mail_error, 'mail_error_at', mail_error_at, 'mail_ok_at', mail_ok_at
  ) ORDER BY provider), '[]'::jsonb)
  FROM public.merchant_accounts WHERE user_id = auth.uid();
$function$;
-- ---------- 0030_merchant_config_urls.sql ----------
CREATE TABLE IF NOT EXISTS public.merchant_config (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  success_url text,
  failure_url text,
  webhook_url text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.merchant_config TO authenticated;
GRANT ALL ON public.merchant_config TO service_role;

ALTER TABLE public.merchant_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own config" ON public.merchant_config;
CREATE POLICY "Users read own config" ON public.merchant_config
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Save / read helpers (writes only through this definer function).
CREATE OR REPLACE FUNCTION public.save_merchant_config(_success_url text, _failure_url text, _webhook_url text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u uuid := auth.uid();
        s text := nullif(btrim(coalesce(_success_url, '')), '');
        f text := nullif(btrim(coalesce(_failure_url, '')), '');
        w text := nullif(btrim(coalesce(_webhook_url, '')), '');
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF s IS NOT NULL AND s !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_SUCCESS_URL'; END IF;
  IF f IS NOT NULL AND f !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_FAILURE_URL'; END IF;
  IF w IS NOT NULL AND w !~* '^https://' THEN RAISE EXCEPTION 'INVALID_WEBHOOK_URL'; END IF;

  INSERT INTO public.merchant_config (user_id, success_url, failure_url, webhook_url, updated_at)
  VALUES (u, left(s, 500), left(f, 500), left(w, 500), now())
  ON CONFLICT (user_id) DO UPDATE
    SET success_url = EXCLUDED.success_url,
        failure_url = EXCLUDED.failure_url,
        webhook_url = EXCLUDED.webhook_url,
        updated_at = now();

  RETURN jsonb_build_object('success_url', s, 'failure_url', f, 'webhook_url', w);
END $function$;

REVOKE ALL ON FUNCTION public.save_merchant_config(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_merchant_config(text, text, text) TO authenticated, service_role;

-- Public pay page needs the owner's redirect URLs (never the webhook URL).
CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE; c public.merchant_config%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.payment_links WHERE slug = _slug LIMIT 1;
  IF r.id IS NULL THEN
    SELECT * INTO r FROM public.payment_links WHERE lower(slug) = lower(_slug) LIMIT 1;
  END IF;
  IF r.id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;

  IF r.status = 'active' AND r.expires_at <= now() THEN
    UPDATE public.payment_links SET status = 'expired' WHERE id = r.id AND status = 'active';
    r.status := 'expired';
  END IF;

  SELECT * INTO c FROM public.merchant_config WHERE user_id = r.user_id;

  RETURN jsonb_build_object(
    'found', true,
    'order_id', r.order_id,
    'slug', r.slug,
    'customer_name', r.customer_name,
    'amount', r.amount,
    'payable_amount', r.payable_amount,
    'upi_id', r.upi_id,
    'payee_name', r.payee_name,
    'status', r.status,
    'expires_at', r.expires_at,
    'success_url', c.success_url,
    'failure_url', c.failure_url,
    'server_now', now()
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.get_public_payment_link(text) TO anon, authenticated, service_role;
-- ---------- 0031_issue_config_diagnostics_and_unique_mobile.sql ----------
-- 1. Mobile number helper + uniqueness for new registrations ---------------
CREATE OR REPLACE FUNCTION public.mobile_digits(_value TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT RIGHT(regexp_replace(COALESCE(_value, ''), '\D', '', 'g'), 10)
$$;

CREATE INDEX IF NOT EXISTS profiles_mobile_digits_idx
  ON public.profiles (public.mobile_digits(mobile));

CREATE OR REPLACE FUNCTION public.profiles_unique_mobile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d TEXT;
BEGIN
  d := public.mobile_digits(NEW.mobile);
  IF LENGTH(d) = 10 THEN
    IF EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id <> NEW.id AND public.mobile_digits(p.mobile) = d
    ) THEN
      RAISE EXCEPTION 'This mobile number is already registered with another account.'
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_unique_mobile_trg ON public.profiles;
CREATE TRIGGER profiles_unique_mobile_trg
  BEFORE INSERT OR UPDATE OF mobile ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_unique_mobile();

-- 2. Admin diagnostics by mobile number -------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_diagnostics(_mobile TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  d TEXT := public.mobile_digits(_mobile);
  uid UUID;
  result JSONB;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  IF LENGTH(d) <> 10 THEN
    RETURN jsonb_build_object('found', false, 'reason', 'bad_number');
  END IF;

  SELECT p.id INTO uid FROM public.profiles p
  WHERE public.mobile_digits(p.mobile) = d
  ORDER BY p.created_at DESC LIMIT 1;

  IF uid IS NULL THEN
    RETURN jsonb_build_object('found', false, 'reason', 'no_user');
  END IF;

  SELECT jsonb_build_object(
    'found', true,
    'now', now(),
    'user', (
      SELECT jsonb_build_object(
        'user_id', u.id,
        'email', u.email,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'full_name', COALESCE(p.full_name, ''),
        'mobile', COALESCE(p.mobile, ''),
        'email_verified', EXISTS (SELECT 1 FROM public.email_verifications v WHERE v.user_id = u.id)
      )
      FROM auth.users u LEFT JOIN public.profiles p ON p.id = u.id WHERE u.id = uid
    ),
    'plan', (
      SELECT jsonb_build_object(
        'plan', s.plan, 'started_at', s.started_at, 'expires_at', s.expires_at,
        'qr_limit', s.qr_limit, 'amount_inr', s.amount_inr
      ) FROM public.subscriptions s WHERE s.user_id = uid
      ORDER BY s.created_at DESC LIMIT 1
    ),
    'quota', jsonb_build_object(
      'qr_used', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid),
      'free_plan_enabled', public.is_free_plan_enabled()
    ),
    'mailbox', (
      SELECT jsonb_build_object(
        'connected', m.connected, 'email', m.email, 'upi_id', m.upi_id, 'payee_name', m.payee_name,
        'has_password', COALESCE(m.app_password, '') <> '',
        'connected_at', m.connected_at, 'last_polled_at', m.last_polled_at,
        'mail_error', m.mail_error, 'mail_error_at', m.mail_error_at, 'mail_ok_at', m.mail_ok_at
      ) FROM public.merchant_accounts m WHERE m.user_id = uid
      ORDER BY m.created_at DESC LIMIT 1
    ),
    'config', (
      SELECT jsonb_build_object('success_url', c.success_url, 'failure_url', c.failure_url, 'webhook_url', c.webhook_url)
      FROM public.merchant_config c WHERE c.user_id = uid
    ),
    'api_key', (
      SELECT jsonb_build_object('active', k.active, 'last_used_at', k.last_used_at, 'created_at', k.created_at)
      FROM public.api_keys k WHERE k.user_id = uid ORDER BY k.created_at DESC LIMIT 1
    ),
    'links', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid),
      'paid', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'paid'),
      'expired', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'expired'),
      'active', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'active'),
      'no_click_expired', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'expired' AND COALESCE(l.clicks,0) = 0),
      'last_paid_at', (SELECT MAX(l.paid_at) FROM public.payment_links l WHERE l.user_id = uid),
      'last_created_at', (SELECT MAX(l.created_at) FROM public.payment_links l WHERE l.user_id = uid),
      'webhook_failed', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND COALESCE(l.webhook_last_error,'') <> '')
    ),
    'recent', COALESCE((
      SELECT jsonb_agg(x ORDER BY x->>'created_at' DESC) FROM (
        SELECT jsonb_build_object(
          'order_id', l.order_id, 'amount', l.amount, 'payable_amount', l.payable_amount,
          'status', l.status, 'clicks', COALESCE(l.clicks,0), 'created_at', l.created_at,
          'paid_at', l.paid_at, 'expires_at', l.expires_at, 'payer_name', l.payer_name,
          'webhook_last_error', l.webhook_last_error
        ) AS x
        FROM public.payment_links l WHERE l.user_id = uid
        ORDER BY l.created_at DESC LIMIT 10
      ) t
    ), '[]'::jsonb),
    'mail_seen', (SELECT COUNT(*) FROM public.processed_emails e WHERE e.user_id = uid)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_diagnostics(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_diagnostics(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mobile_digits(TEXT) TO authenticated, anon, service_role;
-- ---------- 0032_multi_upi_routing.sql ----------
CREATE TABLE public.merchant_upi_ids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider public.upi_provider NOT NULL DEFAULT 'phonepe',
  upi_id text NOT NULL,
  payee_name text NOT NULL DEFAULT '',
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX merchant_upi_ids_user_upi ON public.merchant_upi_ids (user_id, lower(upi_id));
CREATE UNIQUE INDEX merchant_upi_ids_one_primary ON public.merchant_upi_ids (user_id) WHERE is_primary;
GRANT SELECT ON public.merchant_upi_ids TO authenticated;
GRANT ALL ON public.merchant_upi_ids TO service_role;
ALTER TABLE public.merchant_upi_ids ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own upi ids" ON public.merchant_upi_ids FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE public.merchant_upi_routing (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.merchant_upi_routing TO authenticated;
GRANT ALL ON public.merchant_upi_routing TO service_role;
ALTER TABLE public.merchant_upi_routing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own upi routing" ON public.merchant_upi_routing FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.list_upi_ids() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'routing', COALESCE((SELECT enabled FROM merchant_upi_routing WHERE user_id = auth.uid()), false),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'provider', provider, 'upi_id', upi_id, 'payee_name', payee_name, 'is_primary', is_primary) ORDER BY created_at)
                       FROM merchant_upi_ids WHERE user_id = auth.uid()), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.add_upi_id(_upi_id text, _payee_name text DEFAULT '', _provider text DEFAULT 'phonepe') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); v text := lower(btrim(COALESCE(_upi_id, ''))); n int; rid uuid;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v !~ '^[a-z0-9._-]{2,256}@[a-z0-9.-]{2,64}$' THEN RAISE EXCEPTION 'INVALID_UPI_ID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_u::text, 11));
  SELECT count(*) INTO n FROM merchant_upi_ids WHERE user_id = _u;
  IF n >= 10 THEN RAISE EXCEPTION 'UPI_LIMIT_REACHED'; END IF;
  IF EXISTS (SELECT 1 FROM merchant_upi_ids WHERE user_id = _u AND lower(upi_id) = v) THEN RAISE EXCEPTION 'UPI_ALREADY_ADDED'; END IF;
  INSERT INTO merchant_upi_ids (user_id, provider, upi_id, payee_name, is_primary)
  VALUES (_u, CASE WHEN _provider = 'paytm' THEN 'paytm'::upi_provider ELSE 'phonepe'::upi_provider END,
          v, left(btrim(COALESCE(_payee_name, '')), 100), n = 0)
  RETURNING id INTO rid;
  RETURN jsonb_build_object('id', rid);
END $$;

CREATE OR REPLACE FUNCTION public.remove_upi_id(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); was boolean;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  DELETE FROM merchant_upi_ids WHERE id = _id AND user_id = _u RETURNING is_primary INTO was;
  IF was THEN
    UPDATE merchant_upi_ids SET is_primary = true
     WHERE id = (SELECT id FROM merchant_upi_ids WHERE user_id = _u ORDER BY created_at LIMIT 1);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_primary_upi(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid();
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM merchant_upi_ids WHERE id = _id AND user_id = _u) THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  UPDATE merchant_upi_ids SET is_primary = false WHERE user_id = _u AND is_primary;
  UPDATE merchant_upi_ids SET is_primary = true WHERE id = _id;
END $$;

CREATE OR REPLACE FUNCTION public.set_upi_routing(_enabled boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid();
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  INSERT INTO merchant_upi_routing (user_id, enabled, updated_at) VALUES (_u, COALESCE(_enabled, false), now())
  ON CONFLICT (user_id) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
  RETURN COALESCE(_enabled, false);
END $$;

-- Picks the UPI for a new link: random when routing is on, otherwise primary.
CREATE OR REPLACE FUNCTION public.pick_merchant_upi(_user uuid) RETURNS public.merchant_upi_ids
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r merchant_upi_ids%ROWTYPE;
BEGIN
  IF COALESCE((SELECT enabled FROM merchant_upi_routing WHERE user_id = _user), false) THEN
    SELECT * INTO r FROM merchant_upi_ids WHERE user_id = _user ORDER BY random() LIMIT 1;
  ELSE
    SELECT * INTO r FROM merchant_upi_ids WHERE user_id = _user ORDER BY is_primary DESC, created_at LIMIT 1;
  END IF;
  RETURN r;
END $$;

REVOKE EXECUTE ON FUNCTION public.pick_merchant_upi(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pick_merchant_upi(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.list_upi_ids(), public.add_upi_id(text,text,text), public.remove_upi_id(uuid), public.set_primary_upi(uuid), public.set_upi_routing(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_upi_ids(), public.add_upi_id(text,text,text), public.remove_upi_id(uuid), public.set_primary_upi(uuid), public.set_upi_routing(boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_payment_link(_amount numeric, _customer_name text DEFAULT ''::text, _link_type text DEFAULT 'one_time'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _user uuid := auth.uid();
  acct public.merchant_accounts%ROWTYPE;
  pick public.merchant_upi_ids%ROWTYPE;
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
  pick := public.pick_merchant_upi(_user);
  IF pick.id IS NOT NULL THEN
    acct.id := COALESCE(acct.id, pick.id);
    acct.provider := pick.provider; acct.upi_id := pick.upi_id;
    acct.payee_name := CASE WHEN pick.payee_name <> '' THEN pick.payee_name ELSE COALESCE(acct.payee_name, '') END;
  END IF;
  IF acct.id IS NULL OR length(btrim(COALESCE(acct.upi_id, ''))) = 0 THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

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
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  acct public.merchant_accounts%ROWTYPE;
  pick public.merchant_upi_ids%ROWTYPE;
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
  pick := public.pick_merchant_upi(_user);
  IF pick.id IS NOT NULL THEN
    acct.id := COALESCE(acct.id, pick.id);
    acct.provider := pick.provider; acct.upi_id := pick.upi_id;
    acct.payee_name := CASE WHEN pick.payee_name <> '' THEN pick.payee_name ELSE COALESCE(acct.payee_name, '') END;
  END IF;
  IF acct.id IS NULL OR length(btrim(COALESCE(acct.upi_id, ''))) = 0 THEN RAISE EXCEPTION 'UPI_NOT_CONFIGURED'; END IF;

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
-- ---------- 0033_fix_add_upi_id_regex.sql ----------
CREATE OR REPLACE FUNCTION public.add_upi_id(_upi_id text, _payee_name text DEFAULT '', _provider text DEFAULT 'phonepe') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); v text := lower(btrim(COALESCE(_upi_id, ''))); n int; rid uuid;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v !~ '^[a-z0-9._-]{2,255}@[a-z0-9.-]{2,64}$' THEN RAISE EXCEPTION 'INVALID_UPI_ID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_u::text, 11));
  SELECT count(*) INTO n FROM merchant_upi_ids WHERE user_id = _u;
  IF n >= 10 THEN RAISE EXCEPTION 'UPI_LIMIT_REACHED'; END IF;
  IF EXISTS (SELECT 1 FROM merchant_upi_ids WHERE user_id = _u AND lower(upi_id) = v) THEN RAISE EXCEPTION 'UPI_ALREADY_ADDED'; END IF;
  INSERT INTO merchant_upi_ids (user_id, provider, upi_id, payee_name, is_primary)
  VALUES (_u, CASE WHEN _provider = 'paytm' THEN 'paytm'::upi_provider ELSE 'phonepe'::upi_provider END,
          v, left(btrim(COALESCE(_payee_name, '')), 100), n = 0)
  RETURNING id INTO rid;
  RETURN jsonb_build_object('id', rid);
END $$;
