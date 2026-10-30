import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

test('every shipped PowerShell script parses in Windows PowerShell 5.1, including Chinese tools', {skip:process.platform!=='win32'},()=>{
  const script = `$ErrorActionPreference='Stop';$failed=$false;foreach($file in Get-ChildItem -LiteralPath @('packages','tools') -Filter '*.ps1' -File -Recurse){$tokens=$null;$problems=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$problems);foreach($problem in $problems){$failed=$true;Write-Output ($file.FullName+':'+$problem.Extent.StartLineNumber+' '+$problem.Message)}};if($failed){exit 1};Write-Output 'SYNTAX_OK'`;
  const run=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{encoding:'utf8',windowsHide:true,timeout:15000});
  assert.equal(run.status,0,run.error?.message||run.stdout+run.stderr);
  assert.match(run.stdout,/SYNTAX_OK/);
});
