import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { spawnSync } from 'node:child_process';

test('PowerShell 5.1 installer preserves runtime data and completes sparse profiles', () => {
  const temp = mkdtempSync(join(tmpdir(), 'whale-install-smoke-'));
  try {
    const source = join(temp, 'source'), tools = join(source, 'tools');
    const pet = join(source, 'packages/desktop-pet'), plugin = join(source, 'packages/dsh-whale-notify');
    for (const dir of [tools, pet, plugin]) mkdirSync(dir, { recursive: true });
    copyFileSync(resolve('tools/install.ps1'), join(tools, 'install.ps1'));
    const bytes = readFileSync(join(tools, 'install.ps1'));
    assert.deepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf], 'PS5.1 requires BOM for Chinese source');
    writeFileSync(join(pet, 'whale-pet-start.ps1'), "throw 'NoStart must prevent this fixture launcher from running'\n");
    writeFileSync(join(pet, 'whale-pet.ps1'), 'updated program');
    writeFileSync(join(pet, 'lines.json'), '{"default":true}');
    writeFileSync(join(plugin, 'index.js'), 'updated plugin');
    for (const [index, pkg] of [{ name: 'sparse', dsh: {} }, { name: 'empty' },
      { name: 'existing', dependencies: { old: '1.0' }, dsh: { profile: { bundles: ['existing'] } } }].entries()) {
      const home = join(temp, 'custom home ' + index), profile = join(home, 'profiles/desktop');
      const runtime = join(home, 'whale-pet'), store = join(home, 'whale-notify/dsh-whale-notify');
      const nm = join(profile, 'node_modules/dsh-whale-notify');
      for (const dir of [profile, runtime, store, nm]) mkdirSync(dir, { recursive: true });
      writeFileSync(join(profile, 'package.json'), JSON.stringify(pkg));
      const data = ['pet-stats.json', 'pet-memory.json', 'position.json', 'alive.json', 'hidden.json', 'decision.json', 'lines.json'];
      for (const file of data) writeFileSync(join(runtime, file), 'user-data-' + file);
      writeFileSync(join(runtime, 'old-only.txt'), 'preserve unknown user file');
      writeFileSync(join(runtime, 'whale-pet.ps1'), 'old program');
      writeFileSync(join(store, 'index.js'), 'old store');
      writeFileSync(join(nm, 'index.js'), 'old profile plugin');
      const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        join(tools, 'install.ps1'), '-DshHome', home, '-NoStart', '-NoStartup'];
      for (let run = 0; run < 2; run++) {
        const result = spawnSync('powershell.exe', args, { encoding: 'utf8', timeout: 60000, windowsHide: true });
        assert.equal(result.status, 0, (result.error?.message || '') + result.stdout + result.stderr);
        for (const file of data) assert.equal(readFileSync(join(runtime, file), 'utf8'), 'user-data-' + file);
      }
      assert.equal(readFileSync(join(runtime, 'whale-pet.ps1'), 'utf8'), 'updated program');
      assert.equal(readFileSync(join(runtime, 'old-only.txt'), 'utf8'), 'preserve unknown user file');
      const actual = JSON.parse(readFileSync(join(profile, 'package.json'), 'utf8'));
      assert.equal(actual.dependencies['dsh-whale-notify'], 'file:../../whale-notify/dsh-whale-notify');
      assert.equal(actual.dsh.profile.bundles.filter(x => x === 'dsh-whale-notify').length, 1);
      if (index === 2) { assert.equal(actual.dependencies.old, '1.0'); assert(actual.dsh.profile.bundles.includes('existing')); }
      const backups = readdirSync(join(home, 'backups')).sort();
      assert.equal(backups.length, 2);
      const firstBackup = join(home, 'backups', backups[0]);
      assert.equal(readFileSync(join(firstBackup, 'whale-pet/pet-stats.json'), 'utf8'), 'user-data-pet-stats.json');
      assert.equal(readFileSync(join(firstBackup, 'whale-pet/whale-pet.ps1'), 'utf8'), 'old program');
      assert.equal(readFileSync(join(firstBackup, 'plugin-store/index.js'), 'utf8'), 'old store');
      assert.equal(readFileSync(join(firstBackup, 'plugin-profile/index.js'), 'utf8'), 'old profile plugin');
      assert.equal(JSON.parse(readFileSync(join(firstBackup, 'package.json'), 'utf8')).name, pkg.name);
    }
  } finally {
    const child = relative(resolve(tmpdir()), resolve(temp));
    assert(child.startsWith('whale-install-smoke-') && !child.startsWith('..') && !isAbsolute(child));
    rmSync(temp, { recursive: true, force: true });
  }
});
