import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

test('native companion delivers requested reminders without restoring its old floating window',{skip:process.platform!=='win32'},()=>{
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});
  const home=fs.mkdtempSync(path.join(diag,'native-notices-'));
  try{
    const result=spawnSync('powershell.exe',['-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.resolve('tests/native-notifications.test.ps1'),'-TestHome',home],{encoding:'utf8',windowsHide:true,timeout:30000});
    assert.equal(result.status,0,result.stderr||result.stdout);
    assert.match(result.stdout,/NATIVE_NOTIFICATIONS_PASSED=28/);
  }finally{
    assert.equal(path.dirname(home),diag);assert.match(path.basename(home),/^native-notices-/);
    fs.rmSync(home,{recursive:true,force:true});
  }
});
