// Sync the desktop companion's PNG library from the existing licensed source art.
// The conversion preserves all decoded RGBA pixels; existing PNGs stay untouched.
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const input = path.join(root, 'packages/dsh-whale-notify/assets/generated');
const pet = path.join(root, 'packages/desktop-pet');
const assets = path.join(pet, 'assets');
const captions = JSON.parse(readFileSync(path.join(root, 'tools/sticker-captions.json'), 'utf8').replace(/^\uFEFF/, ''));
const bases = [process.env.PET_SHARP_BASE, root, path.resolve(path.dirname(process.execPath), '..'),
  process.env.USERPROFILE && path.join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node')].filter(Boolean);
let sharp;
for (const base of bases) {
  try { sharp = createRequire(path.join(base, 'image-runtime.cjs'))('sharp'); break; } catch { }
}
if (!sharp) throw new Error('Install sharp locally or set PET_SHARP_BASE to its dependency directory.');
const aliases = { 'idle-cute': 'idle', thinking: 'think', waiting: 'wait', success: 'ok', failure: 'err', 'meme-no': 'no', 'home-peek': 'peek' };
const groups = [{ id: 'emotion', label: '情绪' }, { id: 'work', label: '工作' }, { id: 'life', label: '生活' },
  { id: 'weather', label: '天气' }, { id: 'festival', label: '节日' }, { id: 'interaction', label: '互动' }];
function groupFor(id) {
  if (id.startsWith('weather-')) return 'weather';
  if (id.startsWith('festival-') || id === 'valentine') return 'festival';
  if (id.startsWith('daily-') || ['eat', 'afk', 'sleep', 'night', 'greet', 'sweep', 'meme-music'].includes(id)) return 'life';
  if (id.startsWith('work-') || ['thinking', 'waiting', 'tool', 'running', 'success', 'failure', 'achievement', 'levelup', 'balance-low', 'workbench-peek', 'settings-peek'].includes(id)) return 'work';
  if (id.startsWith('game-') || id.startsWith('react-') || ['pick-up', 'home-peek', 'idle-cute', 'wink', 'teasing'].includes(id)) return 'interaction';
  return 'emotion';
}
const extraTags = {
  'work-pat': ['encouragement', 'comfort'], 'react-head': ['comfort'], 'meme-heart': ['affection', 'comfort'],
  'meme-kyun': ['affection'], 'tail-swing': ['happy'], celebrate: ['happy'], 'game-happy': ['happy'],
  'idle-cute': ['company', 'calm'], 'meme-peace': ['calm'], 'daily-stretch': ['break'],
  'daily-coffee': ['break'], 'daily-done': ['rest'], 'meme-cry': ['sad'], 'meme-smile-pain': ['sad']
};
mkdirSync(assets, { recursive: true });
const stickers = [];
let added = 0;
for (const file of readdirSync(input).filter(f => f.endsWith('.webp')).sort()) {
  const id = file.replace(/^dsh-whale-(?:state-)?/, '').replace(/\.webp$/, '');
  const pose = aliases[id] || id;
  const output = path.join(assets, pose + '.png');
  if (!existsSync(output)) {
    await sharp(path.join(input, file)).png({ compressionLevel: 9 }).toFile(output);
    const originalPixels = await sharp(path.join(input, file)).ensureAlpha().raw().toBuffer();
    const convertedPixels = await sharp(output).ensureAlpha().raw().toBuffer();
    if (!originalPixels.equals(convertedPixels)) throw new Error('Pixel mismatch: ' + file);
    added++;
  }
  const pair = captions[id];
  if (!Array.isArray(pair) || !pair[0] || !pair[1]) throw new Error('Missing bilingual captions for ' + id);
  stickers.push({ id, pose, file: 'assets/' + pose + '.png', caption: pair[0], en: pair[1], group: groupFor(id),
    tags: [groupFor(id), ...(extraTags[id] || [])] });
}
const curated=JSON.parse(readFileSync(path.join(root,'tools/sticker-v3.json'),'utf8'));
for(const item of curated){
  if(!existsSync(path.join(assets,item.id+'.png')))throw new Error('Missing approved generated asset: '+item.id);
  stickers.push({...item,pose:item.id,file:'assets/'+item.id+'.png',recommended:true});
}
const bindings={think:'v3-debug',tool:'v3-working',running:'v3-working',ok:'v3-success',err:'v3-debug',wait:'v3-received',greet:'v3-hello',night:'v3-calm',sleep:'v3-tired',afk:'v3-tired','work-sleep':'v3-tired','daily-done':'v3-success','work-pat':'v3-comfort','daily-coffee':'v3-tea'};
writeFileSync(path.join(pet, 'sticker-catalog.json'), JSON.stringify({ version: 2, groups, bindings, stickers }, null, 2) + '\n');
console.log(JSON.stringify({ count: stickers.length, added, groups: Object.fromEntries(groups.map(g => [g.label, stickers.filter(s => s.group === g.id).length])) }));
