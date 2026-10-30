import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

test('bounded read-only health reports explain live, hidden, native, exit and corrupt installations',{skip:process.platform!=='win32'},()=>{
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});
  const home=fs.mkdtempSync(path.join(diag,'health-'));
  try {
    const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',path.resolve('tests/diagnostics.test.ps1'),'-TestHome',home],{encoding:'utf8',windowsHide:true,timeout:45000});
    assert.equal(result.status,0,result.stderr||result.stdout);
    assert.match(result.stdout,/DIAGNOSTICS_PASSED=\d+/);
    const cli=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.resolve('tools/diagnose-pet.ps1'),'-PetHome',home,'-Format','json'],{encoding:'utf8',windowsHide:true,timeout:15000});
    assert.equal(cli.status,0,cli.stderr||cli.stdout);
    const report=JSON.parse(cli.stdout.replace(/^\uFEFF/,''));
    assert.equal(report.schemaVersion,1);assert.ok(Array.isArray(report.suggestions));
  } finally { fs.rmSync(home,{recursive:true,force:true}); }
});
