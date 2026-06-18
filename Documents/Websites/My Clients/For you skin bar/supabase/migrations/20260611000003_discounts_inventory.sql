-- Inventory Movements
create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id),
  change_quantity int not null,
  reason text check (reason in ('manual_adjustment', 'order_created', 'order_cancelled', 'restock', 'damage', 'return')),
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

-- Discounts
create table if not exists public.discounts (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  description text,
  discount_type text check (discount_type in ('percentage', 'fixed_amount', 'free_shipping')),
  discount_value numeric(12,2) not null,
  minimum_order_total_jmd numeric(12,2),
  maximum_discount_jmd numeric(12,2),
  usage_limit_total int,
  usage_limit_per_customer int,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean default true,
  applies_to text check (applies_to in ('all_products', 'specific_products', 'specific_categories')) default 'all_products',
  created_at timestamptz default now()
);

-- Discount Product Rules
create table if not exists public.discount_product_rules (
  discount_id uuid references public.discounts(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,
  primary key (discount_id, product_id)
);

-- Discount Category Rules
create table if not exists public.discount_category_rules (
  discount_id uuid references public.discounts(id) on delete cascade,
  category_id uuid references public.categories(id) on delete cascade,
  primary key (discount_id, category_id)
);

-- Discount Redemptions
create table if not exists public.discount_redemptions (
  id uuid primary key default gen_random_uuid(),
  discount_id uuid references public.discounts(id),
  order_id uuid references public.orders(id),
  customer_id uuid references public.customers(id),
  amount_jmd numeric(12,2),
  created_at timestamptz default now()
);

-- RLS
alter table public.inventory_movements enable row level security;
alter table public.discounts enable row level security;
alter table public.discount_product_rules enable row level security;
alter table public.discount_category_rules enable row level security;
alter table public.discount_redemptions enable row level security;

create policy "Admins can manage inventory movements"
on public.inventory_movements for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can manage discounts"
on public.discounts for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can manage discount product rules"
on public.discount_product_rules for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can manage discount category rules"
on public.discount_category_rules for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can view and manage discount redemptions"
on public.discount_redemptions for all using (public.is_admin()) with check (public.is_admin());
