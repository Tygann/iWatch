create table public.account_profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null check (char_length(btrim(display_name)) between 1 and 80)
);

alter table public.account_profiles enable row level security;

revoke all on public.account_profiles from public, anon, authenticated;
grant select, insert on public.account_profiles to authenticated;
grant update on public.account_profiles to authenticated;

create policy "Read own profile" on public.account_profiles
    for select to authenticated using ((select auth.uid()) = id);

create policy "Create own profile" on public.account_profiles
    for insert to authenticated with check ((select auth.uid()) = id);

create policy "Rename own profile" on public.account_profiles
    for update to authenticated using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);
