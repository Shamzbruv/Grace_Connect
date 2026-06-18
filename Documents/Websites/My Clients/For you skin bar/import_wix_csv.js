const fs = require('fs');
const { parse } = require('csv-parse/sync');
const { Client } = require('pg');

const DATABASE_URL = process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
const CSV_FILE = process.env.CSV_FILE || 'catalog_products (5).csv';

if (!DATABASE_URL) {
  console.error('Missing database connection. Set SUPABASE_DB_URL or DATABASE_URL before running this importer.');
  process.exit(1);
}

const slugify = (value) => String(value || '')
  .toLowerCase()
  .trim()
  .replace(/&/g, 'and')
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/(^-|-$)+/g, '');

const toNumber = (value, fallback = null) => {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
};

const toInt = (value, fallback = 0) => {
  const num = parseInt(value, 10);
  return Number.isFinite(num) ? num : fallback;
};

const imageUrlsFromCsv = (value) => String(value || '')
  .split(';')
  .map(url => url.trim())
  .filter(Boolean)
  .map(url => url.startsWith('http') ? url : `https://static.wixstatic.com/media/${url}`);

async function ensureSchema(client) {
  await client.query(`alter table public.products add column if not exists ingredients_html text;`);
  await client.query(`alter table public.products add column if not exists best_for_html text;`);
  await client.query(`alter table public.products add column if not exists how_to_use_html text;`);
  await client.query(`alter table public.products add column if not exists return_policy_html text;`);
  await client.query(`alter table public.products add column if not exists brand text;`);
  await client.query(`alter table public.products add column if not exists weight text;`);
  await client.query(`alter table public.products add column if not exists discount_mode text;`);
  await client.query(`alter table public.products add column if not exists discount_value numeric(12,2);`);
  await client.query(`alter table public.products add column if not exists external_source text;`);
  await client.query(`alter table public.products add column if not exists source_handle_id text;`);
  await client.query(`
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
  `);
  await client.query(`
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
  `);
}

async function ensureCategory(client, categoryName) {
  const name = String(categoryName || '').trim();
  if (!name) return null;

  const existing = await client.query('select id from public.categories where lower(name) = lower($1) limit 1', [name]);
  if (existing.rows.length) return existing.rows[0].id;

  const baseSlug = slugify(name) || `category-${Date.now()}`;
  let slug = baseSlug;
  let attempt = 1;
  while (true) {
    try {
      const created = await client.query(
        'insert into public.categories (name, slug, is_active) values ($1, $2, true) returning id',
        [name, slug]
      );
      return created.rows[0].id;
    } catch (err) {
      if (!String(err.message).toLowerCase().includes('duplicate')) throw err;
      attempt += 1;
      slug = `${baseSlug}-${attempt}`;
    }
  }
}

function readAdditionalInfo(row) {
  const core = { bestForHtml: '', ingredientsHtml: '', howToUseHtml: '', returnPolicyHtml: '', sections: [] };
  for (let i = 1; i <= 6; i++) {
    const title = String(row[`additionalInfoTitle${i}`] || '').trim();
    const desc = String(row[`additionalInfoDescription${i}`] || '').trim();
    if (!title && !desc) continue;
    const normalized = title.toUpperCase();

    if (['BENEFITS', 'BENEFIT'].includes(normalized)) {
      core.bestForHtml = desc;
    } else if (['INGREDIENTS', 'INGREDIENT'].includes(normalized)) {
      core.ingredientsHtml = desc;
    } else if (['INSTRUCTIONS', 'HOW TO USE', 'HOW TO'].includes(normalized)) {
      core.howToUseHtml = desc;
    } else if (normalized.includes('RETURN') || normalized.includes('REFUND')) {
      core.returnPolicyHtml = desc;
      core.sections.push({ title: title || 'Return / Refund Policy', body: desc });
    } else {
      core.sections.push({ title: title || 'Product Details', body: desc });
    }
  }
  return core;
}

function variantName(row) {
  const parts = [];
  for (let i = 1; i <= 6; i++) {
    const desc = String(row[`productOptionDescription${i}`] || '').trim();
    if (desc) parts.push(desc);
  }
  return parts.join(' / ') || String(row.name || '').trim() || 'Default Option';
}

