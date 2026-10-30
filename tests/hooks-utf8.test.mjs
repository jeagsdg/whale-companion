import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

test('real PowerShell hook reads UTF-8 stdin without corrupting Chinese project metadata', {skip:process.platform!=='win32'}, () => {
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});
  const home=fs.mkdtempSync(path.join(diag,'hook-utf8-'));
  try {
    const input=JSON.stringify({hook_event_name:'UserPromptSubmit',session_id:'01a13567-1329-7381-bb41-6ce4f4d18c47',cwd:'E:\\项目\\中文项目 🐋',prompt:'PRIVATE_PROMPT'});
    const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.resolve('packages/desktop-pet/codex-hook.ps1'),'-PetHome',home],{input,encoding:'utf8',windowsHide:true,timeout:20000});
    assert.equal(result.status,0,result.stderr);assert.equal(result.stdout,'');
    const events=fs.readdirSync(path.join(home,'host-events'));assert.equal(events.length,1);
    const raw=fs.readFileSync(path.join(home,'host-events',events[0]),'utf8');
    assert.equal(JSON.parse(raw).note,'中文项目 🐋');assert.ok(!raw.includes('PRIVATE_PROMPT'));
  } finally {
    assert.ok(home.startsWith(diag+path.sep));fs.rmSync(home,{recursive:true,force:true});
  }
});
