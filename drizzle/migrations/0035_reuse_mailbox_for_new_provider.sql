CREATE OR REPLACE FUNCTION public.save_merchant_account(_provider text, _upi_id text, _payee_name text DEFAULT ''::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _user uuid := auth.uid(); r public.merchant_accounts%ROWTYPE; src public.merchant_accounts%ROWTYPE;
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

  -- Reuse the mailbox (email + app password) already connected on another provider.
  IF NOT r.connected THEN
    SELECT * INTO src FROM public.merchant_accounts
     WHERE user_id = _user AND connected AND id <> r.id AND length(app_password) > 0
     ORDER BY connected_at DESC NULLS LAST LIMIT 1;
    IF src.id IS NOT NULL THEN
      UPDATE public.merchant_accounts
         SET email = src.email, app_password = src.app_password, connected = true, connected_at = now()
       WHERE id = r.id RETURNING * INTO r;
    END IF;
  END IF;

  RETURN jsonb_build_object('provider', r.provider, 'upi_id', r.upi_id, 'payee_name', r.payee_name,
    'email', r.email, 'connected', r.connected, 'connected_at', r.connected_at);
END $function$;