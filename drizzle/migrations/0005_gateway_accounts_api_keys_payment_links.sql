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