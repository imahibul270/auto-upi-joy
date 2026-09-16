CREATE TABLE IF NOT EXISTS public.platform_settings (
  key text PRIMARY KEY,
  value numeric NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.platform_settings TO anon;
GRANT SELECT ON public.platform_settings TO authenticated;
GRANT ALL ON public.platform_settings TO service_role;

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Platform settings are public" ON public.platform_settings;
CREATE POLICY "Platform settings are public"
  ON public.platform_settings FOR SELECT
  TO anon, authenticated
  USING (true);

INSERT INTO public.platform_settings (key, value)
VALUES ('pro_price', 299)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_pro_price()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM public.platform_settings WHERE key = 'pro_price'), 299);
$$;

GRANT EXECUTE ON FUNCTION public.get_pro_price() TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_set_pro_price(_price numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF _price IS NULL OR _price < 1 OR _price > 100000 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  INSERT INTO public.platform_settings (key, value, updated_at)
  VALUES ('pro_price', round(_price, 2), now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

  RETURN round(_price, 2);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_pro_price(numeric) TO authenticated, service_role;