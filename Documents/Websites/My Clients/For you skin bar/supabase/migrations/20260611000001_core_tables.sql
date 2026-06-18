-- Profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users(id),
  full_name text,
  email text,
  role text check (role in ('owner', 'admin', 'staff', 'viewer')),
  is_active boolean default true,
  created_at timestamptz default now()
);

-- Admin check helper
create or replace function public.is_admin()
returns boolean
language sql
security definer
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
    and role in ('owner', 'admin', 'staff')
    and is_active = true
  );
$$;

-- Categories
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  description text,
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- Products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  old_static_id int,
  category_id uuid references public.categories(id),
  name text not null,
  slug text unique not null,
  sku text unique,
  short_description text,
  description text,
  best_for text,
  price_jmd numeric(12,2) not null,
  compare_at_price_jmd numeric(12,2),
  cost_price_jmd numeric(12,2),
  type text check (type in ('physical', 'digital')),
  status text check (status in ('draft', 'active', 'archived')) default 'draft',
  badge text,
  size text,
  routine_step text,
  when_to_use text,
  how_to_use text,
  is_featured boolean default false,
  is_taxable boolean default false,
  track_inventory boolean default true,
  stock_quantity int default 0,
  low_stock_threshold int default 5,
  allow_backorder boolean default false,
  seo_title text,
  seo_description text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Product Images
create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  image_url text not null,
  alt_text text,
  sort_order int default 0,
  is_primary boolean default false,
  created_at timestamptz default now()
);

-- Product Tags
create table if not exists public.product_tags (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  type text check (type in ('skin_concern', 'skin_type', 'ingredient', 'collection'))
);

-- Product Tag Links
create table if not exists public.product_tag_links (
  product_id uuid references public.products(id) on delete cascade,
  tag_id uuid references public.product_tags(id) on delete cascade,
  primary key (product_id, tag_id)
);

-- RLS
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.product_tags enable row level security;
alter table public.product_tag_links enable row level security;

create policy "Admins can view and edit profiles"
on public.profiles for all using (public.is_admin()) with check (public.is_admin());

create policy "Users can view own profile"
on public.profiles for select using (auth.uid() = id);

create policy "Anyone can view active categories"
on public.categories for select using (is_active = true);

create policy "Admins can manage categories"
on public.categories for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view active products"
on public.products for select using (status = 'active');

create policy "Admins can manage products"
on public.products for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view images for active products"
on public.product_images for select using (
  exists (select 1 from public.products where id = product_images.product_id and status = 'active')
);

create policy "Admins can manage product images"
on public.product_images for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view tags"
on public.product_tags for select using (true);

create policy "Admins can manage tags"
on public.product_tags for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view tag links"
on public.product_tag_links for select using (true);

create policy "Admins can manage tag links"
on public.product_tag_links for all using (public.is_admin()) with check (public.is_admin());
