const fs = require('fs');
const readline = require('readline');

async function processLineByLine() {
  const fileStream = fs.createReadStream('/Users/Bakers/.gemini/antigravity-ide/brain/0d0d9eda-1610-4c95-b658-4c434e81568a/.system_generated/logs/transcript.jsonl');

  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    try {
      const parsed = JSON.parse(line);
      if (parsed.tool_calls) {
        for (const tc of parsed.tool_calls) {
          if (tc.name === 'replace_file_content' || tc.name === 'multi_replace_file_content') {
             if (tc.args.TargetFile && tc.args.TargetFile.includes('js/products.js')) {
                if (tc.args.TargetContent) {
                  fs.writeFileSync('extracted_products.js', tc.args.TargetContent);
                  console.log('Extracted js/products.js TargetContent');
                }
             }
             if (tc.args.TargetFile && tc.args.TargetFile.includes('js/blog.js')) {
                if (tc.args.TargetContent) {
                  fs.writeFileSync('extracted_blog.js', tc.args.TargetContent);
                  console.log('Extracted js/blog.js TargetContent');
                }
             }
          }
        }
      }
    } catch (e) {}
  }
}

processLineByLine();
