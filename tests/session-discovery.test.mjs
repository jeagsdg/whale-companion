import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
test('long-lived root sessions survive many subagents and JSON cache stays fresh and bounded',{skip:process.platform!=='win32'},()=>{
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});const home=fs.mkdtempSync(path.join(diag,'session-discovery-'));
  try{
    const r=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.resolve('tests/session-discovery.test.ps1'),'-TestHome',home],{encoding:'utf8',windowsHide:true,timeout:30000});
    assert.equal(r.status,0,r.stderr||r.stdout);
  }finally{assert.ok(home.startsWith(diag+path.sep));fs.rmSync(home,{recursive:true,force:true});}
});
