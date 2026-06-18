# Product Catalog Admin Update Notes

This ZIP has been updated so the admin Products section can manage the missing catalog details from the CSV and display them neatly on the storefront.

## What was added

- Admin product form now supports:
  - Category
  - SKU
  - Brand
  - Size / weight
  - Badge / ribbon
  - Compare-at price
  - Cost price
  - Product-level discount mode/value
  - Inventory quantity, low-stock threshold, and backorder setting
  - Short description and full description
  - Benefits
  - Ingredients
  - How To Use / Instructions
  - Return / refund policy
  - Custom product page sections
  - Multiple image URLs + uploaded image
  - Product variants/options with name, price, SKU, stock, image URL, and active toggle

- Product page now displays:
  - Multiple image gallery
  - Variant selector from Supabase
  - Variant price updates
  - SKU, brand, size, and availability
  - Benefits, ingredients, how-to-use, return/refund policy
  - Custom product sections from Supabase

- Shop page now uses real Supabase variants instead of fake Standard/Large options.

- Inventory page was corrected to use the actual Supabase product fields and product images.

## Supabase migration required

Run this new migration before using the updated admin form:

```sql
supabase/migrations/20260612000006_product_catalog_extensions.sql
```

Without this migration, the admin page will show an error because the new variant and custom-section tables will not exist yet.

## CSV importer update

`import_wix_csv.js` was updated to import:

- Core product fields
- SKU
- Brand
- Weight
- Product discounts
- Inventory
- Images
- Benefits / Ingredients / Instructions
- Return/refund details
- Custom product sections
- Variant rows

Run it with an environment variable instead of hardcoding database credentials:

```bash
SUPABASE_DB_URL="your-postgres-connection-string" node import_wix_csv.js
```

## Important security note

The previous hardcoded database password was removed from the importer. Do not place Supabase database passwords directly in project files that may be shared or uploaded.
