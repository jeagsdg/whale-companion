import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {ensureHostWatcher,maintainHostWatcher,atomicJson,callTool} from '../packages/desktop-pet/whale-mcp.mjs';
const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});
function fixture(fn){const home=fs.mkdtempSync(path.join(diag,'host-life-'));try{fn(home)}finally{assert.ok(!path.relative(diag,home).startsWith('..'));fs.rmSync(home,{recursive:true,force:true})}}
test('host open, explicit exit, re-open, hidden state, bounded recovery and stale show requests',()=>fixture(home=>{
  const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.resolve('tests/host-lifecycle.test.ps1'),'-TestHome',home],{windowsHide:true,encoding:'utf8',timeout:20000});
  assert.equal(result.status,0,result.stderr||result.stdout);assert.match(result.stdout,/HOST_LIFECYCLE_PASSED=31/);
}));
test('MCP bootstrap starts only a missing hidden monitor and never opens another Codex',()=>fixture(home=>{
  let calls=[];const spawnMock=(exe,args,options)=>{calls.push({exe,args,options});return {once(){},unref(){}}};
  assert.equal(ensureHostWatcher(home,spawnMock),false);fs.writeFileSync(path.join(home,'whale-host-watch.ps1'),'# fixture');
  assert.equal(ensureHostWatcher(home,spawnMock),true);assert.equal(calls.length,1);assert.match(calls[0].exe,/powershell\.exe$/i);assert.equal(calls[0].options.windowsHide,true);assert.equal(calls[0].options.stdio,'ignore');assert.ok(calls[0].args.includes(path.join(home,'whale-host-watch.ps1')));
  atomicJson(path.join(home,'host-watch-alive.json'),{at:Date.now(),pid:process.pid});assert.equal(ensureHostWatcher(home,spawnMock),false);
  fs.unlinkSync(path.join(home,'host-watch-alive.json'));atomicJson(path.join(home,'pet-preferences.json'),{autoWakeOnHostStart:false});assert.equal(ensureHostWatcher(home,spawnMock),false);
  atomicJson(path.join(home,'pet-preferences.json'),{host:'dsh'});assert.equal(ensureHostWatcher(home,spawnMock),false);assert.equal(calls.length,1);
}));
test('pet status exposes offline, hidden and stopped independently of cached task result',()=>fixture(home=>{
  atomicJson(path.join(home,'state.json'),{kind:'completion'});assert.equal(callTool(home,'pet_status').online,false);
  atomicJson(path.join(home,'alive.json'),{at:Date.now()});fs.writeFileSync(path.join(home,'hidden.json'),'{}');let s=callTool(home,'pet_status');assert.equal(s.online,true);assert.equal(s.hidden,true);assert.equal(s.status,'completion');
  atomicJson(path.join(home,'control.json'),{stopped:true});s=callTool(home,'pet_status');assert.equal(s.online,false);assert.equal(s.stopped,true);
}));

test('MCP rechecks after initial startup and prefers the silent native monitor',()=>fixture(home=>{
  let calls=[];let tick,cleared,unref=false;
  const stop=maintainHostWatcher(home,{ensure:h=>calls.push(h),schedule:(fn,ms)=>{assert.equal(ms,30000);tick=fn;return {unref(){unref=true}}},cancel:t=>{cleared=t}});
  assert.deepEqual(calls,[home]);tick();assert.deepEqual(calls,[home,home]);assert.equal(unref,true);stop();assert.ok(cleared);
  fs.writeFileSync(path.join(home,'whale-host-watch.exe'),'fixture');
  calls=[];
  assert.equal(ensureHostWatcher(home,(exe,args,options)=>{calls.push({exe,args,options});return {once(){},unref(){}}}),true);
  assert.equal(calls[0].exe,path.join(home,'whale-host-watch.exe'));assert.deepEqual(calls[0].args,['--pet-home',home]);assert.equal(calls[0].options.windowsHide,true);
  assert.equal(ensureHostWatcher(home,()=>{throw new Error('fixture launch failure')}),false);
  assert.match(fs.readFileSync(path.join(home,'host-bootstrap.log'),'utf8'),/fixture launch failure/);
}));

test('MCP bootstrap resolves redirected or junction homes before launching Windows processes',()=>fixture(home=>{
  const actual=path.join(home,'actual');fs.mkdirSync(actual);fs.writeFileSync(path.join(actual,'whale-host-watch.exe'),'fixture');
  const alias=path.join(home,'alias');fs.symlinkSync(actual,alias,'junction');let captured;
  assert.equal(ensureHostWatcher(alias,(exe,args)=>{captured={exe,args};return {once(){},unref(){}}}),true);
  assert.equal(captured.exe,path.join(actual,'whale-host-watch.exe'));assert.deepEqual(captured.args,['--pet-home',actual]);
}));
