CREATE OR REPLACE FUNCTION public.add_upi_id(_upi_id text, _payee_name text DEFAULT '', _provider text DEFAULT 'phonepe') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _u uuid := auth.uid(); v text := lower(btrim(COALESCE(_upi_id, ''))); n int; rid uuid;
BEGIN
  IF _u IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v !~ '^[a-z0-9._-]{2,255}@[a-z0-9.-]{2,64}$' THEN RAISE EXCEPTION 'INVALID_UPI_ID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_u::text, 11));
  SELECT count(*) INTO n FROM merchant_upi_ids WHERE user_id = _u;
  IF n >= 10 THEN RAISE EXCEPTION 'UPI_LIMIT_REACHED'; END IF;
  IF EXISTS (SELECT 1 FROM merchant_upi_ids WHERE user_id = _u AND lower(upi_id) = v) THEN RAISE EXCEPTION 'UPI_ALREADY_ADDED'; END IF;
  INSERT INTO merchant_upi_ids (user_id, provider, upi_id, payee_name, is_primary)
  VALUES (_u, CASE WHEN _provider = 'paytm' THEN 'paytm'::upi_provider ELSE 'phonepe'::upi_provider END,
          v, left(btrim(COALESCE(_payee_name, '')), 100), n = 0)
  RETURNING id INTO rid;
  RETURN jsonb_build_object('id', rid);
END $$;