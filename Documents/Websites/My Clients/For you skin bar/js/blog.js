// Blog posts will be populated from Supabase
window.blogPosts = [];

window.loadBlogPosts = async function() {
    if (window.blogPosts.length > 0) return window.blogPosts;
    
    if (!window.supabase) {
        console.error("Supabase client not loaded.");
        return [];
    }

    try {
        const { data, error } = await window.supabase
            .from('blog_posts')
            .select('*')
            .eq('status', 'published')
            .order('published_at', { ascending: false });
            
        if (error) throw error;
        
        window.blogPosts = data.map(post => ({
            id: post.id,
            title: post.title,
            slug: post.slug,
            excerpt: post.excerpt || '',
            content: post.content || '',
            image: post.featured_image_url || 'https://placehold.co/600x400/F5EDE1/8B5A2B?text=No+Image',
            date: new Date(post.published_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }),
            category: 'Skincare'
        }));
        
        return window.blogPosts;
    } catch (err) {
        console.error("Error fetching blog posts from Supabase:", err);
        return [];
    }
};