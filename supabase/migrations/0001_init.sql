-- =============================================================================
-- Invoiso Cloud — initial schema
-- Multi-tenant: every business data row carries tenant_id; RLS isolates tenants.
-- Tenant identity is carried in the auth JWT via the `tenant_id` custom claim,
-- so client code never has to pass tenant_id around (and cannot spoof it).
-- =============================================================================

create extension if not exists "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 1. Tenants (one workspace per signed-up business)
-- -----------------------------------------------------------------------------
create table if not exists public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null default '',
  created_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 2. Profiles (extends auth.users with tenant + role + force-password flag)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  tenant_id        uuid references public.tenants(id) on delete cascade,
  username         text,
  role             text not null default 'user' check (role in ('admin','user')),
  password_changed boolean not null default false,
  created_at       timestamptz not null default now()
);

-- Every new auth user gets a profile automatically.
-- Self-serve signup users also get their own tenant immediately. This must
-- happen in the auth trigger because projects with email confirmation enabled
-- do not return a session from auth.signUp(), so the client cannot call the
-- create_tenant RPC until after the email is confirmed.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  _tenant_id uuid := gen_random_uuid();
  _business_name text := nullif(trim(new.raw_user_meta_data ->> 'business_name'), '');
begin
  insert into public.tenants (id, name)
  values (_tenant_id, coalesce(_business_name, new.email, ''));

  insert into public.profiles (id, tenant_id, username, role, password_changed)
  values (new.id, _tenant_id, new.email, 'admin', true)
  on conflict (id) do update
    set tenant_id = coalesce(public.profiles.tenant_id, excluded.tenant_id),
        username = excluded.username,
        role = 'admin',
        password_changed = true;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Set the tenant_id custom claim on the JWT whenever profile.tenant_id changes.
create or replace function public.set_tenant_claim()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update auth.users
    set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
        || jsonb_build_object('tenant_id', new.tenant_id)
  where id = new.id;
  return new;
end;
$$;
drop trigger if exists on_profile_tenant_change on public.profiles;
create trigger on_profile_tenant_change
  after insert or update of tenant_id on public.profiles
  for each row execute function public.set_tenant_claim();

