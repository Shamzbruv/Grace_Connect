-- Customers
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text,
  phone text,
  whatsapp text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Orders
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,
  customer_id uuid references public.customers(id),
  status text check (status in ('pending', 'confirmed', 'processing', 'ready_for_pickup', 'shipped', 'delivered', 'cancelled', 'refunded')) default 'pending',
  payment_status text check (payment_status in ('unpaid', 'awaiting_confirmation', 'paid', 'partially_paid', 'refunded')) default 'unpaid',
  fulfillment_status text check (fulfillment_status in ('unfulfilled', 'packed', 'shipped', 'delivered', 'picked_up')) default 'unfulfilled',
  delivery_method text check (delivery_method in ('delivery', 'pickup')),
  payment_method text,
  shipping_address text,
  parish text,
  subtotal_jmd numeric(12,2) not null,
  discount_total_jmd numeric(12,2) default 0,
  shipping_total_jmd numeric(12,2) default 0,
  grand_total_jmd numeric(12,2) not null,
  customer_notes text,
  admin_notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Order Items
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  sku text,
  unit_price_jmd numeric(12,2) not null,
  quantity int not null,
  line_total_jmd numeric(12,2) not null
);

-- Order Status History
create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  old_status text,
  new_status text,
  changed_by uuid references public.profiles(id),
  note text,
  created_at timestamptz default now()
);

-- RLS
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;

create policy "Public can insert customers"
on public.customers for insert with check (true);

create policy "Admins can manage customers"
on public.customers for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can view and manage orders"
on public.orders for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can view and manage order items"
on public.order_items for all using (public.is_admin()) with check (public.is_admin());

create policy "Admins can view and manage order status history"
on public.order_status_history for all using (public.is_admin()) with check (public.is_admin());
