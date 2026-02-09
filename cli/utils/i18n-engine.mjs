/**
 * 🌐 翻译引擎
 * 
 * 加载翻译配置并应用到目标文件
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { log, colors } from './logger.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, '../..');
const TRANSLATIONS_DIR = path.join(ROOT_DIR, 'translations');

/**
 * 加载主配置文件
 */
export async function loadMainConfig() {
  const configPath = path.join(TRANSLATIONS_DIR, 'config.json');
  const content = await fs.readFile(configPath, 'utf-8');
  return JSON.parse(content);
}

/**
 * 加载所有翻译配置
 */
export async function loadAllTranslations(mainConfig, verbose = false) {
  const translations = [];
  
  for (const [category, files] of Object.entries(mainConfig.modules)) {
    for (const file of files) {
      const filePath = path.join(TRANSLATIONS_DIR, file);
      try {
        const content = await fs.readFile(filePath, 'utf-8');
        const config = JSON.parse(content);
        translations.push({
          ...config,
          category,
          configFile: file
        });
        if (verbose) {
          log.dim(`已加载: ${file}`);
        }
      } catch (err) {
        log.warn(`无法加载 ${file}: ${err.message}`);
      }
    }
  }
  
  return translations;
}

/**
 * 应用翻译到目标文件
 */
export async function applyTranslation(translation, targetDir, options = {}) {
  const { dryRun = false, verify = false, verbose = false } = options;
  
  const targetPath = path.join(targetDir, translation.file);
  const stats = {
    file: translation.file,
    description: translation.description,
    total: Object.keys(translation.replacements).filter(k => !k.startsWith('__comment')).length,
    applied: 0,
    skipped: 0,
    notFound: 0
  };
  
  let content;
  try {
    content = await fs.readFile(targetPath, 'utf-8');
  } catch {
    log.error(`文件不存在: ${translation.file}`);
    stats.notFound = stats.total;
    return stats;
  }
  
  let modified = content;
  
  for (const [original, translated] of Object.entries(translation.replacements)) {
    // 跳过注释键（如 __comment_page_header）
    if (original.startsWith('__comment')) continue;

    if (modified.includes(translated)) {
      // 已经翻译过了
      stats.skipped++;
      if (verbose) log.dim(`已存在: ${original.slice(0, 50)}...`);
    } else if (modified.includes(original)) {
      // 应用翻译 - 全局替换所有匹配项
      modified = modified.replaceAll(original, translated);
      stats.applied++;
      if (verbose) {
        log.dim(`替换: ${original.slice(0, 35)}... → ${translated.slice(0, 35)}...`);
      }
    } else {
      // 找不到原文
      stats.notFound++;
      if (verbose) {
        log.warn(`未找到: ${original.slice(0, 60)}...`);
      }
    }
  }
  
  // 写入文件
  if (!dryRun && !verify && stats.applied > 0) {
    await fs.writeFile(targetPath, modified, 'utf-8');
  }
  
  return stats;
}

/**
 * 打印统计报告
 */
export function printStats(allStats, options = {}) {
  const { dryRun = false, verify = false } = options;
  
  console.log('\n' + '═'.repeat(60));
  log.title('📊 汉化统计报告');
  console.log('═'.repeat(60));
  
  let totalApplied = 0;
  let totalSkipped = 0;
  let totalNotFound = 0;
  
  for (const stats of allStats) {
    const icon = stats.notFound > 0 ? '⚠️' : stats.applied > 0 ? '✅' : '➖';
    console.log(`\n${icon} ${colors.bold}${stats.file}${colors.reset}`);
    console.log(`   ${colors.dim}${stats.description}${colors.reset}`);
    
    const appliedStr = `${colors.green}${stats.applied}${colors.reset}`;
    const notFoundStr = stats.notFound > 0 
      ? `${colors.yellow}${stats.notFound}${colors.reset}` 
      : stats.notFound;
    
    console.log(`   应用: ${appliedStr} | 已存在: ${stats.skipped} | 未找到: ${notFoundStr}`);
    
    totalApplied += stats.applied;
    totalSkipped += stats.skipped;
    totalNotFound += stats.notFound;
  }
  
  console.log('\n' + '─'.repeat(60));
  
  const totalAppliedStr = `${colors.green}${totalApplied}${colors.reset}`;
  const totalNotFoundStr = totalNotFound > 0 
    ? `${colors.yellow}${totalNotFound}${colors.reset}` 
    : totalNotFound;
  
  console.log(`总计: 应用 ${totalAppliedStr} | 已存在 ${totalSkipped} | 未找到 ${totalNotFoundStr}`);
  
  // 机器可读的统计行，用于 CI/CD 提取（不含 ANSI 颜色码）
  console.log(`##STATS##applied=${totalApplied}|existed=${totalSkipped}|failed=${totalNotFound}##`);
  
  if (dryRun) {
    log.warn('\n🔍 预览模式 - 未实际修改任何文件');
  } else if (verify) {
    log.warn('\n🔍 验证模式 - 未实际修改任何文件');
  } else if (totalApplied > 0) {
    log.success('\n✅ 汉化已成功应用！');
  } else if (totalSkipped > 0) {
    log.info('\n➖ 汉化已是最新，无需更新');
  }
  
  return { totalApplied, totalSkipped, totalNotFound };
}

export { ROOT_DIR, TRANSLATIONS_DIR };
