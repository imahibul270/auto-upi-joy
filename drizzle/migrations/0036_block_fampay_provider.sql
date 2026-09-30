CREATE OR REPLACE FUNCTION public.reject_fampay_provider()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.provider::text = 'fampay' THEN
    RAISE EXCEPTION 'FAMPAY_NOT_SUPPORTED';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS merchant_accounts_no_fampay ON public.merchant_accounts;
CREATE TRIGGER merchant_accounts_no_fampay
  BEFORE INSERT OR UPDATE ON public.merchant_accounts
  FOR EACH ROW EXECUTE FUNCTION public.reject_fampay_provider();

DROP TRIGGER IF EXISTS merchant_upi_ids_no_fampay ON public.merchant_upi_ids;
CREATE TRIGGER merchant_upi_ids_no_fampay
  BEFORE INSERT OR UPDATE ON public.merchant_upi_ids
  FOR EACH ROW EXECUTE FUNCTION public.reject_fampay_provider();

DROP TRIGGER IF EXISTS payment_links_no_fampay ON public.payment_links;
CREATE TRIGGER payment_links_no_fampay
  BEFORE INSERT ON public.payment_links
  FOR EACH ROW EXECUTE FUNCTION public.reject_fampay_provider();