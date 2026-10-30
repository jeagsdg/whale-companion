import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, readdirSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { spawnSync } from 'node:child_process';

test('Codex installation needs no DSH profile and preserves user data over migration and upgrades', { skip: process.platform !== 'win32' }, () => {
  const temp = mkdtempSync(join(tmpdir(), 'whale-codex-install-'));
  try {
    const source = join(temp, 'source'), tools = join(source, 'tools'), pet = join(source, 'packages/desktop-pet');
    const runtime = join(temp, 'pet home'), legacy = join(temp, 'legacy');
    for (const dir of [tools, pet, legacy]) mkdirSync(dir, { recursive: true });
    copyFileSync(resolve('tools/install-codex.ps1'), join(tools, 'install-codex.ps1'));
    assert.deepEqual([...readFileSync(join(tools, 'install-codex.ps1')).subarray(0, 3)], [0xef, 0xbb, 0xbf]);
    writeFileSync(join(pet, 'whale-pet-start.ps1'), "throw 'NoStart must prevent launcher execution'\n");
    for (const file of ['whale-pet.ps1', 'whale-pet-http.ps1', 'whale-codex.ps1', 'whale-companion.ps1', 'whale-news.ps1']) {
      writeFileSync(join(pet, file), 'new-' + file);
    }
    writeFileSync(join(pet, 'sticker-catalog.json'), '{"version":2}');
    writeFileSync(join(pet, 'lines.json'), '{"sourceDefaults":true}');
    writeFileSync(join(pet, 'pet-preferences.json'), '{"host":"codex","petName":"鲸鱼娘","quiet":true,"newPreference":true}');
    const data = ['pet-stats.json', 'pet-memory.json', 'position.json', 'lines.json', 'companion-data.json'];
    for (const file of data) writeFileSync(join(legacy, file), JSON.stringify({ userData: file }));
    writeFileSync(join(legacy, 'pet-preferences.json'), JSON.stringify({ host: 'dsh', petName: '小蓝', userName: '阿明', quiet: false, custom: 7 }));
    for (const file of ['state.json', 'control.json', 'alive.json', 'hidden.json', 'show.json', 'decision.json']) writeFileSync(join(legacy, file), '{"stale":true}');
    writeFileSync(join(legacy, 'whale-pet.ps1'), 'legacy program');
    const run = () => {
      const actual = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        join(tools, 'install-codex.ps1'), '-PetHome', runtime, '-LegacyPetHome', legacy, '-NoStart', '-NoStartup'],
        { encoding: 'utf8', timeout: 30000, windowsHide: true });
      assert.equal(actual.status, 0, (actual.error?.message || '') + actual.stdout + actual.stderr);
    };
    run();
    for (const file of data) assert.equal(readFileSync(join(runtime, file), 'utf8'), JSON.stringify({ userData: file }));
    for (const file of ['state.json', 'control.json', 'alive.json', 'hidden.json', 'show.json', 'decision.json']) assert(!existsSync(join(runtime, file)), file);
    const prefs = JSON.parse(readFileSync(join(runtime, 'pet-preferences.json'), 'utf8'));
    assert.deepEqual(prefs, { host: 'codex', petName: '小蓝', userName: '阿明', quiet: false, custom: 7, newPreference: true });
    assert.equal(readFileSync(join(runtime, 'whale-codex.ps1'), 'utf8'), 'new-whale-codex.ps1');
    assert.equal(JSON.parse(readFileSync(join(runtime, 'codex-migration.json'), 'utf8')).legacyDataCopied, true);
    writeFileSync(join(runtime, 'pet-stats.json'), '{"affinity":99}');
    writeFileSync(join(runtime, 'unknown-user-file.json'), '{"keep":true}');
    writeFileSync(join(pet, 'sticker-catalog.json'), '{"version":3}');
    writeFileSync(join(pet, 'whale-pet.ps1'), 'upgraded program');
    writeFileSync(join(legacy, 'pet-memory.json'), '{"changedAfterMigration":true}');
    run();
    assert.equal(readFileSync(join(runtime, 'pet-stats.json'), 'utf8'), '{"affinity":99}');
    assert.equal(readFileSync(join(runtime, 'pet-memory.json'), 'utf8'), JSON.stringify({ userData: 'pet-memory.json' }));
    assert.equal(readFileSync(join(runtime, 'unknown-user-file.json'), 'utf8'), '{"keep":true}');
    assert.equal(readFileSync(join(runtime, 'sticker-catalog.json'), 'utf8'), '{"version":3}');
    assert.equal(readFileSync(join(runtime, 'whale-pet.ps1'), 'utf8'), 'upgraded program');
    assert.equal(readFileSync(join(legacy, 'whale-pet.ps1'), 'utf8'), 'legacy program');
    const backups = readdirSync(runtime + '.backups').sort();
    assert.equal(backups.length, 2);
    assert.equal(readFileSync(join(runtime + '.backups', backups[0], 'legacy/lines.json'), 'utf8'), JSON.stringify({ userData: 'lines.json' }));
    assert.equal(readFileSync(join(runtime + '.backups', backups[1], 'installed/whale-pet.ps1'), 'utf8'), 'new-whale-pet.ps1');
    assert(!existsSync(join(temp, '.dsh/profiles')));
    // A fresh installation without any legacy directory also works.
    const fresh = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
      join(tools, 'install-codex.ps1'), '-PetHome', join(temp, 'fresh'), '-LegacyPetHome', join(temp, 'absent-legacy'), '-NoStart', '-NoStartup'],
      { encoding: 'utf8', timeout: 30000, windowsHide: true });
    assert.equal(fresh.status, 0, fresh.stdout + fresh.stderr);
    assert.equal(JSON.parse(readFileSync(join(temp, 'fresh/pet-preferences.json'), 'utf8')).host, 'codex');
  } finally {
    const child = relative(resolve(tmpdir()), resolve(temp));
    assert(child.startsWith('whale-codex-install-') && !child.startsWith('..') && !isAbsolute(child));
    rmSync(temp, { recursive: true, force: true });
  }
});
