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
$function$;ALTER TABLE public.merchant_accounts ADD COLUMN IF NOT EXISTS last_polled_at timestamptz;

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
END $function$;-- Internal helpers must never be callable from the browser.
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