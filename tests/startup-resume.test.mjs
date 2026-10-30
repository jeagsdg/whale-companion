import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const diag=path.resolve('.diag');fs.mkdirSync(diag,{recursive:true});
function fixture(run){const home=fs.mkdtempSync(path.join(diag,'startup-resume-'));try{run(home)}finally{assert.ok(!path.relative(diag,home).startsWith('..'));fs.rmSync(home,{recursive:true,force:true})}}
function ps(file,args=[]){return spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',file,...args],{encoding:'utf8',windowsHide:true,timeout:25000})}

test('NoStartup resumes only a verified task for this home and waits for an independent monitor',{skip:process.platform!=='win32'},()=>fixture(home=>{
  const result=ps(path.resolve('tests/startup-resume.test.ps1'),['-TestHome',home]);
  assert.equal(result.status,0,result.stderr||result.stdout);assert.match(result.stdout,/STARTUP_RESUME_PASSED=\d+/);
}));

test('real installer restores the existing task before UI launch and NoStart invokes neither',{skip:process.platform!=='win32'},()=>fixture(home=>{
  const source=path.join(home,'source'),tools=path.join(source,'tools'),pet=path.join(source,'packages/desktop-pet');
  fs.mkdirSync(tools,{recursive:true});fs.mkdirSync(pet,{recursive:true});
  fs.copyFileSync(path.resolve('tools/install-codex.ps1'),path.join(tools,'install-codex.ps1'));
  fs.writeFileSync(path.join(pet,'whale-pet-start.ps1'),"throw 'The process launcher must be mocked'\n");
  fs.writeFileSync(path.join(pet,'whale-startup.ps1'),`function Resolve-PetPhysicalHome([string]$PetHome){return [IO.Path]::GetFullPath($PetHome)}
function Resume-PetStartupTask([string]$PetHome){[IO.File]::AppendAllText($env:WHALE_STARTUP_TEST_SEQUENCE,"resume\n");return $true}
function Install-PetStartupTask {throw 'NoStartup must not register a task'}
`);
  const wrapper=path.join(home,'wrapper.ps1');
  fs.writeFileSync(wrapper,`param([string]$Installer,[string]$Runtime,[string]$Legacy,[string]$Sequence,[switch]$NoStart)
$ErrorActionPreference='Stop'
$env:WHALE_STARTUP_TEST_SEQUENCE=$Sequence
function Get-CimInstance {return @()}
function Stop-Process {throw 'No unrelated process may be stopped'}
function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,$WorkingDirectory);[IO.File]::AppendAllText($env:WHALE_STARTUP_TEST_SEQUENCE,"launcher\n")}
& $Installer -PetHome $Runtime -LegacyPetHome $Legacy -NoStartup -NoStart:$NoStart
`);
  const runtime=path.join(home,'runtime'),legacy=path.join(home,'absent-legacy'),sequence=path.join(home,'sequence.txt');
  const args=['-Installer',path.join(tools,'install-codex.ps1'),'-Runtime',runtime,'-Legacy',legacy,'-Sequence',sequence];
  const first=ps(wrapper,args);assert.equal(first.status,0,first.stderr||first.stdout);
  assert.deepEqual(fs.readFileSync(sequence,'utf8').trim().split(/\r?\n/),['resume','launcher']);
  fs.writeFileSync(sequence,'');
  const second=ps(wrapper,[...args,'-NoStart']);assert.equal(second.status,0,second.stderr||second.stdout);
  assert.equal(fs.readFileSync(sequence,'utf8'),'');
  const installer=fs.readFileSync(path.resolve('tools/install-codex.ps1'),'utf8');
  const launch=installer.lastIndexOf('Start-Process -FilePath $powershell');
  assert.ok(launch>installer.indexOf('Install-PetStartupTask $PetHome -StartNow'));
  assert.ok(launch>installer.indexOf('Resume-PetStartupTask $PetHome'));
}));
