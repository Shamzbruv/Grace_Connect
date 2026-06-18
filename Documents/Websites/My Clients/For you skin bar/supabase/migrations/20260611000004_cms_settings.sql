-- Blog Posts
create table if not exists public.blog_posts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  excerpt text,
  content text,
  featured_image_url text,
  status text check (status in ('draft', 'published', 'archived')) default 'draft',
  published_at timestamptz,
  seo_title text,
  seo_description text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Pages
create table if not exists public.pages (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  content jsonb,
  seo_title text,
  seo_description text,
  status text check (status in ('draft', 'published', 'archived')) default 'published',
  updated_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Store Settings
create table if not exists public.store_settings (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  value jsonb not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz default now()
);

-- Newsletter Subscribers
create table if not exists public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  source text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- Contact Messages
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  phone text,
  inquiry_type text,
  message text not null,
  status text check (status in ('new', 'read', 'replied', 'archived')) default 'new',
  created_at timestamptz default now()
);

-- Custom Order Requests
create table if not exists public.custom_order_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  event_type text,
  event_date date,
  quantity int,
  product_interest text,
  notes text,
  status text check (status in ('new', 'quoted', 'approved', 'declined', 'completed')) default 'new',
  created_at timestamptz default now()
);

-- Quiz System
create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  question_text text not null,
  sort_order int not null,
  is_active boolean default true
);

create table if not exists public.quiz_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid references public.quiz_questions(id) on delete cascade,
  label text not null,
  value text not null,
  sort_order int default 0
);

create table if not exists public.quiz_recommendation_rules (
  id uuid primary key default gen_random_uuid(),
  skin_type text,
  skin_concern text,
  routine_step text,
  product_id uuid references public.products(id),
  priority int default 0,
  is_active boolean default true
);

-- RLS
alter table public.blog_posts enable row level security;
alter table public.pages enable row level security;
alter table public.store_settings enable row level security;
alter table public.newsletter_subscribers enable row level security;
alter table public.contact_messages enable row level security;
alter table public.custom_order_requests enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_options enable row level security;
alter table public.quiz_recommendation_rules enable row level security;

create policy "Anyone can view published blog posts"
on public.blog_posts for select using (status = 'published');

create policy "Admins can manage blog posts"
on public.blog_posts for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view published pages"
on public.pages for select using (status = 'published');

create policy "Admins can manage pages"
on public.pages for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view store settings"
on public.store_settings for select using (true);

create policy "Admins can manage store settings"
on public.store_settings for all using (public.is_admin()) with check (public.is_admin());

create policy "Public can insert newsletter subscribers"
on public.newsletter_subscribers for insert with check (true);

create policy "Admins can view and manage newsletter subscribers"
on public.newsletter_subscribers for all using (public.is_admin()) with check (public.is_admin());

create policy "Public can insert contact messages"
on public.contact_messages for insert with check (true);

create policy "Admins can view and manage contact messages"
on public.contact_messages for all using (public.is_admin()) with check (public.is_admin());

create policy "Public can insert custom order requests"
on public.custom_order_requests for insert with check (true);

create policy "Admins can view and manage custom order requests"
on public.custom_order_requests for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view quiz questions"
on public.quiz_questions for select using (is_active = true);

create policy "Admins can manage quiz questions"
on public.quiz_questions for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view quiz options"
on public.quiz_options for select using (true);

create policy "Admins can manage quiz options"
on public.quiz_options for all using (public.is_admin()) with check (public.is_admin());

create policy "Anyone can view quiz rules"
on public.quiz_recommendation_rules for select using (is_active = true);

create policy "Admins can manage quiz rules"
on public.quiz_recommendation_rules for all using (public.is_admin()) with check (public.is_admin());
