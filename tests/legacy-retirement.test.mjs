import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
test('stopped legacy bridge releases startup and old manual entry forwards to the chosen Codex home',()=>{
  const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});const temp=fs.mkdtempSync(path.join(diag,'retire-test-'));
  try {
    const source=path.join(temp,'source'),tools=path.join(source,'tools'),pkg=path.join(source,'packages','desktop-pet'),legacy=path.join(temp,'legacy'),runtime=path.join(temp,'custom runtime');
    for(const dir of [tools,pkg,legacy])fs.mkdirSync(dir,{recursive:true});
    fs.copyFileSync(path.resolve('tools/install-codex.ps1'),path.join(tools,'install-codex.ps1'));
    fs.copyFileSync(path.resolve('packages/desktop-pet/legacy-codex-forward.ps1'),path.join(pkg,'legacy-codex-forward.ps1'));
    fs.writeFileSync(path.join(pkg,'whale-pet-start.ps1'),"param([string]$PetHome,[switch]$Auto,[switch]$Show)\n[IO.File]::AppendAllText((Join-Path $PetHome 'trace.txt'),'new'+[Environment]::NewLine)\n");
    fs.writeFileSync(path.join(pkg,'pet-preferences.json'),'{"host":"codex"}');
    const oldLauncher="param([string]$PetHome,[switch]$Auto,[switch]$Show)\nthrow 'legacy UI must not run'\n";
    const oldBridge="param([int]$Port=19390,[string]$PetHome=$PSScriptRoot)\nthrow 'stopped legacy bridge must not bind'\n";
    fs.writeFileSync(path.join(legacy,'whale-pet-start.ps1'),oldLauncher);fs.writeFileSync(path.join(legacy,'whale-pet-http.ps1'),oldBridge);
    fs.writeFileSync(path.join(legacy,'control.json'),'{"stopped":true}');fs.writeFileSync(path.join(legacy,'pet-stats.json'),'{"level":7}');
    const run=(file,args=[])=>spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',file,...args],{windowsHide:true,encoding:'utf8',timeout:60000});
    let result=run(path.join(tools,'install-codex.ps1'),['-PetHome',runtime,'-LegacyPetHome',legacy,'-NoStartup']);assert.equal(result.status,0,result.stderr||result.stdout);
    const record=JSON.parse(fs.readFileSync(path.join(legacy,'codex-preferred.json'),'utf8'));assert.equal(record.petHome,runtime);
    assert.equal(fs.readFileSync(path.join(legacy,'pet-stats.json'),'utf8'),'{"level":7}');assert.equal(fs.readFileSync(path.join(runtime,'pet-stats.json'),'utf8'),'{"level":7}');
    const backup=path.join(runtime+'.backups',fs.readdirSync(runtime+'.backups')[0],'retired-legacy');assert.equal(fs.readFileSync(path.join(backup,'whale-pet-start.ps1'),'utf8'),oldLauncher);assert.equal(fs.readFileSync(path.join(backup,'whale-pet-http.ps1'),'utf8'),oldBridge);
    result=run(path.join(legacy,'whale-pet-http.ps1'),['-PetHome',legacy]);assert.equal(result.status,0,result.stderr);
    const trace=path.join(runtime,'trace.txt');const before=fs.existsSync(trace)?fs.readFileSync(trace,'utf8'):'';
    result=run(path.join(legacy,'whale-pet-start.ps1'),['-PetHome',legacy,'-Auto']);assert.equal(result.status,0,result.stderr);assert.equal(fs.existsSync(trace)?fs.readFileSync(trace,'utf8'):'',before);
    result=run(path.join(legacy,'whale-pet-start.ps1'),['-PetHome',legacy,'-Show']);assert.equal(result.status,0,result.stderr);assert.equal(fs.readFileSync(trace,'utf8'),before+'new\r\n');
  }finally{assert.ok(path.relative(diag,temp)&&!path.relative(diag,temp).startsWith('..'));fs.rmSync(temp,{recursive:true,force:true});}
});