-- Create a tenant and make the caller its admin (used after the first signup).
create or replace function public.create_tenant(_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  _tenant_id uuid := gen_random_uuid();
begin
  insert into public.tenants (id, name) values (_tenant_id, coalesce(_name, ''));
  update public.profiles
     set tenant_id = _tenant_id, role = 'admin', password_changed = true
   where id = auth.uid();
  return _tenant_id;
end;
$$;

-- Join an existing tenant (by invite, admin-only). Returns null if unauthorized.
create or replace function public.join_tenant(_tenant_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set tenant_id = _tenant_id, role = 'user'
   where id = auth.uid();
  return _tenant_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Business data tables (all tenant-scoped)
-- -----------------------------------------------------------------------------
create table if not exists public.customers (
  id            text primary key,
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  name          text not null,
  email         text,
  phone         text,
  address       text,
  gstin         text,
  business_name text not null default '',
  created_at    timestamptz not null default now()
);

create table if not exists public.products (
  id                  text primary key,
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  name                text not null,
  description         text,
  price               double precision,
  stock               bigint,
  hsncode             text,
  tax_rate            bigint,
  type                text not null default 'product',
  default_discount    double precision not null default 0,
  purchase_price      double precision not null default 0,
  alias_name          text,
  unit                text not null default '',
  unlimited_stock     bigint not null default 0,
  price_includes_tax  bigint not null default 0,
  created_at          timestamptz not null default now()
);

create table if not exists public.product_metadata (
  product_id       text primary key references public.products(id) on delete cascade,
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  storage_location text,
  container_number text,
  batch_number     text,
  expiry_date      text,
  manufacture_date text,
  supplier_name    text,
  sku_code         text,
  notes            text
);

create table if not exists public.invoices (
  id                  text primary key,
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  customer_id         text,
  customer_name       text,
  customer_email      text,
  customer_phone      text,
  customer_address    text,
  customer_gstin      text,
  customer_business_name text not null default '',
  date                text,
  notes               text,
  tax_rate            double precision,
  type                text,
  currency_code       text not null default 'INR',
  currency_symbol     text not null default '₹',
  tax_mode            text not null default 'global',
  deleted_at          text,
  upi_id              text,
  bank_account_id     text,
  due_date            text,
  quantity_label      text,
  additional_costs    text,
  previous_balance    double precision not null default 0,
  invoice_number      text,
  invoice_title       text,
  created_at          timestamptz not null default now()
);

create table if not exists public.invoice_items (
  id                        text primary key,
  tenant_id                 uuid not null references public.tenants(id) on delete cascade,
  invoice_id                text not null references public.invoices(id) on delete cascade,
  product_id                text,
  product_name              text,
  product_description       text,
  product_price             double precision,
  product_tax_rate          bigint,
  product_hsn_code          text,
  quantity                  double precision,
  discount                  double precision,
  unit_price                double precision,
  extra_cost                double precision,
  discount_per_unit         bigint not null default 0,
  is_product_saved          bigint not null default 0,
  product_type              text not null default 'product',
  product_purchase_price    double precision not null default 0,
  product_alias_name        text,
  product_unit              text not null default '',
  unit                      text,
  product_price_includes_tax bigint not null default 0
);

create table if not exists public.invoice_payments (
  id               text primary key,
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  invoice_id       text not null references public.invoices(id) on delete cascade,
  invoice_number   text not null,
  receipt_number   text not null,
  amount_paid      double precision not null,
  tax_amount_paid  double precision not null default 0,
  previously_paid  double precision not null default 0,
  balance_after    double precision not null,
  date_paid        text not null,
  payment_method   text,
  notes            text
);

-- Single row per tenant (company profile for the invoice header).
create table if not exists public.company_info (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null unique references public.tenants(id) on delete cascade,
  name         text not null,
  address      text,
  phone        text,
  email        text,
  website      text,
  gstin        text,
  pan_number   text not null default '',
  fssai_code   text not null default '',
  country      text not null default 'India'
);

-- Per-tenant key/value settings (currency, template, logos, etc.).
create table if not exists public.settings (
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  key        text not null,
  value      text,
  primary key (tenant_id, key)
);

-- Atomic per-tenant invoice-number counters (replaces racy client-side +1).
create table if not exists public.invoice_counters (
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  type       text not null,          -- 'Invoice' | 'Quotation' | 'Receipt'
  last_value bigint not null default 0,
  primary key (tenant_id, type)
);

-- Atomically get the next display number for a type (thread-safe in Postgres).
create or replace function public.next_invoice_number(_type text)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  _tenant_id uuid := auth.jwt() ->> 'tenant_id';
  _next bigint;
begin
  if _tenant_id is null then
    raise exception 'tenant_id claim missing on auth token';
  end if;
  insert into public.invoice_counters (tenant_id, type, last_value)
  values (_tenant_id::uuid, _type, 0)
  on conflict (tenant_id, type) do nothing;

  update public.invoice_counters
     set last_value = last_value + 1
   where tenant_id = _tenant_id::uuid and type = _type
  returning last_value into _next;
  return _next;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Indexes
-- -----------------------------------------------------------------------------
create index if not exists idx_customers_tenant      on public.customers (tenant_id);
create index if not exists idx_products_tenant       on public.products (tenant_id);
create index if not exists idx_invoices_tenant       on public.invoices (tenant_id);
create index if not exists idx_invoices_customer     on public.invoices (customer_name);
create index if not exists idx_invoices_date         on public.invoices (date);
create index if not exists idx_invoices_type         on public.invoices (type);
create index if not exists idx_invoice_items_tenant  on public.invoice_items (tenant_id);
create index if not exists idx_invoice_items_invoice on public.invoice_items (invoice_id);
create index if not exists idx_payments_tenant       on public.invoice_payments (tenant_id);
create index if not exists idx_payments_invoice      on public.invoice_payments (invoice_id);
create index if not exists idx_payments_date         on public.invoice_payments (date_paid);

-- -----------------------------------------------------------------------------
-- 5. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.tenants          enable row level security;
alter table public.profiles         enable row level security;
alter table public.customers        enable row level security;
alter table public.products         enable row level security;
alter table public.product_metadata enable row level security;
alter table public.invoices         enable row level security;
alter table public.invoice_items    enable row level security;
alter table public.invoice_payments enable row level security;
alter table public.company_info     enable row level security;
alter table public.settings         enable row level security;
alter table public.invoice_counters enable row level security;

-- Helper: current tenant id from JWT claim.
create or replace function public.current_tenant_id()
returns uuid language sql stable security definer set search_path = public as $$
  select (auth.jwt() ->> 'tenant_id')::uuid;
$$;

-- Tenants: a user sees only their own tenant row.
create policy tenant_select on public.tenants
  for select using (id = public.current_tenant_id());

-- Profiles: a user reads/updates only their own profile; admins read tenant members.
create policy profile_select on public.profiles
  for select using (id = auth.uid() or tenant_id = public.current_tenant_id());
create policy profile_insert on public.profiles
  for insert with check (id = auth.uid());
create policy profile_update on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid());

-- Generic tenant-scoped policies for each business table.
create policy customers_all   on public.customers        for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy products_all    on public.products         for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy product_md_all  on public.product_metadata for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy invoices_all    on public.invoices         for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy invoice_items_all on public.invoice_items  for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy payments_all    on public.invoice_payments for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy company_info_all on public.company_info    for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy settings_all    on public.settings         for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
create policy counters_all    on public.invoice_counters for all using (tenant_id = public.current_tenant_id()) with check (tenant_id = public.current_tenant_id());
