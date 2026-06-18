const fs = require('fs');
const { parse } = require('csv-parse/sync');

const fileContent = fs.readFileSync('catalog_products (5).csv', 'utf8');
const records = parse(fileContent, {
  columns: true,
  skip_empty_lines: true
});

const product = records.find(r => r.fieldType === 'Product');
console.log("Name:", product.name);
for (let i = 1; i <= 6; i++) {
  const title = product[`additionalInfoTitle${i}`];
  const desc = product[`additionalInfoDescription${i}`];
  if (title) {
    console.log(`\n--- ${title} ---`);
    console.log(desc);
  }
}
