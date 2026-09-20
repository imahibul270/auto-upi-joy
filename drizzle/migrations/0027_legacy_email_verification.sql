CREATE TABLE IF NOT EXISTS public.email_verifications (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  verified_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.email_verifications TO authenticated;
GRANT ALL ON public.email_verifications TO service_role;

ALTER TABLE public.email_verifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own verification" ON public.email_verifications;
CREATE POLICY "Users read own verification"
ON public.email_verifications FOR SELECT TO authenticated
USING (auth.uid() = user_id);