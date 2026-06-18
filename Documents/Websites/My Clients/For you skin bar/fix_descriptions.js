const { createClient } = require('@supabase/supabase-js');
global.WebSocket = require('ws');
const supabase = createClient('https://xftnfbeembjrhezvzquu.supabase.co', process.env.SUPABASE_KEY || 'your-service-role-key-here');

async function fixDescriptions() {
  const { data: products, error } = await supabase.from('products').select('id, name, description');
  if (error) { console.error('Error fetching:', error); return; }
  
  let updatedCount = 0;
  for (const p of products) {
    if (!p.description) continue;
    
    let desc = p.description;
    
    // Split points where the "Benefits" or "Ingredients" usually start in the Wix description
    const splitMarkers = [
      "<p>Why you'll love it",
      "<p><strong>Why you'll love it",
      '<p>Benefits',
      '<p><strong>Benefits',
      '<p>Ingredients',
      '<p><strong>Ingredients',
      '<p>How to use',
      '<p><strong>How to use',
      '<p>HOW TO USE',
      '<p><strong>HOW TO USE',
      '<p>Fragrance Your Way'
    ];
    
    let lowestIndex = desc.length;
    for (const marker of splitMarkers) {
      const idx = desc.indexOf(marker);
      if (idx !== -1 && idx < lowestIndex) {
        lowestIndex = idx;
      }
    }
    
    if (lowestIndex < desc.length) {
      const newDesc = desc.substring(0, lowestIndex).trim();
      console.log(`Updating ${p.name}... cut from ${desc.length} to ${newDesc.length} chars`);
      await supabase.from('products').update({ description: newDesc }).eq('id', p.id);
      updatedCount++;
    }
  }
  console.log(`Fixed ${updatedCount} descriptions.`);
}

fixDescriptions();
