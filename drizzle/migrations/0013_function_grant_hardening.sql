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