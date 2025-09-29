// !/usr/bin/env tsx

import { bundle } from './lua-bundler.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('Bundling Lua...');

  // Bundle the main Lua file
  const bundledLua = bundle(path.join(__dirname, '../src/process.lua'));

  // Ensure the dist directory exists
  const distPath = path.join(__dirname, '../dist');
  if (!fs.existsSync(distPath)) {
    fs.mkdirSync(distPath);
  }

  // Write the concatenated content to the output file
  fs.writeFileSync(path.join(distPath, 'aos-bundled.lua'), bundledLua);
  console.log('Doth Lua hath been bundled!');
}

main();
