// Products data will be populated from Supabase
window.productsData = [];

window.loadProductsData = async function() {
    if (window.productsData.length > 0) return window.productsData;

    if (!window.supabase) {
        console.error("Supabase client not loaded.");
        return [];
    }

    try {
        const { data, error } = await window.supabase
            .from('products')
            .select('*, categories(name), product_images(image_url, sort_order, is_primary), product_tags(name, type), product_variants(*), product_info_sections(*)')
            .eq('status', 'active');

        if (error) throw error;

        window.productsData = (data || []).map(p => {
            const tags = p.product_tags || [];
            const images = (p.product_images || [])
                .filter(img => img && img.image_url)
                .sort((a, b) => {
                    if (a.is_primary && !b.is_primary) return -1;
                    if (!a.is_primary && b.is_primary) return 1;
                    return (a.sort_order || 0) - (b.sort_order || 0);
                })
                .map(img => img.image_url);

            const variants = (p.product_variants || [])
                .filter(v => v.is_active !== false)
                .sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0))
                .map(v => ({
                    id: v.id,
                    name: v.name,
                    sku: v.sku || '',
                    price: Number(v.price_jmd || p.price_jmd || 0),
                    compareAtPrice: v.compare_at_price_jmd ? Number(v.compare_at_price_jmd) : null,
                    stock: v.stock_quantity,
                    trackInventory: v.track_inventory !== false,
                    image: v.image_url || ''
                }));

            const infoSections = (p.product_info_sections || [])
                .filter(section => section.is_visible !== false && (section.title || section.body))
                .sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0))
                .map(section => ({
                    title: section.title || 'Product Details',
                    body: section.body || ''
                }));

            return {
                id: p.id,
                name: p.name,
                slug: p.slug,
                sku: p.sku || '',
                brand: p.brand || '',
                price: Number(p.price_jmd || 0),
                compareAtPrice: p.compare_at_price_jmd ? Number(p.compare_at_price_jmd) : null,
                costPrice: p.cost_price_jmd ? Number(p.cost_price_jmd) : null,
                discountMode: p.discount_mode || '',
                discountValue: p.discount_value ? Number(p.discount_value) : null,
                category: (p.categories ? p.categories.name : 'Uncategorized'),
                description: p.description || p.short_description || '',
                shortDescription: p.short_description || '',
                badge: p.badge,
                images,
                image: images.length > 0 ? images[0] : 'https://placehold.co/600x400/F5EDE1/8B5A2B?text=No+Image',
                bestFor: p.best_for || '',
                bestForHtml: p.best_for_html || '',
                ingredientsHtml: p.ingredients_html || '',
                howToUseHtml: p.how_to_use_html || '',
                returnPolicyHtml: p.return_policy_html || '',
                infoSections,
                skinConcern: tags.filter(t => t.type === 'skin_concern').map(t => t.name),
                skinType: tags.filter(t => t.type === 'skin_type').map(t => t.name),
                routineStep: p.routine_step || '',
                ingredients: tags.filter(t => t.type === 'ingredient').map(t => t.name),
                type: p.type,
                howToUse: p.how_to_use || '',
                whenToUse: p.when_to_use || '',
                size: p.size || p.weight || '',
                isFeatured: p.is_featured,
                trackInventory: p.track_inventory !== false,
                stockQuantity: p.stock_quantity,
                allowBackorder: p.allow_backorder,
                relatedProducts: [],
                variants
            };
        });

        return window.productsData;
    } catch (err) {
        console.error("Error fetching products from Supabase:", err);
        alert("Failed to load products: " + err.message);
        return [];
    }
};
