import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

// Exact bytes of the bundled 2026-10-16 release. Keep this fixture independent
// of the user's global skills directory and of later bundled skill revisions.
const previousSkill=`---
name: whale-companion
description: Respond as the user's whale companion when they call 梁文峰 or explicitly ask the desktop pet for companionship, saved names, personal to-dos, reminders, focus sessions, or its news feed. Use existing whale_companion tools; ordinary coding work does not need this persona.
---

# Whale companion

The native pet supplies character animation and Codex task status. This skill brings the existing companion tools into its quick chat. It does not add custom menus or speech bubbles to the native pet.

Read \`whale_companion.pet_status\` at the start of a companion interaction. Use the current \`preferences.petName\` for the character and \`preferences.userName\` to address the user naturally; do not hard-code either name or rename the user. Keep replies warm, brief and relevant to what the user actually asked. Provide support without inventing the user's emotions or promising automatic messages.

Use the tools exposed by the installed \`whale_companion\` MCP server:

- \`pet_list_todos\` / \`pet_add_todo\`: read or create local to-dos when requested.
- \`pet_remind\`: create a requested one-off reminder using its supported minutes range.
- \`pet_focus\` / \`pet_cancel_focus\`: start or cancel a requested focus session.
- \`pet_news\`: read actual cached headlines, timestamps and original source links. Say when the feed is empty or stale. Use \`pet_refresh_news\` when the user requests a refresh; a queued refresh is not a completed refresh.
- \`pet_set_names\`: change names only when the user asks for a change.

Mutating tools return a queued command ID. Use \`pet_command_result\` to check whether it completed before claiming success; if it is still pending, say so. Do not repeatedly poll for an extended period. Surface an error accurately and stop retrying the same failed action without a changed condition.

The tools require the original local companion service to be running. Read-only saved data can remain available while it is offline, but creation, timers and reminders may not be. If offline, explain this and give the existing manual desktop-pet launch entry; do not claim a timer or reminder was set, and do not launch or restart another program silently.

Reply in the native quick chat. \`pet_say\` targets the original standalone pet's bubble, so use it only when the user asks to send text there. Hidden-mode reminder presentation may be delayed; do not promise delivery through the native pet.

When discussing work, use the actual current conversation and available task state. Summarize the concrete activity briefly. Do not fabricate progress or copy private prompts, tool arguments or code into pet notifications. The native animation's built-in task status is controlled by the app.
`;
const oldHash='920bea508da99e5903931236f7426ebd54fc730ed967f1924efceed8876d864c';
assert.equal(createHash('sha256').update(previousSkill).digest('hex'),oldHash);

function runInstaller(home){
  // A wrapper captures only the public result as JSON. Paths are arguments,
  // never interpolated into executable PowerShell text.
  const wrapper=path.join(home,'run-install.ps1');
  fs.writeFileSync(wrapper,"param([string]$Installer,[string]$TargetHome)\n$ErrorActionPreference='Stop'\n[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)\n& $Installer -CodexHome $TargetHome | ConvertTo-Json -Depth 6 -Compress\n");
  const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',wrapper,'-Installer',path.resolve('packages/native-pet/install.ps1'),'-TargetHome',home],{encoding:'utf8',windowsHide:true,timeout:20000});
  assert.equal(result.status,0,result.stderr||result.stdout);
  return JSON.parse(result.stdout.replace(/^\uFEFF/,''));
}
function fixture(run){
  const root=path.resolve('.diag');fs.mkdirSync(root,{recursive:true});
  const home=fs.mkdtempSync(path.join(root,'native-install-'));
  try {run(home)} finally {
    const relative=path.relative(root,home);assert.ok(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative));
    fs.rmSync(home,{recursive:true,force:true});
  }
}
function skillPath(home){return path.join(home,'skills/whale-companion/SKILL.md')}
const sourceSkill=fs.readFileSync(path.resolve('packages/native-pet/skill/whale-companion/SKILL.md'));

test('native pet can be installed twice with atomic replacements and leaves the current bundled skill unchanged',{skip:process.platform!=='win32'},()=>fixture(home=>{
  const first=runInstaller(home);assert.equal(first.companionSkill,'installed');assert.equal(first.selected,false);
  const installed=path.join(home,'pets/liangwenfeng-whale');
  for(const name of ['pet.json','spritesheet.webp'])assert.deepEqual(fs.readFileSync(path.join(installed,name)),fs.readFileSync(path.resolve('packages/native-pet/liangwenfeng-whale',name)));
  const second=runInstaller(home);assert.equal(second.companionSkill,'already-installed');assert.equal(second.companionSkillBackup,null);
  assert.deepEqual(fs.readFileSync(skillPath(home)),sourceSkill);
  const backups=fs.readdirSync(path.join(home,'pets-backups'));assert.equal(backups.length,1);
  for(const name of ['pet.json','spritesheet.webp'])assert.deepEqual(fs.readFileSync(path.join(home,'pets-backups',backups[0],name)),fs.readFileSync(path.join(installed,name)));
  assert.ok(!fs.readdirSync(installed).some(name=>name.endsWith('.tmp')));
}));

test('a known previous bundled skill is backed up and upgraded without touching companion data',{skip:process.platform!=='win32'},()=>fixture(home=>{
  fs.mkdirSync(path.dirname(skillPath(home)),{recursive:true});fs.writeFileSync(skillPath(home),previousSkill);
  const data=path.join(home,'companion-data.json');fs.writeFileSync(data,'{"tasks":[{"text":"keep me"}]}');
  const result=runInstaller(home);assert.equal(result.companionSkill,'upgraded');assert.ok(result.companionSkillBackup);
  assert.deepEqual(fs.readFileSync(skillPath(home)),sourceSkill);
  assert.equal(fs.readFileSync(result.companionSkillBackup,'utf8'),previousSkill);
  assert.ok(!path.relative(path.join(home,'skills-backups'),result.companionSkillBackup).startsWith('..'));
  assert.equal(fs.readFileSync(data,'utf8'),'{"tasks":[{"text":"keep me"}]}');
  const backupFolder=path.dirname(result.companionSkillBackup);
  assert.deepEqual(fs.readdirSync(backupFolder),['SKILL.md']);
  assert.ok(!fs.readdirSync(path.dirname(skillPath(home))).some(name=>name.endsWith('.tmp')));
  assert.equal(runInstaller(home).companionSkill,'already-installed');
  assert.equal(fs.readdirSync(path.join(home,'skills-backups')).length,1);
}));

test('unknown customized companion skills are preserved byte for byte',{skip:process.platform!=='win32'},()=>fixture(home=>{
  const custom=Buffer.from('---\nname: whale-companion\n---\nMy own instructions and naming preferences.\n');
  fs.mkdirSync(path.dirname(skillPath(home)),{recursive:true});fs.writeFileSync(skillPath(home),custom);
  const result=runInstaller(home);assert.equal(result.companionSkill,'existing-skill-preserved');assert.equal(result.companionSkillBackup,null);
  assert.deepEqual(fs.readFileSync(skillPath(home)),custom);assert.equal(fs.existsSync(path.join(home,'skills-backups')),false);
}));
