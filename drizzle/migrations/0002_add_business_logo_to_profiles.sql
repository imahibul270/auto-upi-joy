ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS business_logo TEXT;

COMMENT ON COLUMN public.profiles.business_logo IS 'Merchant-provided business logo stored as a validated image data URL.';