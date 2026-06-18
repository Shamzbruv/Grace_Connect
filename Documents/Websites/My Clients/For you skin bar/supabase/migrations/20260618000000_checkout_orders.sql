create table orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,

  full_name text not null,
  phone text not null,
  email text not null,

  country text not null default 'Jamaica',
  address_line_1 text,
  address_line_2 text,
  city text,
  parish text,
  state_province text,
  postal_code text,

  delivery_method text not null,
  delivery_notes text,

  subtotal numeric(10,2) not null,
  shipping_amount numeric(10,2) default 0,
  shipping_status text default 'confirmed',
  total numeric(10,2) not null,
  currency text default 'JMD',

  payment_method text default 'WiPay',
  payment_status text default 'pending confirmation',
  order_status text default 'received',

  notes text,
  created_at timestamptz default now()
);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade,

  product_id text,
  product_name text not null,
  variant_name text,
  unit_price numeric(10,2) not null,
  quantity int not null,
  line_total numeric(10,2) not null,
  image_url text
);

create table email_logs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade,
  recipient text not null,
  email_type text not null,
  resend_email_id text,
  status text default 'sent',
  error_message text,
  created_at timestamptz default now()
);
