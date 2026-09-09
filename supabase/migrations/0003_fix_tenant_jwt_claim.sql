-- Supabase JWTs nest custom claims under app_metadata, not as top-level keys.
-- Read tenant_id from either location so RLS and RPCs work after login.

create or replace function public.current_tenant_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    nullif(auth.jwt() ->> 'tenant_id', '')::uuid,
    nullif(auth.jwt() -> 'app_metadata' ->> 'tenant_id', '')::uuid
  );
$$;

create or replace function public.next_invoice_number(_type text)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  _tenant_id uuid := public.current_tenant_id();
  _next bigint;
begin
  if _tenant_id is null then
    raise exception 'tenant_id claim missing on auth token';
  end if;
  insert into public.invoice_counters (tenant_id, type, last_value)
  values (_tenant_id, _type, 0)
  on conflict (tenant_id, type) do nothing;

  update public.invoice_counters
     set last_value = last_value + 1
   where tenant_id = _tenant_id and type = _type
  returning last_value into _next;
  return _next;
end;
$$;
