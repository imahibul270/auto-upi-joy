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