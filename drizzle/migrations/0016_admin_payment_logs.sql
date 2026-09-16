create or replace function public.admin_payment_logs(_search text default '', _limit int default 200)
returns json
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json)
  from (
    select
      pl.id,
      pl.order_id,
      pl.slug,
      pl.amount,
      pl.payable_amount,
      pl.status::text as status,
      pl.customer_name,
      pl.payer_name,
      pl.clicks,
      pl.created_at,
      pl.paid_at,
      pl.expires_at,
      pl.user_id,
      coalesce(p.full_name, '') as merchant_name,
      coalesce(u.email, '') as merchant_email
    from public.payment_links pl
    left join public.profiles p on p.id = pl.user_id
    left join auth.users u on u.id = pl.user_id
    where public.is_platform_admin()
      and (
        coalesce(_search, '') = ''
        or pl.order_id ilike '%' || _search || '%'
        or coalesce(u.email, '') ilike '%' || _search || '%'
        or coalesce(p.full_name, '') ilike '%' || _search || '%'
        or coalesce(pl.customer_name, '') ilike '%' || _search || '%'
      )
    order by pl.created_at desc
    limit least(greatest(coalesce(_limit, 200), 1), 1000)
  ) t;
$$;

revoke all on function public.admin_payment_logs(text, int) from public, anon;
grant execute on function public.admin_payment_logs(text, int) to authenticated, service_role;