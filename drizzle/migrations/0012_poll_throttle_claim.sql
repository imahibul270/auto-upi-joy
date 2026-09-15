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