async function importCSV() {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  await ensureSchema(client);

  const fileContent = fs.readFileSync(CSV_FILE, 'utf8');
  const records = parse(fileContent, { columns: true, skip_empty_lines: true });
  const products = records.filter(r => r.fieldType === 'Product');
  const variantsByHandle = new Map();

  records.filter(r => r.fieldType === 'Variant').forEach(row => {
    if (!variantsByHandle.has(row.handleId)) variantsByHandle.set(row.handleId, []);
    variantsByHandle.get(row.handleId).push(row);
  });

  console.log(`Found ${products.length} products and ${records.length - products.length} variant rows in CSV.`);
  let updated = 0, inserted = 0, errors = 0, variantsImported = 0, sectionsImported = 0;

  for (const p of products) {
    const name = String(p.name || '').trim();
    if (!name) continue;

    const info = readAdditionalInfo(p);
    const price = toNumber(p.price, 0);
    const compareAtPrice = p.discountMode && p.discountValue ? null : null;
    const costPrice = toNumber(p.cost, null);
    const stockQuantity = toInt(p.inventory, 0);
    const status = String(p.visible).toLowerCase() === 'true' ? 'active' : 'draft';
    const categoryName = String(p.collection || '').split(';')[0].trim();

    try {
      await client.query('begin');
      const categoryId = await ensureCategory(client, categoryName);
      const existing = await client.query('select id from public.products where name = $1 limit 1', [name]);
      let productId;

      const productValues = [
        name,
        String(p.description || '').trim() || null,
        String(p.sku || '').trim() || null,
        price,
        compareAtPrice,
        costPrice,
        String(p.ribbon || '').trim() || null,
        status,
        categoryId,
        String(p.brand || '').trim() || null,
        String(p.weight || '').trim() || null,
        String(p.discountMode || '').trim() || null,
        toNumber(p.discountValue, null),
        info.ingredientsHtml || null,
        info.bestForHtml || null,
        info.howToUseHtml || null,
        info.returnPolicyHtml || null,
        stockQuantity,
        'wix_csv',
        String(p.handleId || '').trim() || null
      ];

      if (existing.rows.length) {
        productId = existing.rows[0].id;
        await client.query(`
          update public.products
          set name = $1,
              description = $2,
              sku = nullif($3, ''),
              price_jmd = $4,
              compare_at_price_jmd = $5,
              cost_price_jmd = $6,
              badge = $7,
              status = $8,
              category_id = $9,
              brand = $10,
              weight = $11,
              discount_mode = $12,
              discount_value = $13,
              ingredients_html = $14,
              best_for_html = $15,
              how_to_use_html = $16,
              return_policy_html = $17,
              track_inventory = true,
              stock_quantity = $18,
              external_source = $19,
              source_handle_id = $20,
              updated_at = now()
          where id = $21
        `, [...productValues, productId]);
        updated++;
      } else {
        const baseSlug = slugify(name) || `product-${Date.now()}`;
        let slug = baseSlug;
        let attempt = 1;
        while (true) {
          try {
            const created = await client.query(`
              insert into public.products (
                name, slug, description, sku, price_jmd, compare_at_price_jmd, cost_price_jmd,
                badge, status, category_id, brand, weight, discount_mode, discount_value,
                ingredients_html, best_for_html, how_to_use_html, return_policy_html,
                track_inventory, stock_quantity, type, external_source, source_handle_id
              ) values ($1,$2,$3,nullif($4,''),$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,true,$19,'physical',$20,$21)
              returning id
            `, [
              name, slug, String(p.description || '').trim() || null, String(p.sku || '').trim() || null,
              price, compareAtPrice, costPrice, String(p.ribbon || '').trim() || null, status, categoryId,
              String(p.brand || '').trim() || null, String(p.weight || '').trim() || null,
              String(p.discountMode || '').trim() || null, toNumber(p.discountValue, null),
              info.ingredientsHtml || null, info.bestForHtml || null, info.howToUseHtml || null, info.returnPolicyHtml || null,
              stockQuantity, 'wix_csv', String(p.handleId || '').trim() || null
            ]);
            productId = created.rows[0].id;
            inserted++;
            break;
          } catch (err) {
            if (!String(err.message).toLowerCase().includes('duplicate')) throw err;
            attempt += 1;
            slug = `${baseSlug}-${attempt}`;
          }
        }
      }

      const images = imageUrlsFromCsv(p.productImageUrl);
      await client.query('delete from public.product_images where product_id = $1', [productId]);
      for (const [index, imageUrl] of images.entries()) {
        await client.query(
          'insert into public.product_images (product_id, image_url, is_primary, sort_order) values ($1, $2, $3, $4)',
          [productId, imageUrl, index === 0, index]
        );
      }

      await client.query('delete from public.product_info_sections where product_id = $1', [productId]);
      for (const [index, section] of info.sections.entries()) {
        if (!section.title && !section.body) continue;
        await client.query(
          'insert into public.product_info_sections (product_id, title, body, sort_order, is_visible) values ($1, $2, $3, $4, true)',
          [productId, section.title || 'Product Details', section.body || '', index]
        );
        sectionsImported++;
      }

      await client.query('delete from public.product_variants where product_id = $1', [productId]);
      const variantRows = variantsByHandle.get(p.handleId) || [];
      for (const [index, v] of variantRows.entries()) {
        const name = variantName(v);
        await client.query(`
          insert into public.product_variants (product_id, name, sku, price_jmd, stock_quantity, track_inventory, image_url, is_active, sort_order)
          values ($1, $2, nullif($3,''), $4, $5, true, $6, true, $7)
          on conflict (product_id, name) do update set
            sku = excluded.sku,
            price_jmd = excluded.price_jmd,
            stock_quantity = excluded.stock_quantity,
            image_url = excluded.image_url,
            is_active = excluded.is_active,
            sort_order = excluded.sort_order,
            updated_at = now()
        `, [
          productId,
          name,
          String(v.sku || '').trim(),
          toNumber(v.price, price),
          toInt(v.inventory, stockQuantity),
          imageUrlsFromCsv(v.productImageUrl)[0] || null,
          index
        ]);
        variantsImported++;
      }

      await client.query('commit');
      console.log(`SYNCED: ${name} (${variantRows.length} variants, ${info.sections.length} custom sections)`);
    } catch (err) {
      await client.query('rollback');
      console.error(`ERROR on ${name}:`, err.message);
      errors++;
    }
  }

  console.log(`\nDone! Updated: ${updated}, Inserted: ${inserted}, Variants: ${variantsImported}, Sections: ${sectionsImported}, Errors: ${errors}`);
  await client.end();
}

importCSV().catch(err => {
  console.error(err);
  process.exit(1);
});
