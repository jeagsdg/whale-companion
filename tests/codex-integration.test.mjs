import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=path.resolve('.');
test('Codex registration preserves existing settings and hooks, backs up and updates idempotently',()=>{
  const diag=path.join(root,'.diag');fs.mkdirSync(diag,{recursive:true});
  const temp=fs.mkdtempSync(path.join(diag,'integration-'));
  try {
    const home=path.join(temp,'codex home'),pet=path.join(temp,'pet home');
    fs.mkdirSync(home);fs.mkdirSync(pet);
    fs.writeFileSync(path.join(pet,'whale-mcp.mjs'),'// fixture');fs.writeFileSync(path.join(pet,'codex-hook.ps1'),'# fixture');
    const before='notify = ["existing-notifier.exe", "keep"]\nmodel = "configured-model"\n\n[mcp_servers.existing]\ncommand = "existing.exe"\n';
    fs.writeFileSync(path.join(home,'config.toml'),before);
    const existing={description:'User hooks',hooks:{Stop:[{matcher:'keep',hooks:[{type:'command',command:'original-command',timeout:12}]}],PreToolUse:[{hooks:[{type:'command',command:'untouched'}]}]}};
    fs.writeFileSync(path.join(home,'hooks.json'),JSON.stringify(existing));
    const run=()=>spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/install-codex-integration.ps1'),'-PetHome',pet,'-CodexHome',home,'-NodePath',process.execPath,'-WithHooks'],{windowsHide:true,encoding:'utf8',timeout:15000});
    for(let i=0;i<2;i++) {
      const result=run();assert.equal(result.status,0,result.stderr||result.stdout);
      const content=fs.readFileSync(path.join(home,'config.toml'),'utf8');
      assert.ok(content.startsWith(before.trimEnd()),'all existing TOML is preserved');
      assert.equal(content.match(/\[mcp_servers.whale_companion\]/g).length,1);
      const hooks=JSON.parse(fs.readFileSync(path.join(home,'hooks.json'),'utf8'));
      assert.equal(hooks.description,'User hooks');assert.deepEqual(hooks.hooks.PreToolUse,existing.hooks.PreToolUse);
      assert.deepEqual(hooks.hooks.Stop[0],existing.hooks.Stop[0]);assert.equal(hooks.hooks.Stop.length,2);
      const advisory=hooks.hooks.PermissionRequest[0].hooks[0];
      assert.equal(advisory.async,true);assert.equal(advisory.timeout,3);assert.match(advisory.command,/WindowStyle Hidden/);
      assert.doesNotMatch(content+JSON.stringify(hooks),/dangerously|bypass-hook-trust|permissionDecision|allow_managed/);
      const parsed=spawnSync('python',['-c','import tomllib,sys,json; p=tomllib.load(open(sys.argv[1],"rb")); print(json.dumps(p["mcp_servers"]["whale_companion"]))',path.join(home,'config.toml')],{encoding:'utf8',windowsHide:true,timeout:10000});
      assert.equal(parsed.status,0,parsed.stderr);const server=JSON.parse(parsed.stdout);assert.deepEqual(server.args,[path.join(pet,'whale-mcp.mjs'),'--pet-home',pet]);
    }
    const backups=fs.readdirSync(path.join(home,'backups'));assert.equal(backups.length,2);
    assert.equal(fs.readFileSync(path.join(home,'backups',backups.sort()[0],'config.toml'),'utf8'),before);
    assert.ok(!fs.existsSync(path.join(home,'hooks-trust.json')));
    // An unowned entry is rejected before mutation.
    for(const unowned of ['[mcp_servers.whale_companion]\ncommand = "user-owned"\n',"[mcp_servers.'whale_companion']\ncommand = 'user-owned'\n",'[ mcp_servers.whale_companion ]\ncommand = "user-owned"\n','[mcp_servers]\nwhale_companion = {command = "user-owned"}\n']) {
      fs.writeFileSync(path.join(home,'config.toml'),unowned);
      const conflict=run();assert.notEqual(conflict.status,0);assert.equal(fs.readFileSync(path.join(home,'config.toml'),'utf8'),unowned);
    }
  } finally {assert.ok(path.relative(diag,temp)&&!path.relative(diag,temp).startsWith('..'));fs.rmSync(temp,{recursive:true,force:true});}
});
