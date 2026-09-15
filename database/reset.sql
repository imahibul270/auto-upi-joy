-- =====================================================================
-- Auto Upi — RESET (DESTRUCTIVE)
-- Removes every object created by setup.sql, including all profile data.
-- Only run this on a project you are happy to wipe.
-- =====================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
DROP FUNCTION IF EXISTS public.set_updated_at();

DROP TABLE IF EXISTS public.profiles;
