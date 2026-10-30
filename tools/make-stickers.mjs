// 重新生成中英双字幕表情包（240 微信三套 + 512 大图两套）。文案表：tools/sticker-captions.json
// Usage: node tools/make-stickers.mjs [--limit 3] [--output path]
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const args = process.argv.slice(2);
const argument = (key) => { const at = args.indexOf(key); return at >= 0 ? args[at + 1] : undefined; };
const GEN = argument('--input') || process.env.PET_STICKER_INPUT || process.env.DSH_STICKER_INPUT || path.join(ROOT, 'packages/dsh-whale-notify/assets/generated');
const OUT = argument('--output') || process.env.PET_STICKER_OUTPUT || process.env.DSH_STICKER_OUTPUT || path.join(ROOT, '鲸鱼娘表情包');
const limit = Number(argument('--limit') || 0);
if (!Number.isInteger(limit) || limit < 0) throw new Error('--limit must be a nonnegative integer');
// Local npm installation, an explicit dependency base, and the bundled Codex runtime all work.
const BASES = [process.env.PET_SHARP_BASE, process.env.DSH_SHARP_BASE, process.env.CODEX_NODE_MODULES,
  ROOT, process.cwd(), path.resolve(path.dirname(process.execPath), '..'),
  process.env.USERPROFILE && path.join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node')].filter(Boolean);
let sharp = null;
for (const base of BASES) { try { sharp = createRequire(path.join(base, 'noop.js'))('sharp'); break; } catch (e) {} }
if (!sharp) { console.error('sharp not found. Install sharp locally or set PET_SHARP_BASE to a directory containing node_modules/sharp.'); process.exit(1); }

const CAP = JSON.parse(readFileSync(process.env.PET_STICKER_CAPTIONS || process.env.DSH_STICKER_CAPTIONS || path.join(HERE, 'sticker-captions.json'), 'utf8').replace(/^\uFEFF/, ''));
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const wrap = (t, max) => { if (t.length <= max) return [t]; const w = t.split(' '); const L = []; let c = ''; for (const x of w) { if ((c + ' ' + x).trim().length <= max) c = (c + ' ' + x).trim(); else { if (c) L.push(c); c = x; } } if (c) L.push(c); return L.slice(0, 2); };
const empty = (w, h) => ({ create: { width: w, height: h, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } });
const grad = (id) => '<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#0b2440"/><stop offset="100%" stop-color="#061423"/></linearGradient></defs>';

for (const d of ['png', 'captioned', 'wechat/png', 'wechat/captioned', 'wechat/gif']) mkdirSync(path.join(OUT, d), { recursive: true });
const candidates = readdirSync(GEN).filter((f) => f.endsWith('.webp')).sort();
const files = limit ? candidates.slice(0, limit) : candidates;
const manifest = [];
let i = 0;
for (const f of files) {
  const pose = f.replace(/^dsh-whale-(?:state-)?/, '').replace(/\.webp$/, '');
  const pair = CAP[pose] || [pose, pose];
  // Existing caption tables are [Chinese, English]; named fields are accepted too.
  const title = String((Array.isArray(pair) ? pair[0] : pair.cn ?? pair.title) || pose);
  const caption = String((Array.isArray(pair) ? pair[1] : pair.en ?? pair.caption) || title);
  i += 1;
  const name = String(i).padStart(2, '0') + '-' + (slug(pose) || String(i)) + '.png';
  const src = path.join(GEN, f);
  // 512 clean
  await sharp(src).resize(492, 492, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .extend({ top: 10, bottom: 10, left: 10, right: 10, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 }).toFile(path.join(OUT, 'png', name));
  // 512 captioned：art on top, caption band below (never over the art)
  const art512 = await sharp(src).resize(472, 372, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer();
  const l512 = wrap(caption, 22);
  const t512 = '<text x="256" y="438" text-anchor="middle" font-family="Microsoft YaHei, Segoe UI, sans-serif" font-size="26" font-weight="700" fill="#ffffff">' + esc(title) + '</text>' + l512.map((l, k) => '<text x="256" y="' + (467 + k * 23) + '" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="22" font-weight="700" fill="#ffffff">' + esc(l) + '</text>').join('');
  const svg512 = '<svg width="512" height="512" xmlns="http://www.w3.org/2000/svg">' + grad('g') +
    '<ellipse cx="256" cy="404" rx="140" ry="20" fill="#000" opacity="0.18"/>' +
    '<rect x="22" y="404" width="468" height="98" rx="28" fill="url(#g)" stroke="#38bdf8" stroke-width="2.5"/>' + t512 + '</svg>';
  await sharp(empty(512, 512)).composite([{ input: art512, top: 6, left: 20 }, { input: Buffer.from(svg512), top: 0, left: 0 }]).png({ compressionLevel: 9 }).toFile(path.join(OUT, 'captioned', name));
  // 240 WeChat clean
  await sharp(src).resize(228, 228, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .extend({ top: 6, bottom: 6, left: 6, right: 6, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 }).toFile(path.join(OUT, 'wechat/png', name));
  // 240 WeChat captioned
  const art240 = await sharp(src).resize(220, 172, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer();
  const l240 = wrap(caption, 20);
  const t240 = '<text x="120" y="205" text-anchor="middle" font-family="Microsoft YaHei, Segoe UI, sans-serif" font-size="14" font-weight="700" fill="#ffffff">' + esc(title) + '</text>' + l240.map((l, k) => '<text x="120" y="' + (219 + k * 11) + '" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="10" font-weight="700" fill="#ffffff">' + esc(l) + '</text>').join('');
  const svg240 = '<svg width="240" height="240" xmlns="http://www.w3.org/2000/svg">' + grad('g2') +
    '<rect x="10" y="188" width="220" height="46" rx="14" fill="url(#g2)" stroke="#38bdf8" stroke-width="1.4"/>' + t240 + '</svg>';
  await sharp(empty(240, 240)).composite([{ input: art240, top: 6, left: 10 }, { input: Buffer.from(svg240), top: 0, left: 0 }]).png({ compressionLevel: 9 }).toFile(path.join(OUT, 'wechat/captioned', name));
  // 240 animated (2-frame bounce)
  // Render each frame first. Resizing a joined filmstrip destroys the page height.
  const frameArt = await sharp(src).resize(220, 220, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer();
  const a = await sharp(empty(240, 240)).composite([{ input: frameArt, top: 6, left: 10 }]).png().toBuffer();
  const b = await sharp(empty(240, 240)).composite([{ input: frameArt, top: 14, left: 10 }]).png().toBuffer();
  await sharp([a, b], { join: { animated: true } })
    .gif({ delay: [700, 700], loop: 0, dither: 1 }).toFile(path.join(OUT, 'wechat/gif', name.replace(/\.png$/, '.gif')));
  manifest.push({ index: i, file: name, pose, title, caption });
}
writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({ pack: 'Whale Musume - Bilingual Sticker Pack', count: manifest.length, sets: { master: 'png/ + captioned/ (512)', wechat: 'wechat/png + wechat/captioned (240) + wechat/gif' }, stickers: manifest }, null, 2));
writeFileSync(path.join(OUT, 'manifest.csv'), ['index,file,pose,title,caption'].concat(manifest.map((m) => [m.index, m.file, m.pose, JSON.stringify(m.title), JSON.stringify(m.caption)].join(','))).join('\n') + '\n');
console.log('stickers: ' + manifest.length + ' -> ' + OUT);
