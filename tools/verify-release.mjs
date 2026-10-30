import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const manifest=JSON.parse(fs.readFileSync('dist/latest-release.json','utf8'));
const source=path.join(manifest.directory,'whale-dsh-source-2.5.0');
const dsh=path.join(manifest.directory,'whale-dsh-2.5.0');
const npm=path.join(manifest.directory,'npm/dsh-whale-notify');
assert(!fs.existsSync(path.join(source,'packages/harmony-whale')),'Mobile source must not be published with DSH');
const forbidden=/^(?:companion-data|pet-preferences|pet-stats|pet-memory|news-library|alive|bridge-alive|control|state|position|approvals)\.json$|\.(?:p12|p7b|cer|keystore|log|hap)$/;
let count=0;
function scan(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){assert(!entry.isSymbolicLink());assert(!forbidden.test(entry.name),entry.name);assert(!/harmony|mobile|\.ets$|\.app$/i.test(entry.name),entry.name);if(entry.isDirectory())scan(path.join(dir,entry.name));else count++;}}
scan(source);scan(dsh);scan(npm);
assert(fs.existsSync(path.join(npm,'runtime/desktop-pet/whale-mcp.mjs')));
assert(fs.existsSync(path.join(source,'tests/test_bridge.py')));
assert(fs.existsSync(path.join(dsh,'Install-DSH.cmd')));
const pkg=JSON.parse(fs.readFileSync(path.join(npm,'package.json'),'utf8'));
assert(pkg.bin['whale-dsh-install']);assert(!pkg.private);assert(!pkg.scripts?.postinstall);
const home=fs.mkdtempSync(path.resolve('.build-cache/dsh-release-smoke-'));
fs.mkdirSync(path.join(home,'profiles/desktop'),{recursive:true});
fs.mkdirSync(path.join(home,'whale-pet'));
fs.writeFileSync(path.join(home,'profiles/desktop/package.json'),JSON.stringify({name:'smoke',dsh:{profile:{bundles:['existing']}}}));
fs.writeFileSync(path.join(home,'whale-pet/companion-data.json'),'{"test":"preserve-existing-data"}');
for(let i=0;i<2;i++){
 const run=spawnSync(process.execPath,[path.join(npm,'bin/install.cjs'),'-DshHome',home,'-NoStart','-NoStartup'],{encoding:'utf8',windowsHide:true,timeout:90000});
 assert.equal(run.status,0,run.stdout+run.stderr);
 assert.equal(fs.readFileSync(path.join(home,'whale-pet/companion-data.json'),'utf8'),'{"test":"preserve-existing-data"}');
}
const actual=JSON.parse(fs.readFileSync(path.join(home,'profiles/desktop/package.json'),'utf8'));
assert.equal(actual.dsh.profile.bundles.filter(x=>x==='dsh-whale-notify').length,1);
assert(actual.dsh.profile.bundles.includes('existing'));
assert(fs.existsSync(path.join(home,'whale-pet/whale-pet-start.ps1')));
assert.equal(JSON.parse(fs.readFileSync(path.join(home,'whale-pet/pet-preferences.json'),'utf8')).host,'dsh');
const result={status:'passed',scannedFiles:count,sourceCredentialsExcluded:true,packagedInstallAndUpgrade:true,existingDataPreserved:true};
fs.writeFileSync('.build-cache/release-verification.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
