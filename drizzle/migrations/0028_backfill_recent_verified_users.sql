INSERT INTO public.email_verifications (user_id, verified_at)
SELECT id, now() FROM auth.users WHERE created_at >= '2026-09-20 00:00:00+00'
ON CONFLICT (user_id) DO NOTHING;