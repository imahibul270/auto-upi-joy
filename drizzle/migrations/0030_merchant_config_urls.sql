CREATE TABLE IF NOT EXISTS public.merchant_config (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  success_url text,
  failure_url text,
  webhook_url text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.merchant_config TO authenticated;
GRANT ALL ON public.merchant_config TO service_role;

ALTER TABLE public.merchant_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own config" ON public.merchant_config;
CREATE POLICY "Users read own config" ON public.merchant_config
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Save / read helpers (writes only through this definer function).
CREATE OR REPLACE FUNCTION public.save_merchant_config(_success_url text, _failure_url text, _webhook_url text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE u uuid := auth.uid();
        s text := nullif(btrim(coalesce(_success_url, '')), '');
        f text := nullif(btrim(coalesce(_failure_url, '')), '');
        w text := nullif(btrim(coalesce(_webhook_url, '')), '');
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF s IS NOT NULL AND s !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_SUCCESS_URL'; END IF;
  IF f IS NOT NULL AND f !~* '^https?://' THEN RAISE EXCEPTION 'INVALID_FAILURE_URL'; END IF;
  IF w IS NOT NULL AND w !~* '^https://' THEN RAISE EXCEPTION 'INVALID_WEBHOOK_URL'; END IF;

  INSERT INTO public.merchant_config (user_id, success_url, failure_url, webhook_url, updated_at)
  VALUES (u, left(s, 500), left(f, 500), left(w, 500), now())
  ON CONFLICT (user_id) DO UPDATE
    SET success_url = EXCLUDED.success_url,
        failure_url = EXCLUDED.failure_url,
        webhook_url = EXCLUDED.webhook_url,
        updated_at = now();

  RETURN jsonb_build_object('success_url', s, 'failure_url', f, 'webhook_url', w);
END $function$;

REVOKE ALL ON FUNCTION public.save_merchant_config(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_merchant_config(text, text, text) TO authenticated, service_role;

-- Public pay page needs the owner's redirect URLs (never the webhook URL).
CREATE OR REPLACE FUNCTION public.get_public_payment_link(_slug text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE r public.payment_links%ROWTYPE; c public.merchant_config%ROWTYPE;
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
    'success_url', c.success_url,
    'failure_url', c.failure_url,
    'server_now', now()
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.get_public_payment_link(text) TO anon, authenticated, service_role;