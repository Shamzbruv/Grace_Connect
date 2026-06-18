import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'YOUR_SUPABASE_URL';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'YOUR_SUPABASE_SERVICE_ROLE_KEY';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const productsData = [
  {
    name: "Radiance Vitamin C Serum",
    category: "Face Care",
    price: 4500,
    description: "Brighten and revitalize your skin with our potent Vitamin C serum. Formulated to reduce dark spots and give you a natural glow.",
    badge: "Best Seller",
    size: "30ml",
    howToUse: "Apply 2-3 drops to clean, dry skin every morning.",
    isBestSeller: true,
    image: "https://images.unsplash.com/photo-1620916566398-39f1143ab7be?auto=format&fit=crop&w=600&q=80"
  },
  {
    name: "Hydrating Rose Water Toner",
    category: "Face Care",
    price: 2500,
    description: "A soothing and refreshing toner that restores skin pH balance and minimizes pores while providing instant hydration.",
    badge: null,
    size: "150ml",
    howToUse: "Mist directly onto face or apply with a cotton pad after cleansing.",
    isBestSeller: false,
    image: "https://images.unsplash.com/photo-1608248593802-8081547f3b14?auto=format&fit=crop&w=600&q=80"
  },
  {
    name: "Whipped Shea Body Butter",
    category: "Body Care",
    price: 3800,
    description: "Deeply nourish your skin with this luxurious, thick body butter. Perfect for dry skin, leaving it soft and glowing all day.",
    badge: "New",
    size: "250g",
    howToUse: "Massage generously into skin, especially after a shower.",
    isBestSeller: true,
    image: "https://images.unsplash.com/photo-1614859324967-bdf29770513e?auto=format&fit=crop&w=600&q=80"
  },
  {
    name: "Turmeric & Honey Face Mask",
    category: "Face Care",
    price: 3200,
    description: "Draw out impurities and brighten dull skin with this healing clay mask. Helps combat acne and hyperpigmentation.",
    badge: null,
    size: "100g",
    howToUse: "Apply an even layer. Leave for 10-15 minutes, then rinse.",
    isBestSeller: false,
    image: "https://images.unsplash.com/photo-1596755389378-c31d21fd1273?auto=format&fit=crop&w=600&q=80"
  },
  {
    name: "Exfoliating Coffee Scrub",
    category: "Body Care",
    price: 2800,
    description: "Buff away dead skin cells and stimulate blood flow with our organic coffee scrub. Leaves skin incredibly smooth.",
    badge: null,
    size: "200g",
    howToUse: "Use in shower 2-3 times a week in circular motions.",
    isBestSeller: false,
    image: "https://images.unsplash.com/photo-1615397323869-d41ee04aab8c?auto=format&fit=crop&w=600&q=80"
  },
  {
    name: "Nourishing Lip Oil",
    category: "Face Care",
    price: 1800,
    description: "A non-sticky, hydrating lip oil that provides a beautiful glossy finish while deeply moisturizing your lips.",
    badge: "Trending",
    size: "10ml",
    howToUse: "Apply to lips as needed throughout the day.",
    isBestSeller: true,
    image: "https://images.unsplash.com/photo-1599305090598-fe179d501227?auto=format&fit=crop&w=600&q=80"
  }
];

const blogPosts = [
  {
    title: "5 Steps to Glowing Skin",
    excerpt: "Discover the essential routine that will transform your skin from dull to radiant in just two weeks.",
    content: "Having glowing skin is about consistency and the right ingredients. Start with a gentle cleanser, never skip your vitamin C serum in the morning, and always moisturize. Exfoliating twice a week helps remove dead skin cells. Drink plenty of water and wear sunscreen daily!",
    category: "Skincare Routine",
    image: "https://images.unsplash.com/photo-1616683693504-3ea7e9ad6fec?auto=format&fit=crop&w=800&q=80",
    author: "For You Team",
    published_at: new Date().toISOString()
  },
  {
    title: "The Magic of Shea Butter",
    excerpt: "Why this natural ingredient is the ultimate savior for dry skin and how to use it effectively.",
    content: "Shea butter is packed with vitamins A and E, making it incredibly healing and moisturizing. It forms a protective barrier on your skin to lock in moisture. When whipped, it becomes the perfect texture for daily application. Make sure to apply it right after a shower when your pores are open.",
    category: "Ingredients",
    image: "https://images.unsplash.com/photo-1608248543803-ba4f8c70ae0b?auto=format&fit=crop&w=800&q=80",
    author: "For You Team",
    published_at: new Date(Date.now() - 86400000).toISOString()
  },
  {
    title: "Understanding Your Skin Type",
    excerpt: "Take the guesswork out of your routine by finally understanding what your skin actually needs.",
    content: "Is your skin dry, oily, combination, or sensitive? Wash your face, wait 30 minutes, and observe. If it's tight, it's dry. If it's shiny all over, it's oily. If only your T-zone is shiny, it's combination. Knowing this helps you pick the right products and avoid unnecessary irritation.",
    category: "Guides",
    image: "https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=800&q=80",
    author: "For You Team",
    published_at: new Date(Date.now() - 172800000).toISOString()
  }
];

async function seedData() {
    console.log("Seeding Database...");
    
    // Seed Products
    for (const item of productsData) {
        const categorySlug = item.category.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        const { data: catData, error: catErr } = await supabase
            .from('categories')
            .upsert({ name: item.category, slug: categorySlug, is_active: true }, { onConflict: 'slug' })
            .select('id')
            .single();
            
        if (catErr) { console.error(catErr); continue; }
        
        const slug = item.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        
        const { data: prodData, error: prodErr } = await supabase
            .from('products')
            .insert({
                category_id: catData.id,
                name: item.name,
                slug: slug,
                short_description: item.description,
                price_jmd: item.price,
                type: 'physical',
                status: 'active',
                badge: item.badge,
                size: item.size,
                how_to_use: item.howToUse,
                is_featured: item.isBestSeller,
                track_inventory: true,
                stock_quantity: 50
            })
            .select('id')
            .single();
            
        if (prodErr) { console.error(prodErr); continue; }
        
        await supabase.from('product_images').insert({
            product_id: prodData.id,
            image_url: item.image,
            is_primary: true
        });
        
        console.log(`Added product: ${item.name}`);
    }

    // Seed Blog
    for (const post of blogPosts) {
        const slug = post.title.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        const { error } = await supabase.from('blog_posts').insert({
            title: post.title,
            slug: slug,
            excerpt: post.excerpt,
            content: post.content,
            featured_image: post.image,
            category: post.category,
            author_name: post.author,
            published_at: post.published_at,
            status: 'published'
        });
        if (error) { console.error(error); continue; }
        console.log(`Added blog post: ${post.title}`);
    }
    
    console.log("Seeding complete!");
}

seedData();
