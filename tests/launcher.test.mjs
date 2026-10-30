import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const diag=path.join(root,'.diag');fs.mkdirSync(diag,{recursive:true});
function run(scenario,verify){
  const home=fs.mkdtempSync(path.join(diag,'launcher-test-'));
  try{
    const result=spawnSync('powershell.exe',['-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(root,'tests/launcher-probe.ps1'),'-PetHome',home,'-Scenario',scenario],{encoding:'utf8',windowsHide:true,timeout:60000});
    assert.equal(result.status,0,result.stderr||result.stdout);
    const calls=JSON.parse(fs.readFileSync(path.join(home,'trace.json'),'utf8'));
    verify(home,calls);
  }finally{assert.ok(path.relative(diag,home)&&!path.relative(diag,home).startsWith('..'));fs.rmSync(home,{recursive:true,force:true});}
}
test('actual launcher respects stopped intent without spawning any process',()=>run('Stopped',(_,calls)=>assert.equal(calls.length,0)));
test('actual launcher leaves a hidden live UI hidden without spawning',()=>run('Hidden',(home,calls)=>{assert.equal(calls.length,0);assert.ok(fs.existsSync(path.join(home,'hidden.json')));assert.ok(!fs.existsSync(path.join(home,'show.json')));}));
test('actual launcher recovers only the missing component, always hidden',()=>run('Recovery',(_,calls)=>{assert.equal(calls.length,1);assert.equal(calls[0].exe,'powershell.exe');assert.equal(calls[0].style,'Hidden');assert.match(calls[0].args,/whale-pet\.ps1/);assert.doesNotMatch(calls[0].args,/whale-pet-http/);}));
test('manual summon clears hidden state and marks the show request explicit',()=>run('ManualShow',(home,calls)=>{assert.equal(calls.length,0);assert.ok(!fs.existsSync(path.join(home,'hidden.json')));assert.equal(JSON.parse(fs.readFileSync(path.join(home,'show.json'),'utf8')).explicit,true);}));
test('a bridge belonging to another installation is rejected without spawning or showing anything',()=>run('ForeignBridge',(home,calls)=>{assert.equal(calls.length,0);assert.ok(JSON.parse(fs.readFileSync(path.join(home,'conflict.json'),'utf8')).error);}));
test('Codex metadata worker recovery launches just the missing worker and keeps a hidden UI hidden',()=>run('CodexRecovery',(home,calls)=>{assert.equal(calls.length,1);assert.match(calls[0].args,/whale-codex\.ps1/);assert.equal(calls[0].style,'Hidden');assert.ok(fs.existsSync(path.join(home,'hidden.json')));}));
test('new host opening clears previous exit and hidden state and sends one explicit wake request',()=>run('HostOpen',(home,calls)=>{assert.equal(calls.length,0);assert.equal(JSON.parse(fs.readFileSync(path.join(home,'control.json'),'utf8')).stopped,false);assert.ok(!fs.existsSync(path.join(home,'hidden.json')));assert.equal(JSON.parse(fs.readFileSync(path.join(home,'show.json'),'utf8')).explicit,true);}));
test('disabled host opening respects the previous exit and hidden intent',()=>run('HostDisabled',(home,calls)=>{assert.equal(calls.length,0);assert.equal(JSON.parse(fs.readFileSync(path.join(home,'control.json'),'utf8')).stopped,true);assert.ok(fs.existsSync(path.join(home,'hidden.json')));assert.ok(!fs.existsSync(path.join(home,'show.json')));}));
test('ten cold starts while a child is still initializing enqueue only one hidden UI process',()=>run('ColdRepeat',(_,calls)=>{assert.equal(calls.length,1);assert.equal(calls[0].style,'Hidden');}));
test('native mode restores the service on host opening without showing the old floating pet',()=>run('NativeHostOpen',(home,calls)=>{
  assert.equal(calls.length,0);assert.equal(JSON.parse(fs.readFileSync(path.join(home,'control.json'),'utf8')).stopped,false);
  assert.ok(fs.existsSync(path.join(home,'hidden.json')));assert.ok(!fs.existsSync(path.join(home,'show.json')));
}));
test('explicit panel recovery revives only the hidden service and queues the requested panel',()=>run('SupportOnly',(home,calls)=>{
  assert.equal(calls.length,1);assert.match(calls[0].args,/whale-pet\.ps1/);assert.equal(calls[0].style,'Hidden');
  assert.equal(JSON.parse(fs.readFileSync(path.join(home,'control.json'),'utf8')).stopped,false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(home,'hidden.json'),'utf8')).supportOnly,true);
  const commands=fs.readdirSync(path.join(home,'commands'));assert.equal(commands.length,1);
  assert.equal(JSON.parse(fs.readFileSync(path.join(home,'commands',commands[0]),'utf8')).panel,'tasks');
  assert.ok(!fs.existsSync(path.join(home,'show.json')));
}));
test('a host watcher cannot undo an explicit service-only recovery',()=>run('SupportHostOpen',(home,calls)=>{
  assert.equal(calls.length,0);assert.equal(JSON.parse(fs.readFileSync(path.join(home,'hidden.json'),'utf8')).supportOnly,true);
  assert.ok(!fs.existsSync(path.join(home,'show.json')));
}));
test('an explicit manual summon can leave service-only mode',()=>run('SupportManualShow',(home,calls)=>{
  assert.equal(calls.length,0);assert.ok(!fs.existsSync(path.join(home,'hidden.json')));
  assert.equal(JSON.parse(fs.readFileSync(path.join(home,'show.json'),'utf8')).explicit,true);
}));
test('an explicit panel waits for a concurrent launcher rather than silently losing its request',()=>run('ContendedPanel',(home,calls)=>{
  assert.equal(calls.length,1);
  const commands=fs.readdirSync(path.join(home,'commands'));assert.equal(commands.length,1);
  assert.equal(JSON.parse(fs.readFileSync(path.join(home,'commands',commands[0]),'utf8')).panel,'tasks');
  assert.ok(!fs.existsSync(path.join(home,'show.json')));
}));
