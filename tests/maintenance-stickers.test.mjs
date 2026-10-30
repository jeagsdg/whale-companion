import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { spawnSync } from 'node:child_process';

test('generator smoke covers array and named captions without image dependencies', () => {
  const temp = mkdtempSync(join(tmpdir(), 'whale-stickers-smoke-'));
  try {
    const base = join(temp, 'runtime'), input = join(temp, 'input'), output = join(temp, 'output');
    const module = join(base, 'node_modules/sharp');
    mkdirSync(module, { recursive: true }); mkdirSync(input);
    writeFileSync(join(module, 'index.js'), `const fs = require('node:fs');
      module.exports = function(input) { const x = {
        resize() { return x; }, extend() { return x; }, png() { return x; }, gif() { return x; },
        composite(items) { for (const i of items) if (Buffer.isBuffer(i.input) && i.input.includes(Buffer.from('<svg')))
          fs.appendFileSync(process.env.SMOKE_SVG, i.input); return x; },
        async toBuffer() { return Buffer.from('stub'); }, async toFile(p) { fs.writeFileSync(p, 'stub'); }
      }; return x; };`);
    writeFileSync(join(input, 'dsh-whale-state-idle.webp'), 'stub');
    writeFileSync(join(input, 'dsh-whale-state-thinking.webp'), 'stub');
    const captions = join(temp, 'captions.json'), svg = join(temp, 'captions.svg');
    writeFileSync(captions, JSON.stringify({ idle: ['在的', "I'm here"], thinking: { cn: '让我想想', en: 'Hmm & <okay>' } }));
    const result = spawnSync(process.execPath, [resolve('tools/make-stickers.mjs')], { encoding: 'utf8',
      env: { ...process.env, DSH_SHARP_BASE: base, DSH_STICKER_INPUT: input,
        DSH_STICKER_OUTPUT: output, DSH_STICKER_CAPTIONS: captions, SMOKE_SVG: svg } });
    assert.equal(result.status, 0, result.stderr);
    const manifest = JSON.parse(readFileSync(join(output, 'manifest.json'), 'utf8'));
    assert.equal(manifest.count, 2);
    assert.equal(manifest.stickers[0].title, '在的');
    assert.equal(manifest.stickers[0].caption, "I'm here");
    assert.equal(manifest.stickers[0].file, '01-idle.png');
    assert.equal(manifest.stickers[1].caption, 'Hmm & <okay>');
    const markup = readFileSync(svg, 'utf8');
    assert(markup.includes('在的') && markup.includes("I'm here"));
    assert(markup.includes('Hmm &amp; &lt;okay&gt;'));
  } finally {
    const child = relative(resolve(tmpdir()), resolve(temp));
    assert(child.startsWith('whale-stickers-smoke-') && !child.startsWith('..') && !isAbsolute(child));
    rmSync(temp, { recursive: true, force: true });
  }
});
