/**
 * 🔍 验证翻译键是否匹配上游源码
 * 
 * 用法: node scripts/validate-translations.mjs --upstream <上游目录>
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const TRANSLATIONS_DIR = path.join(ROOT, 'translations');

const args = process.argv.slice(2);
const upstreamIdx = args.indexOf('--upstream');
if (upstreamIdx === -1 || !args[upstreamIdx + 1]) {
  console.error('用法: node scripts/validate-translations.mjs --upstream <上游目录>');
  process.exit(1);
}
const UPSTREAM = args[upstreamIdx + 1];

// 加载 config.json
const configRaw = await fs.readFile(path.join(TRANSLATIONS_DIR, 'config.json'), 'utf-8');
const config = JSON.parse(configRaw);

let totalFiles = 0;
let totalEntries = 0;
let totalMatch = 0;
let totalStale = 0;

const staleReport = [];

for (const [category, files] of Object.entries(config.modules)) {
  for (const file of files) {
    const filePath = path.join(TRANSLATIONS_DIR, file);
    let json;
    try {
      json = JSON.parse(await fs.readFile(filePath, 'utf-8'));
    } catch {
      console.error(`⚠️ 无法读取: ${file}`);
      continue;
    }

    const sourceFile = path.join(UPSTREAM, json.file);
    let sourceContent;
    try {
      sourceContent = await fs.readFile(sourceFile, 'utf-8');
    } catch {
      console.error(`⚠️ 上游文件不存在: ${json.file}`);
      continue;
    }

    totalFiles++;
    const entries = Object.entries(json.replacements || {});
    const fileStale = [];
    let fileMatch = 0;

    for (const [key, value] of entries) {
      // 跳过注释键
      if (key.startsWith('__comment')) continue;
      
      totalEntries++;
      if (sourceContent.includes(key)) {
        fileMatch++;
        totalMatch++;
      } else {
        fileStale.push(key.length > 80 ? key.slice(0, 77) + '...' : key);
        totalStale++;
      }
    }

    const icon = fileStale.length === 0 ? '✅' : '⚠️';
    console.log(`${icon} ${file}: ${fileMatch}/${fileMatch + fileStale.length} 匹配${fileStale.length > 0 ? `, ${fileStale.length} 失效` : ''}`);

    if (fileStale.length > 0) {
      staleReport.push({ file, stale: fileStale, sourceFile: json.file });
      for (const s of fileStale.slice(0, 5)) {
        console.log(`   ❌ ${s}`);
      }
      if (fileStale.length > 5) {
        console.log(`   ... 还有 ${fileStale.length - 5} 条`);
      }
    }
  }
}

console.log('\n' + '═'.repeat(60));
console.log(`📊 验证结果: ${totalFiles} 个文件, ${totalEntries} 条翻译`);
console.log(`   ✅ 匹配: ${totalMatch} | ❌ 失效: ${totalStale}`);
console.log(`   匹配率: ${((totalMatch / totalEntries) * 100).toFixed(1)}%`);
console.log('═'.repeat(60));

if (staleReport.length > 0) {
  console.log('\n📋 失效条目详情:');
  for (const r of staleReport) {
    console.log(`\n📁 ${r.file} (→ ${r.sourceFile})`);
    for (const s of r.stale) {
      console.log(`   ❌ ${s}`);
    }
  }
}
