Grace Connect Quote & Scripture Background Catalogue

12 square PNG backgrounds at 1080x1080, based on the current Grace Connect palette.

This folder is the upload record, not an app asset. These files (plus
catalogue_manifest.json) are what was uploaded to the public Supabase
Storage bucket "quote-backgrounds" (see supabase/migrations/
20260821202000_quote_backgrounds_storage_bucket.sql), which is what the
app actually fetches from at runtime (lib/models/quote_background.dart).

To add or replace a background:
1. Drop the PNG here and add/update its entry in catalogue_manifest.json.
2. Upload it: `supabase storage cp -r --experimental supabase/storage_seed/
   quote_backgrounds/<file> ss:///quote-backgrounds/quote_backgrounds/<file>`
3. No app release needed -- the manifest and images are fetched live.

Suggested app flow:
1. User chooses Scripture, Daily Quote, or Custom Text.
2. User chooses a catalogue background.
3. App overlays the text dynamically.
4. User can adjust font, size, alignment, text color, shadow and reference.
5. Export/share the flattened card.

Use the recommended text color and safe-area hints in catalogue_manifest.json.
