const fs = require('fs');
const path = 'u:/testing_ai/队伍编成/index.html';
const html = fs.readFileSync(path, 'utf8');

// 1. extract <script> block
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.error('NO SCRIPT BLOCK'); process.exit(1); }
const code = m[1];

// 2. syntax check
try {
  new Function(code);
  console.log('SYNTAX OK');
} catch (e) {
  console.error('SYNTAX ERROR:', e.message);
  process.exit(1);
}

// 3. collect id="..." attributes
const idSet = new Set();
const idRe = /\sid\s*=\s*"([^"]+)"/g;
let mm;
while ((mm = idRe.exec(html)) !== null) idSet.add(mm[1]);
console.log('IDs found:', [...idSet].length);

// 4. collect $("id") references in JS
const refSet = new Set();
const refRe = /\$\("([a-zA-Z0-9_-]+)"\)/g;
let rr;
while ((rr = refRe.exec(code)) !== null) refSet.add(rr[1]);
console.log('$() refs:', [...refSet]);

// 5. check each ref exists
let bad = 0;
for (const r of refSet) {
  if (!idSet.has(r)) { console.error('MISSING ID for $(' + r + ')'); bad++; }
}
if (bad === 0) console.log('ALL $() REFS RESOLVED');
else process.exit(2);
