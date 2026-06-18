const { Client } = require('pg');

async function run() {
  const connectionString = process.env.SUPABASE_DB_URL;
  if (!connectionString) {
    console.error("Missing SUPABASE_DB_URL environment variable.");
    process.exit(1);
  }
  
  const client = new Client({ 
    connectionString,
    ssl: { rejectUnauthorized: false }
  });
  
  await client.connect();
  console.log("Connected successfully to DB.");

  const mappings = {
    "dark-spots": [
      "kojie fade",
      "truglow sugar scrub",
      "clear era vanishing",
      "skin balance",
      "protect", // Protect and Glow
      "niaskin boost"
    ],
    "acne": [
      "neem turmeric",
      "clear skin serum",
      "skinfidence blemish",
      "neem calm and clear mist",
      "neem calm and clear sugar scrub"
    ],
    "body-care": [
      "body butters",
      "body mists",
      "body oils",
      "soaps",
      "scrubs"
    ],
    "dryness": [
      "glow therapy soap",
      "calm theory soap",
      "plump n glow", // Plump N Glow Elixir
      "rose radiance toner",
      "niaskin boost"
    ],
    "glow": [
      // Includes dark-spots + dryness
      "kojie fade",
      "truglow sugar scrub",
      "clear era vanishing",
      "skin balance",
      "protect",
      "niaskin boost",
      "glow therapy soap",
      "calm theory soap",
      "plump n glow",
      "rose radiance toner"
    ],
    "texture": [
      "scrubs",
      "clear skin serum",
      "niaskin boost",
      "skinfidence blemish"
    ]
  };

  const { rows: products } = await client.query('SELECT id, name FROM public.products');
  console.log(`Fetched ${products.length} products from DB.`);

  const inserts = [];

  const findProducts = (query) => {
    return products.filter(p => {
      const pName = p.name.toLowerCase();
      const q = query.toLowerCase();
      
      // Categories matching
      if (q === "body butters") return pName.includes("butter");
      if (q === "body mists") return pName.includes("mist");
      if (q === "body oils") return pName.includes("oil");
      if (q === "soaps") return pName.includes("soap") || pName.includes("bar");
      if (q === "scrubs") return pName.includes("scrub") || pName.includes("exfoliation glove");

      // Specific string matching
      if (q === "protect") return pName.includes("protect");
      if (q === "skin balance") return pName.includes("skin balance");
      if (q === "kojie fade") return pName.includes("kojie fade");
      if (q === "neem calm and clear mist") return pName.includes("neem") && pName.includes("mist");
      if (q === "plump n glow") return pName.includes("plump");
      
      return pName.includes(q);
    });
  };

  for (const [concernSlug, queries] of Object.entries(mappings)) {
    for (const q of queries) {
      const matched = findProducts(q);
      for (const m of matched) {
        inserts.push({
          product_id: m.id,
          concern_slug: concernSlug
        });
      }
    }
  }

  const uniqueInserts = [];
  const seen = new Set();
  for (const ins of inserts) {
    const key = `${ins.product_id}_${ins.concern_slug}`;
    if (!seen.has(key)) {
      seen.add(key);
      uniqueInserts.push(ins);
    }
  }

  console.log(`Found ${uniqueInserts.length} concern mappings to insert.`);

  await client.query('DELETE FROM public.product_concerns');
  console.log('Cleared existing product concerns.');

  if (uniqueInserts.length > 0) {
    const values = uniqueInserts.map(i => `('${i.product_id}', '${i.concern_slug}')`).join(',');
    await client.query(`INSERT INTO public.product_concerns (product_id, concern_slug) VALUES ${values}`);
    console.log("Successfully inserted product concerns.");
  }

  await client.end();
}

run().catch(console.error);
