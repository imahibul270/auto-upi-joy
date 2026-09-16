CREATE TABLE public.plan_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  order_id text NOT NULL UNIQUE,
  slug text NOT NULL,
  amount numeric NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.plan_orders TO authenticated;
GRANT ALL ON public.plan_orders TO service_role;

ALTER TABLE public.plan_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own plan orders"
ON public.plan_orders FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX plan_orders_user_idx ON public.plan_orders (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.complete_plan_order(_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _row public.plan_orders;
BEGIN
  SELECT * INTO _row FROM public.plan_orders WHERE order_id = _order_id FOR UPDATE;
  IF _row.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF _row.status = 'paid' THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;

  UPDATE public.plan_orders
     SET status = 'paid', paid_at = now()
   WHERE id = _row.id;

  PERFORM public.activate_pro_subscription(_row.user_id, 'gateway:' || _row.order_id, _row.amount);

  RETURN jsonb_build_object('ok', true, 'already', false);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_plan_order(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_plan_order(text) TO service_role;