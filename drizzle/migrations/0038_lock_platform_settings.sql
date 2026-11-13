DROP POLICY IF EXISTS "Platform settings are public" ON public.platform_settings;
REVOKE SELECT ON public.platform_settings FROM anon, authenticated;