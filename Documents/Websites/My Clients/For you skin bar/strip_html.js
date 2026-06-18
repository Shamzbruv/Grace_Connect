const { createClient } = require('@supabase/supabase-js');
global.WebSocket = require('ws');
const supabase = createClient('https://xftnfbeembjrhezvzquu.supabase.co', process.env.SUPABASE_KEY || 'your-service-role-key-here');

function htmlToText(html) {
    if (!html) return html;
    
    let text = html;
    
    // Convert common block elements to newlines
    text = text.replace(/<p[^>]*>/gi, '\n');
    text = text.replace(/<\/p>/gi, '\n');
    text = text.replace(/<br\s*\/?>/gi, '\n');
    
    // Convert lists
    text = text.replace(/<li[^>]*>/gi, '\n• ');
    text = text.replace(/<\/li>/gi, '');
    text = text.replace(/<ul[^>]*>/gi, '\n');
    text = text.replace(/<\/ul>/gi, '\n');
    
    // Decode HTML entities
    text = text.replace(/&nbsp;/g, ' ');
    text = text.replace(/&amp;/g, '&');
    text = text.replace(/&lt;/g, '<');
    text = text.replace(/&gt;/g, '>');
    text = text.replace(/&quot;/g, '"');
    text = text.replace(/&#39;/g, "'");
    
    // Strip all remaining HTML tags
    text = text.replace(/<[^>]+>/g, '');
    
    // Clean up whitespace: convert 3+ newlines to 2 newlines
    text = text.replace(/\n{3,}/g, '\n\n');
    
    // Trim
    return text.trim();
}

async function stripAllHtml() {
    console.log("Fetching products...");
    const { data: products, error } = await supabase.from('products').select('id, description, best_for_html, ingredients_html, how_to_use_html');
    if (error) { console.error('Error fetching:', error); return; }
    
    let count = 0;
    
    for (const p of products) {
        const updates = {};
        let needsUpdate = false;
        
        if (p.description && p.description.includes('<')) {
            updates.description = htmlToText(p.description);
            needsUpdate = true;
        }
        if (p.best_for_html && p.best_for_html.includes('<')) {
            updates.best_for_html = htmlToText(p.best_for_html);
            needsUpdate = true;
        }
        if (p.ingredients_html && p.ingredients_html.includes('<')) {
            updates.ingredients_html = htmlToText(p.ingredients_html);
            needsUpdate = true;
        }
        if (p.how_to_use_html && p.how_to_use_html.includes('<')) {
            updates.how_to_use_html = htmlToText(p.how_to_use_html);
            needsUpdate = true;
        }
        
        // Also check for &nbsp;
        if (!needsUpdate) {
             if (p.description && p.description.includes('&nbsp;')) { updates.description = htmlToText(p.description); needsUpdate = true; }
             if (p.best_for_html && p.best_for_html.includes('&nbsp;')) { updates.best_for_html = htmlToText(p.best_for_html); needsUpdate = true; }
             if (p.ingredients_html && p.ingredients_html.includes('&nbsp;')) { updates.ingredients_html = htmlToText(p.ingredients_html); needsUpdate = true; }
             if (p.how_to_use_html && p.how_to_use_html.includes('&nbsp;')) { updates.how_to_use_html = htmlToText(p.how_to_use_html); needsUpdate = true; }
        }

        if (needsUpdate) {
            await supabase.from('products').update(updates).eq('id', p.id);
            count++;
        }
    }
    
    console.log(`Successfully converted HTML to plain text for ${count} products.`);
}

stripAllHtml();
