ALTER TABLE public.payment_links
  ADD COLUMN IF NOT EXISTS webhook_url text,
  ADD COLUMN IF NOT EXISTS webhook_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS webhook_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS webhook_last_error text;