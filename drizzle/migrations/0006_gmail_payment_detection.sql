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