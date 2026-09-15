DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_business_logo_size'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_business_logo_size
      CHECK (business_logo IS NULL OR length(business_logo) <= 700000);
  END IF;
END $$;