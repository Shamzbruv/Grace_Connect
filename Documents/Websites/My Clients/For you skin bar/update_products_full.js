const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');
global.WebSocket = require('ws');

const SUPABASE_URL = 'https://xftnfbeembjrhezvzquu.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_KEY || 'your-service-role-key-here'; // Service role key to bypass RLS for migration
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function migrateFullData() {
    // 1. Read original products
    const originalContent = fs.readFileSync('./js/products.original.js', 'utf-8');
    // Extract the JSON part
    const jsonMatch = originalContent.match(/window\.productsData\s*=\s*(\[.*\]);/s);
    if (!jsonMatch) {
        console.error("Could not find products array in products.original.js");
        return;
    }
    
    let originalProducts;
    try {
        originalProducts = JSON.parse(jsonMatch[1]);
    } catch (e) {
        console.error("Could not parse JSON", e);
        return;
    }

    console.log(`Loaded ${originalProducts.length} original products.`);

    for (const op of originalProducts) {
        // Find by name
        const { data: dbProducts, error: findError } = await supabase
            .from('products')
            .select('id')
            .eq('name', op.name);

        if (findError) {
            console.error("Error finding", op.name, findError);
            continue;
        }

        if (dbProducts && dbProducts.length > 0) {
            const dbId = dbProducts[0].id;
            // Update the product with full details
            const updateData = {
                description: op.description || '',
                best_for: op.bestFor || '',
                how_to_use: op.howToUse || '',
                when_to_use: op.whenToUse || '',
                size: op.size || '',
                routine_step: op.routineStep || ''
            };

            const { error: updateError } = await supabase
                .from('products')
                .update(updateData)
                .eq('id', dbId);

            if (updateError) {
                console.error("Error updating", op.name, updateError);
            } else {
                console.log("Updated", op.name);
            }

            // Let's also create tags for ingredients, skin_concern, skin_type
            // We'll insert tags safely (ignore duplicates) and link them
            async function addTags(tagArray, type) {
                if (!tagArray) return;
                for (let tagName of tagArray) {
                    if (!tagName.trim()) continue;
                    let slug = tagName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
                    
                    // Upsert tag
                    const { data: tagData, error: tagError } = await supabase
                        .from('product_tags')
                        .upsert({ name: tagName, slug: slug, type: type }, { onConflict: 'slug' })
                        .select('id');
                    
                    let tagId = null;
                    if (tagError) {
                        // If upsert failed (maybe due to constraint), try select
                        const { data: existingTag } = await supabase.from('product_tags').select('id').eq('slug', slug).single();
                        if (existingTag) tagId = existingTag.id;
                    } else if (tagData && tagData.length > 0) {
                        tagId = tagData[0].id;
                    }

                    if (tagId) {
                        await supabase.from('product_tag_links').upsert({
                            product_id: dbId,
                            tag_id: tagId
                        }, { onConflict: 'product_id,tag_id' });
                    }
                }
            }

            await addTags(op.ingredients, 'ingredient');
            await addTags(op.skinConcern, 'skin_concern');
            await addTags(op.skinType, 'skin_type');

        } else {
            console.warn("Product not found in DB:", op.name);
        }
    }

    console.log("Migration complete!");
}

migrateFullData().catch(console.error);
