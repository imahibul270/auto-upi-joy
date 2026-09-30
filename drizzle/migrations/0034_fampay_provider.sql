ALTER TYPE public.upi_provider ADD VALUE IF NOT EXISTS 'fampay';
ALTER TABLE public.payment_links ADD COLUMN IF NOT EXISTS utr text;

CREATE OR REPLACE FUNCTION public.add_upi_id(_upi_id text, _payee_name text DEFAULT ''::text, _provider text DEFAULT 'phonepe'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _u uuid := auth.uid(); v text := lower(btrim(COALESCE(_upi_id, ''))); n int; rid uuid;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v !~ '^[a-z0-9._-]{2,255}@[a-z0-9.-]{2,64}$' THEN RAISE EXCEPTION 'INVALID_UPI_ID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_u::text, 11));
  SELECT count(*) INTO n FROM merchant_upi_ids WHERE user_id = _u;
  IF n >= 10 THEN RAISE EXCEPTION 'UPI_LIMIT_REACHED'; END IF;
  IF EXISTS (SELECT 1 FROM merchant_upi_ids WHERE user_id = _u AND lower(upi_id) = v) THEN RAISE EXCEPTION 'UPI_ALREADY_ADDED'; END IF;
  INSERT INTO merchant_upi_ids (user_id, provider, upi_id, payee_name, is_primary)
  VALUES (_u, (CASE WHEN _provider IN ('paytm','fampay') THEN _provider ELSE 'phonepe' END)::upi_provider,
          v, left(btrim(COALESCE(_payee_name, '')), 100), n = 0)
  RETURNING id INTO rid;
  RETURN jsonb_build_object('id', rid);
END $function$;

CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE; c public.merchant_config%ROWTYPE; fam boolean;
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
  fam := r.provider::text = 'fampay' AND r.status = 'paid';
  RETURN jsonb_build_object(
    'found', true, 'order_id', r.order_id, 'slug', r.slug, 'customer_name', r.customer_name,
    'amount', r.amount, 'payable_amount', r.payable_amount, 'upi_id', r.upi_id,
    'payee_name', r.payee_name, 'status', r.status, 'expires_at', r.expires_at,
    'success_url', c.success_url, 'failure_url', c.failure_url, 'server_now', now(),
    'provider', r.provider,
    'payer_name', CASE WHEN fam THEN r.payer_name END,
    'utr', CASE WHEN fam THEN r.utr END
  );
END $function$;