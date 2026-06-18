import fs from 'fs';
import path from 'path';
import { createClient } from '@supabase/supabase-js';
import WebSocket from 'ws';

// Configuration
const SUPABASE_URL = process.env.SUPABASE_URL || 'YOUR_SUPABASE_URL';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'YOUR_SUPABASE_SERVICE_ROLE_KEY';

global.WebSocket = WebSocket;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
});

async function migrateProducts() {
    console.log("Starting Products Migration...");
    
    // Read the js/products.original.js file
    const productsPath = path.resolve('./js/products.original.js');
    if (!fs.existsSync(productsPath)) {
        console.error("Products file not found at", productsPath);
        return;
    }
    
    const productsContent = fs.readFileSync(productsPath, 'utf-8');
    
    // Quick and dirty way to parse the window.productsData object from the JS file
    // Assumes the file starts with `window.productsData = [` and ends with `];`
    let jsonStr = productsContent.replace('window.productsData =', '').trim();
    if (jsonStr.endsWith(';')) jsonStr = jsonStr.slice(0, -1);
    
    let productsData;
    try {
        // Using Function constructor to safely evaluate the JS object array into JSON
        productsData = new Function(`return ${jsonStr}`)();
    } catch (e) {
        console.error("Failed to parse products.js data:", e);
        return;
    }
    
    console.log(`Found ${productsData.length} products to migrate.`);
    
    for (const item of productsData) {
        // 1. Upsert Category if it doesn't exist
        const categorySlug = item.category.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        const { data: catData, error: catErr } = await supabase
            .from('categories')
            .upsert({ name: item.category, slug: categorySlug, is_active: true }, { onConflict: 'slug' })
            .select('id')
            .single();
            
        if (catErr) {
            console.error("Error with category:", catErr);
            continue;
        }
        
        // 2. Insert Product
        const slug = item.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        
        // Parse price removing JMD and commas if it's a string, otherwise use the number directly
        const priceClean = typeof item.price === 'number' 
            ? item.price 
            : parseFloat(String(item.price).replace(/[^0-9.-]+/g, ""));
        
        const { data: prodData, error: prodErr } = await supabase
            .from('products')
            .insert({
                old_static_id: item.id,
                category_id: catData.id,
                name: item.name,
                slug: slug,
                short_description: item.description,
                price_jmd: priceClean,
                type: 'physical',
                status: 'active',
                badge: item.badge || null,
                size: item.size || null,
                how_to_use: item.howToUse || null,
                when_to_use: item.whenToUse || null,
                is_featured: !!item.isBestSeller,
                track_inventory: true,
                stock_quantity: 100 // default stock
            })
            .select('id')
            .single();
            
        if (prodErr) {
            console.error(`Error inserting product ${item.name}:`, prodErr);
            continue;
        }
        
        // 3. Download and Upload Image
        if (item.image) {
            try {
                const extension = item.image.split('.').pop()?.split('?')[0] || 'jpg';
                const filename = `${slug}-${Date.now()}.${extension}`;
                let imageUrl = item.image;
                
                if (item.image.startsWith('http')) {
                    const response = await fetch(item.image);
                    if (!response.ok) throw new Error(`Failed to fetch image: ${response.statusText}`);
                    
                    const arrayBuffer = await response.arrayBuffer();
                    const buffer = Buffer.from(arrayBuffer);
                    
                    const { error: uploadErr } = await supabase.storage
                        .from('product-images')
                        .upload(filename, buffer, {
                            contentType: response.headers.get('content-type') || 'image/jpeg',
                            upsert: true
                        });
                        
                    if (uploadErr) throw uploadErr;
                    
                    const { data: { publicUrl } } = supabase.storage.from('product-images').getPublicUrl(filename);
                    imageUrl = publicUrl;
                }
                
                await supabase.from('product_images').insert({
                    product_id: prodData.id,
                    image_url: imageUrl,
                    is_primary: true
                });
            } catch (imgErr) {
                console.error(`Error migrating image for ${item.name}:`, imgErr);
            }
        }
        
        // Note: For tags (skin concerns, ingredients) you would similarly map and insert into product_tags and product_tag_links
        console.log(`Migrated product: ${item.name}`);
    }
    
    console.log("Products Migration Complete.");
}

async function migrateBlog() {
    console.log("Starting Blog Migration...");
    
    // Read the js/blog.original.js file
    const blogPath = path.resolve('./js/blog.original.js');
    if (!fs.existsSync(blogPath)) {
        console.error("Blog file not found at", blogPath);
        return;
    }
    
    const blogContent = fs.readFileSync(blogPath, 'utf-8');
    
    let jsonStr = blogContent.replace('window.blogPosts =', '').trim();
    if (jsonStr.endsWith(';')) jsonStr = jsonStr.slice(0, -1);
    
    let blogData;
    try {
        blogData = new Function(`return ${jsonStr}`)();
    } catch (e) {
        console.error("Failed to parse blog.js data:", e);
        return;
    }
    
    console.log(`Found ${blogData.length} blog posts to migrate.`);
    
    for (const post of blogData) {
        const slug = post.title.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        
        let imageUrl = post.image;
        if (post.image && post.image.startsWith('http')) {
            try {
                const extension = post.image.split('.').pop()?.split('?')[0] || 'jpg';
                const filename = `${slug}-${Date.now()}.${extension}`;
                
                const response = await fetch(post.image);
                if (response.ok) {
                    const arrayBuffer = await response.arrayBuffer();
                    const buffer = Buffer.from(arrayBuffer);
                    
                    const { error: uploadErr } = await supabase.storage
                        .from('blog-images')
                        .upload(filename, buffer, {
                            contentType: response.headers.get('content-type') || 'image/jpeg',
                            upsert: true
                        });
                        
                    if (!uploadErr) {
                        const { data: { publicUrl } } = supabase.storage.from('blog-images').getPublicUrl(filename);
                        imageUrl = publicUrl;
                    }
                }
            } catch (imgErr) {
                console.error(`Error migrating blog image for ${post.title}:`, imgErr);
            }
        }

        const { error: postErr } = await supabase
            .from('blog_posts')
            .insert({
                title: post.title,
                slug: slug,
                excerpt: post.excerpt,
                content: `<p>${post.content}</p>`, // basic wrapper
                featured_image_url: imageUrl,
                status: 'published',
                published_at: new Date(post.date).toISOString()
            });
            
        if (postErr) {
            console.error(`Error inserting post ${post.title}:`, postErr);
            continue;
        }
        console.log(`Migrated post: ${post.title}`);
    }
    
    console.log("Blog Migration Complete.");
}

async function main() {
    await migrateProducts();
    await migrateBlog();
}

main().catch(console.error);
