insert into storage.buckets (id, name, public) values 
  ('product-images', 'product-images', true),
  ('blog-images', 'blog-images', true),
  ('brand-assets', 'brand-assets', true),
  ('private-files', 'private-files', false)
on conflict (id) do nothing;

create policy "Anyone can view product images"
on storage.objects for select using (bucket_id = 'product-images');

create policy "Admins can upload product images"
on storage.objects for insert with check (bucket_id = 'product-images' and public.is_admin());

create policy "Admins can update product images"
on storage.objects for update using (bucket_id = 'product-images' and public.is_admin());

create policy "Admins can delete product images"
on storage.objects for delete using (bucket_id = 'product-images' and public.is_admin());

create policy "Anyone can view blog images"
on storage.objects for select using (bucket_id = 'blog-images');

create policy "Admins can manage blog images"
on storage.objects for all using (bucket_id = 'blog-images' and public.is_admin()) with check (bucket_id = 'blog-images' and public.is_admin());

create policy "Anyone can view brand assets"
on storage.objects for select using (bucket_id = 'brand-assets');

create policy "Admins can manage brand assets"
on storage.objects for all using (bucket_id = 'brand-assets' and public.is_admin()) with check (bucket_id = 'brand-assets' and public.is_admin());

create policy "Admins can manage private files"
on storage.objects for all using (bucket_id = 'private-files' and public.is_admin()) with check (bucket_id = 'private-files' and public.is_admin());
