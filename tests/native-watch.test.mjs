import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
test('lightweight Windows monitor preserves verified wake/exit/recovery behavior and cleanup',()=>{
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});const home=fs.mkdtempSync(path.join(diag,'native-watch-'));
  try{
    const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.resolve('tests/native-watch.test.ps1'),'-TestHome',home],{windowsHide:true,encoding:'utf8',timeout:60000});
    assert.equal(result.status,0,result.stderr||result.stdout);assert.match(result.stdout,/NATIVE_WATCH_PASSED=17/);
  }finally{assert.ok(path.relative(diag,home)&&!path.relative(diag,home).startsWith('..'));fs.rmSync(home,{recursive:true,force:true})}
});
