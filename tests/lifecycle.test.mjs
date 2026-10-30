import test from 'node:test';
import assert from 'node:assert/strict';
import {createPetSupervisor} from '../packages/dsh-whale-notify/lib/pet-lifecycle.js';

function setup(overrides={}) {
  let clock=1000000, stopped=false, calls=[];
  const supervisor=createPetSupervisor({petHome:'C:/pet',now:()=>clock,health:async()=>null,
    readJson:(path)=>path.endsWith('control.json')?{stopped}:null,exists:()=>true,
    processAlive:()=>false,spawn:(options)=>{calls.push(options);return {done:Promise.resolve()};},...overrides});
  return {supervisor,calls,setStopped(value){stopped=value;},advance(ms){clock+=ms;}};
}
test('healthy hidden pet is never shown or launched',async()=>{
  const {supervisor,calls}=setup({health:async()=>({ok:true,uiAlive:true})});
  for(let i=0;i<10;i++) assert.equal(await supervisor.check(),'online');
  assert.equal(calls.length,0);
});
test('intentional exit stays exited',async()=>{
  const {supervisor,calls,setStopped}=setup();setStopped(true);
  assert.equal(await supervisor.check(),'stopped');assert.equal(calls.length,0);
});
test('recovery has backoff, finite retries and no Explorer/cmd fallback',async()=>{
  const {supervisor,calls,advance}=setup();
  assert.equal(await supervisor.check(),'starting');
  assert.equal(await supervisor.check(),'backoff');
  for(let i=0;i<2;i++){advance(600000);assert.equal(await supervisor.check(),'starting');}
  advance(600000);assert.equal(await supervisor.check(),'retry-limit');
  assert.equal(calls.length,3);
  for(const call of calls){assert.equal(call.argv[0],'powershell.exe');assert.ok(call.argv.includes('Hidden'));assert.ok(call.argv.includes('-Auto'));assert.ok(!call.argv.some(arg=>/explorer|cmd\.exe|\/show/i.test(arg)));}
});
test('overlapping checks never spawn twice; dispose cancels in-flight recovery',async()=>{
  let finish;const pending=new Promise(resolve=>finish=resolve);
  const {supervisor,calls}=setup({health:()=>pending});
  const first=supervisor.check();assert.equal(await supervisor.check(),'idle');
  supervisor.dispose();finish(null);assert.equal(await first,'disposed');assert.equal(calls.length,0);
});
test('user exit during health request is respected before spawning',async()=>{
  let finish;const pending=new Promise(resolve=>finish=resolve);
  const {supervisor,calls,setStopped}=setup({health:()=>pending});
  const first=supervisor.check();setStopped(true);finish(null);assert.equal(await first,'stopped');assert.equal(calls.length,0);
});
