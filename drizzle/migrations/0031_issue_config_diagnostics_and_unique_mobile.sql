-- 1. Mobile number helper + uniqueness for new registrations ---------------
CREATE OR REPLACE FUNCTION public.mobile_digits(_value TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT RIGHT(regexp_replace(COALESCE(_value, ''), '\D', '', 'g'), 10)
$$;

CREATE INDEX IF NOT EXISTS profiles_mobile_digits_idx
  ON public.profiles (public.mobile_digits(mobile));

CREATE OR REPLACE FUNCTION public.profiles_unique_mobile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d TEXT;
BEGIN
  d := public.mobile_digits(NEW.mobile);
  IF LENGTH(d) = 10 THEN
    IF EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id <> NEW.id AND public.mobile_digits(p.mobile) = d
    ) THEN
      RAISE EXCEPTION 'This mobile number is already registered with another account.'
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_unique_mobile_trg ON public.profiles;
CREATE TRIGGER profiles_unique_mobile_trg
  BEFORE INSERT OR UPDATE OF mobile ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_unique_mobile();

-- 2. Admin diagnostics by mobile number -------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_diagnostics(_mobile TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  d TEXT := public.mobile_digits(_mobile);
  uid UUID;
  result JSONB;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  IF LENGTH(d) <> 10 THEN
    RETURN jsonb_build_object('found', false, 'reason', 'bad_number');
  END IF;

  SELECT p.id INTO uid FROM public.profiles p
  WHERE public.mobile_digits(p.mobile) = d
  ORDER BY p.created_at DESC LIMIT 1;

  IF uid IS NULL THEN
    RETURN jsonb_build_object('found', false, 'reason', 'no_user');
  END IF;

  SELECT jsonb_build_object(
    'found', true,
    'now', now(),
    'user', (
      SELECT jsonb_build_object(
        'user_id', u.id,
        'email', u.email,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'full_name', COALESCE(p.full_name, ''),
        'mobile', COALESCE(p.mobile, ''),
        'email_verified', EXISTS (SELECT 1 FROM public.email_verifications v WHERE v.user_id = u.id)
      )
      FROM auth.users u LEFT JOIN public.profiles p ON p.id = u.id WHERE u.id = uid
    ),
    'plan', (
      SELECT jsonb_build_object(
        'plan', s.plan, 'started_at', s.started_at, 'expires_at', s.expires_at,
        'qr_limit', s.qr_limit, 'amount_inr', s.amount_inr
      ) FROM public.subscriptions s WHERE s.user_id = uid
      ORDER BY s.created_at DESC LIMIT 1
    ),
    'quota', jsonb_build_object(
      'qr_used', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid),
      'free_plan_enabled', public.is_free_plan_enabled()
    ),
    'mailbox', (
      SELECT jsonb_build_object(
        'connected', m.connected, 'email', m.email, 'upi_id', m.upi_id, 'payee_name', m.payee_name,
        'has_password', COALESCE(m.app_password, '') <> '',
        'connected_at', m.connected_at, 'last_polled_at', m.last_polled_at,
        'mail_error', m.mail_error, 'mail_error_at', m.mail_error_at, 'mail_ok_at', m.mail_ok_at
      ) FROM public.merchant_accounts m WHERE m.user_id = uid
      ORDER BY m.created_at DESC LIMIT 1
    ),
    'config', (
      SELECT jsonb_build_object('success_url', c.success_url, 'failure_url', c.failure_url, 'webhook_url', c.webhook_url)
      FROM public.merchant_config c WHERE c.user_id = uid
    ),
    'api_key', (
      SELECT jsonb_build_object('active', k.active, 'last_used_at', k.last_used_at, 'created_at', k.created_at)
      FROM public.api_keys k WHERE k.user_id = uid ORDER BY k.created_at DESC LIMIT 1
    ),
    'links', jsonb_build_object(
      'total', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid),
      'paid', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'paid'),
      'expired', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'expired'),
      'active', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'active'),
      'no_click_expired', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND l.status = 'expired' AND COALESCE(l.clicks,0) = 0),
      'last_paid_at', (SELECT MAX(l.paid_at) FROM public.payment_links l WHERE l.user_id = uid),
      'last_created_at', (SELECT MAX(l.created_at) FROM public.payment_links l WHERE l.user_id = uid),
      'webhook_failed', (SELECT COUNT(*) FROM public.payment_links l WHERE l.user_id = uid AND COALESCE(l.webhook_last_error,'') <> '')
    ),
    'recent', COALESCE((
      SELECT jsonb_agg(x ORDER BY x->>'created_at' DESC) FROM (
        SELECT jsonb_build_object(
          'order_id', l.order_id, 'amount', l.amount, 'payable_amount', l.payable_amount,
          'status', l.status, 'clicks', COALESCE(l.clicks,0), 'created_at', l.created_at,
          'paid_at', l.paid_at, 'expires_at', l.expires_at, 'payer_name', l.payer_name,
          'webhook_last_error', l.webhook_last_error
        ) AS x
        FROM public.payment_links l WHERE l.user_id = uid
        ORDER BY l.created_at DESC LIMIT 10
      ) t
    ), '[]'::jsonb),
    'mail_seen', (SELECT COUNT(*) FROM public.processed_emails e WHERE e.user_id = uid)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_diagnostics(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_diagnostics(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mobile_digits(TEXT) TO authenticated, anon, service_role;