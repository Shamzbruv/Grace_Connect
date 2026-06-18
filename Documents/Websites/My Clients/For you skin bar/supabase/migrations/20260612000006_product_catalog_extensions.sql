-- Product catalog extensions for complete CSV-to-Supabase-to-website sync.
-- Adds the missing fields needed by the admin product editor, product page, variants, and custom page sections.

alter table public.products add column if not exists ingredients_html text;
alter table public.products add column if not exists best_for_html text;
alter table public.products add column if not exists how_to_use_html text;
alter table public.products add column if not exists return_policy_html text;
alter table public.products add column if not exists brand text;
alter table public.products add column if not exists weight text;
alter table public.products add column if not exists discount_mode text;
alter table public.products add column if not exists discount_value numeric(12,2);
alter table public.products add column if not exists external_source text;
alter table public.products add column if not exists source_handle_id text;

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  sku text,
  price_jmd numeric(12,2),
  compare_at_price_jmd numeric(12,2),
  stock_quantity int default 0,
  track_inventory boolean default true,
  image_url text,
  is_active boolean default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(product_id, name)
);

create table if not exists public.product_info_sections (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  title text not null,
  body text,
  sort_order int default 0,
  is_visible boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_info_sections_product_id on public.product_info_sections(product_id);

alter table public.product_variants enable row level security;
alter table public.product_info_sections enable row level security;

drop policy if exists "Anyone can view active product variants" on public.product_variants;
create policy "Anyone can view active product variants"
on public.product_variants for select using (
  is_active = true
  and exists (
    select 1 from public.products
    where products.id = product_variants.product_id
    and products.status = 'active'
  )
);

drop policy if exists "Admins can manage product variants" on public.product_variants;
create policy "Admins can manage product variants"
on public.product_variants for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Anyone can view visible product info sections" on public.product_info_sections;
create policy "Anyone can view visible product info sections"
on public.product_info_sections for select using (
  is_visible = true
  and exists (
    select 1 from public.products
    where products.id = product_info_sections.product_id
    and products.status = 'active'
  )
);

drop policy if exists "Admins can manage product info sections" on public.product_info_sections;
create policy "Admins can manage product info sections"
on public.product_info_sections for all using (public.is_admin()) with check (public.is_admin());
