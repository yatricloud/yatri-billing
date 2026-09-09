-- Auto-stamp tenant_id on INSERT for all tenant-scoped business tables.
-- Client repositories intentionally omit tenant_id (RLS + JWT claim handle
-- isolation); this trigger fills it from the authenticated user's JWT so
-- INSERT ... WITH CHECK (tenant_id = current_tenant_id()) succeeds.

create or replace function public.set_tenant_id_on_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tenant_id is null then
    new.tenant_id := public.current_tenant_id();
  end if;
  if new.tenant_id is null then
    raise exception 'tenant_id claim missing on auth token';
  end if;
  return new;
end;
$$;

-- customers
drop trigger if exists trg_customers_tenant on public.customers;
create trigger trg_customers_tenant
  before insert on public.customers
  for each row execute function public.set_tenant_id_on_insert();

-- products
drop trigger if exists trg_products_tenant on public.products;
create trigger trg_products_tenant
  before insert on public.products
  for each row execute function public.set_tenant_id_on_insert();

-- product_metadata
drop trigger if exists trg_product_metadata_tenant on public.product_metadata;
create trigger trg_product_metadata_tenant
  before insert on public.product_metadata
  for each row execute function public.set_tenant_id_on_insert();

-- invoices
drop trigger if exists trg_invoices_tenant on public.invoices;
create trigger trg_invoices_tenant
  before insert on public.invoices
  for each row execute function public.set_tenant_id_on_insert();

-- invoice_items
drop trigger if exists trg_invoice_items_tenant on public.invoice_items;
create trigger trg_invoice_items_tenant
  before insert on public.invoice_items
  for each row execute function public.set_tenant_id_on_insert();

-- invoice_payments
drop trigger if exists trg_invoice_payments_tenant on public.invoice_payments;
create trigger trg_invoice_payments_tenant
  before insert on public.invoice_payments
  for each row execute function public.set_tenant_id_on_insert();

-- company_info
drop trigger if exists trg_company_info_tenant on public.company_info;
create trigger trg_company_info_tenant
  before insert on public.company_info
  for each row execute function public.set_tenant_id_on_insert();

-- settings
drop trigger if exists trg_settings_tenant on public.settings;
create trigger trg_settings_tenant
  before insert on public.settings
  for each row execute function public.set_tenant_id_on_insert();

-- invoice_counters
drop trigger if exists trg_invoice_counters_tenant on public.invoice_counters;
create trigger trg_invoice_counters_tenant
  before insert on public.invoice_counters
  for each row execute function public.set_tenant_id_on_insert();
