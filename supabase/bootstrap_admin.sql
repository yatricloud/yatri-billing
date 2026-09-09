-- =============================================================================
-- Bootstrap an admin user + tenant for Invoiso Cloud
-- =============================================================================
-- Run this AFTER applying 0001_init.sql, in the Supabase Dashboard:
--   Dashboard → SQL Editor → paste 0001_init.sql → Run
--   Then paste this file (edit the email) → Run
--
-- STEP 1 (UI): Create the login user first:
--   Dashboard → Authentication → Users → Add user
--   Enter an EMAIL + a TEMPORARY password, confirm email.
--   This triggers `handle_new_user`, which inserts their `profiles` row.
--
-- STEP 2 (SQL, here): create the tenant and make that user its admin.
--   Replace 'you@company.com' with the email you used in Step 1.
-- =============================================================================

do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
begin
  -- The auth user must already exist (created via the dashboard in Step 1).
  select id into v_user_id
    from auth.users
   where email = 'you@company.com'
   limit 1;

  if v_user_id is null then
    raise exception 'No auth user with email you@company.com. Create it in Authentication → Users first.';
  end if;

  -- Create the workspace/tenant.
  insert into public.tenants (name) values ('My Company')
  returning id into v_tenant_id;

  -- Link the user's profile to the tenant as admin.
  update public.profiles
     set tenant_id = v_tenant_id, role = 'admin', password_changed = true
   where id = v_user_id;

  -- The on_profile_tenant_change trigger already stamped tenant_id onto the JWT.
  raise notice 'Tenant % created; user % is admin.', v_tenant_id, v_user_id;
end $$;
