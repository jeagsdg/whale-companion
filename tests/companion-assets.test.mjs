import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { join, resolve, relative, isAbsolute, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';

test('catalog supplies the curated transparent sticker set alongside the complete legacy library', () => {
  const pet = resolve('packages/desktop-pet');
  const catalog = JSON.parse(readFileSync(join(pet, 'sticker-catalog.json'), 'utf8'));
  assert.equal(catalog.version, 2);
  assert.equal(catalog.stickers.length, 104);
  assert.equal(new Set(catalog.stickers.map(s => s.id)).size, 104);
  assert.equal(new Set(catalog.stickers.map(s => s.file)).size, 104);
  assert.equal(catalog.stickers.filter(s=>s.recommended).length,12);
  assert.deepEqual(catalog.groups.map(g => g.id), ['emotion', 'work', 'life', 'weather', 'festival', 'interaction']);
  for (const sticker of catalog.stickers) {
    assert(catalog.groups.some(g => g.id === sticker.group));
    assert(/[\u3400-\u9fff]/.test(sticker.caption), 'Chinese caption: ' + sticker.id);
    assert(/[A-Za-z]/.test(sticker.en));
    assert(existsSync(join(pet, sticker.file)), sticker.file);
    const png = readFileSync(join(pet, sticker.file));
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    if(sticker.recommended){assert(png.readUInt32BE(16)>=512&&png.readUInt32BE(20)>=512)}
    else{assert.equal(png.readUInt32BE(16),512);assert.equal(png.readUInt32BE(20),512)}
  }
  assert(catalog.stickers.some(s => s.tags.includes('comfort')));
  assert(catalog.stickers.some(s => s.tags.includes('encouragement')));
});

test('real sticker generator emits complete PNG sets and actual two-frame transparent GIFs', async t => {
  let sharp;
  for (const base of [process.env.PET_SHARP_BASE, resolve('.'), resolve(dirname(process.execPath), '..'),
    process.env.USERPROFILE && join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node')].filter(Boolean)) {
    try { sharp = createRequire(join(base, 'test-image-runtime.cjs'))('sharp'); break; } catch { }
  }
  if (!sharp) return t.skip('Optional sharp runtime is not installed.');
  const temp = mkdtempSync(join(tmpdir(), 'whale-real-stickers-'));
  try {
    const run = spawnSync(process.execPath, [resolve('tools/make-stickers.mjs'), '--limit', '3', '--output', temp],
      { encoding: 'utf8', timeout: 60000, windowsHide: true });
    assert.equal(run.status, 0, run.stdout + run.stderr);
    const manifest = JSON.parse(readFileSync(join(temp, 'manifest.json'), 'utf8'));
    assert.equal(manifest.count, 3);
    for (const sticker of manifest.stickers) {
      for (const [folder, size] of [['png', 512], ['captioned', 512], ['wechat/png', 240], ['wechat/captioned', 240]]) {
        const metadata = await sharp(join(temp, folder, sticker.file)).metadata();
        assert.equal(metadata.width, size); assert.equal(metadata.height, size); assert(metadata.hasAlpha);
      }
      const gifPath = join(temp, 'wechat/gif', sticker.file.replace(/\.png$/, '.gif'));
      const metadata = await sharp(gifPath, { animated: true }).metadata();
      assert.equal(metadata.width, 240); assert.equal(metadata.pageHeight, 240);
      assert.equal(metadata.pages, 2); assert(metadata.hasAlpha); assert.equal(metadata.loop, 0);
      const a = await sharp(gifPath, { page: 0 }).raw().toBuffer();
      const b = await sharp(gifPath, { page: 1 }).raw().toBuffer();
      assert(!a.equals(b), 'Animation frames must differ');
    }
    assert.equal(readdirSync(join(temp, 'wechat/gif')).length, 3);
  } finally {
    const child = relative(resolve(tmpdir()), resolve(temp));
    assert(child.startsWith('whale-real-stickers-') && !child.startsWith('..') && !isAbsolute(child));
    rmSync(temp, { recursive: true, force: true });
  }
});
