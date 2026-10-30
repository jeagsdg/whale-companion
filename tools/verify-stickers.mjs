// Verify the complete sticker export with the real image decoder, without changing it.
import { createRequire } from 'node:module';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.resolve(process.argv[2] || path.join(root, '鲸鱼娘表情包/Codex新版'));
let sharp;
for (const base of [process.env.PET_SHARP_BASE, root, path.resolve(path.dirname(process.execPath), '..'),
  process.env.USERPROFILE && path.join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node')].filter(Boolean)) {
  try { sharp = createRequire(path.join(base, 'image-runtime.cjs'))('sharp'); break; } catch { }
}
if (!sharp) throw new Error('Install sharp locally or set PET_SHARP_BASE.');
const manifest = JSON.parse(readFileSync(path.join(output, 'manifest.json'), 'utf8'));
if (manifest.count !== manifest.stickers.length) throw new Error('Manifest count mismatch.');
const maxBytes = {};
let count = 0;
for (const sticker of manifest.stickers) {
  for (const [folder, pixels] of [['png', 512], ['captioned', 512], ['wechat/png', 240], ['wechat/captioned', 240], ['wechat/gif', 240]]) {
    const file = path.join(output, folder, folder.endsWith('gif') ? sticker.file.replace(/\.png$/, '.gif') : sticker.file);
    const m = await sharp(file, { animated: folder.endsWith('gif') }).metadata();
    if (m.width !== pixels || (m.pageHeight || m.height) !== pixels || !m.hasAlpha) throw new Error('Wrong dimensions or missing alpha: ' + file);
    if (folder.endsWith('gif')) {
      if (m.pages !== 2 || m.delay?.length !== 2 || m.loop !== 0) throw new Error('GIF is not a looping two-frame animation: ' + file);
      const a = await sharp(file, { page: 0 }).raw().toBuffer();
      const b = await sharp(file, { page: 1 }).raw().toBuffer();
      if (a.equals(b)) throw new Error('Identical animation frames: ' + file);
    }
    count++;
    maxBytes[folder] = Math.max(maxBytes[folder] || 0, statSync(file).size);
  }
}
console.log(JSON.stringify({ stickers: manifest.count, verifiedFiles: count, maxBytes }, null, 2));
