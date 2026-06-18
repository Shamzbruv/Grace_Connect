// no dotenv required, relying on node --env-file or fallback
const fs = require('fs');
const { Client } = require('pg');

async function runMigration() {
  const connectionString = process.env.SUPABASE_DB_URL || 'postgresql://postgres.xftnfbeembjrhezvzquu:IloveJesus%40101@aws-1-us-west-2.pooler.supabase.com:6543/postgres';
  
  console.log("Connecting to the database...");
  const client = new Client({ connectionString });
  
  try {
    await client.connect();
    console.log("Connected successfully.");
    
    const migrationSql = fs.readFileSync('supabase/migrations/20260612000006_product_catalog_extensions.sql', 'utf8');
    
    console.log("Running migration...");
    await client.query(migrationSql);
    console.log("Migration executed successfully!");
    
  } catch (error) {
    console.error("Error executing migration:", error);
  } finally {
    await client.end();
  }
}

runMigration();
