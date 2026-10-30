import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.join(root,'dist');
const stamp=new Date().toISOString().replace(/[:.]/g,'-');
const release=path.join(output,'whale-release-'+stamp);
fs.mkdirSync(release,{recursive:true});
const runtimeJson=new Set(['lines.json','runtime-version.json','sticker-catalog.json']);
const sourceExt=new Set(['.mjs','.js','.cjs','.ps1','.py','.cmd','.cs','.dll','.exe','.css','.png','.webp','.ico','.md','.yml','.ts','.ets','.html','.json','.json5','.txt']);
const forbidden=new Set(['node_modules','oh_modules','build','.hvigor','.git','.idea','.src','out','dist','runtime','release','__pycache__']);
const desktop=(rel)=>rel.startsWith('assets/')?/^[a-z0-9-]+\.(png|ico)$/.test(path.basename(rel)):!rel.includes('/')&&(runtimeJson.has(rel)||/\.(ps1|mjs|cmd|cs|dll|exe)$/.test(rel));
function tree(src,dst,filter=()=>true,base=''){
 for(const item of fs.readdirSync(src,{withFileTypes:true})){
  if(item.isSymbolicLink())continue;
  const rel=base+item.name,from=path.join(src,item.name),to=path.join(dst,item.name);
  if(item.isDirectory()){if(!forbidden.has(item.name))tree(from,to,filter,rel+'/');}
  else if(filter(rel)&&sourceExt.has(path.extname(item.name))&&!/^(local\.properties|oh-package-lock\.json5|build-profile\.json5\.bak)$/.test(item.name)&&!/(?:signing|secret|token|credentials|\.p12|\.p7b|\.cer)/i.test(rel)){
   fs.mkdirSync(dst,{recursive:true});fs.copyFileSync(from,to);
  }
 }
}
function file(rel,dest){fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(root,rel),dest);}
const dsh=path.join(release,'whale-dsh-2.5.0');
tree(path.join(root,'packages/desktop-pet'),path.join(dsh,'packages/desktop-pet'),desktop);
tree(path.join(root,'packages/dsh-whale-notify'),path.join(dsh,'packages/dsh-whale-notify'));
for(const rel of ['tools/install.ps1','tools/diagnose-pet.ps1','LICENSE','docs/ARCHITECTURE.md','docs/UPSTREAM.md'])file(rel,path.join(dsh,rel));
file('docs/DSH-RELEASE.md',path.join(dsh,'README.md'));
file('Install-DSH.cmd',path.join(dsh,'Install-DSH.cmd'));
const source=path.join(release,'whale-dsh-source-2.5.0');
const publicFile=rel=>!/(?:harmony|mobile)/i.test(rel);
for(const dir of ['packages/desktop-pet','packages/dsh-whale-notify','packages/native-pet','tools','tests','docs','.github']){
 if(fs.existsSync(path.join(root,dir)))tree(path.join(root,dir),path.join(source,dir),dir==='packages/desktop-pet'?desktop:publicFile);
}
for(const name of ['package.json','LICENSE','CHANGELOG.md','Install-DSH.cmd','.gitignore'])file(name,path.join(source,name));
file('docs/DSH-RELEASE.md',path.join(source,'README.md'));
const workspace=JSON.parse(fs.readFileSync(path.join(source,'package.json'),'utf8'));
workspace.version='2.5.0';
for(const key of Object.keys(workspace.scripts))if(/harmony|mobile/i.test(key))delete workspace.scripts[key];
workspace.scripts['package:release']='node tools/package-release.mjs';
fs.writeFileSync(path.join(source,'package.json'),JSON.stringify(workspace,null,2)+'\n');
// Standalone npm archive: explicit CLI entrypoint, no installation-time execution.
const npm=path.join(release,'npm/dsh-whale-notify');
tree(path.join(root,'packages/dsh-whale-notify'),npm);
tree(path.join(root,'packages/desktop-pet'),path.join(npm,'runtime/desktop-pet'),desktop);
fs.mkdirSync(path.join(npm,'setup'),{recursive:true});
let installer=fs.readFileSync(path.join(root,'tools/install.ps1'),'utf8');
installer=installer.replace("$plugin = Join-Path $root 'packages\\dsh-whale-notify'","$plugin = $root").replace("$pet = Join-Path $root 'packages\\desktop-pet'","$pet = Join-Path $root 'runtime\\desktop-pet'");
fs.writeFileSync(path.join(npm,'setup/install.ps1'),installer.startsWith('\uFEFF')?installer:'\uFEFF'+installer);
file('LICENSE',path.join(npm,'LICENSE'));
const pkg=JSON.parse(fs.readFileSync(path.join(npm,'package.json'),'utf8'));
delete pkg.private;pkg.version='2.5.0';pkg.bin={'whale-dsh-install':'bin/install.cjs'};pkg.files=['lib','assets','cordis.patch.yml','runtime','setup','bin','LICENSE','README.md'];pkg.repository={type:'git',url:'https://github.com/Jeagsdg/whale-companion.git',directory:'packages/dsh-whale-notify'};
fs.writeFileSync(path.join(npm,'package.json'),JSON.stringify(pkg,null,2));
fs.mkdirSync(path.join(npm,'bin'),{recursive:true});
fs.writeFileSync(path.join(npm,'bin/install.cjs'),`#!/usr/bin/env node\nconst {spawnSync}=require('node:child_process');\nconst path=require('node:path');\nif(process.platform!=='win32'){console.error('DSH desktop companion requires Windows.');process.exit(1);}\nconst allowed=new Set(['-NoStart','-NoStartup','-DshHome']);const args=process.argv.slice(2);for(let i=0;i<args.length;i++){if(!allowed.has(args[i]))throw Error('Unknown installer option: '+args[i]);if(args[i]==='-DshHome'&&!args[++i])throw Error('Missing DshHome');}\nconst result=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'../setup/install.ps1'),...args],{stdio:'inherit',windowsHide:true});if(result.error)console.error(result.error.message);process.exit(result.status??1);\n`);
// ZIP creation uses Python stdlib, with every path passed as an argument.
const zipCode='import pathlib,sys,zipfile\np=pathlib.Path(sys.argv[1])\nwith zipfile.ZipFile(sys.argv[2],"w",zipfile.ZIP_DEFLATED) as z:\n for f in sorted(p.rglob("*")):\n  if f.is_file(): z.write(f, f.relative_to(p.parent).as_posix())';
for(const dir of [dsh,source]){const r=spawnSync('python',['-c',zipCode,dir,dir+'.zip'],{encoding:'utf8',windowsHide:true});if(r.status!==0)throw Error(r.stderr||r.error?.message);}
const tarCode='import tarfile,sys\nwith tarfile.open(sys.argv[2],"w:gz") as t: t.add(sys.argv[1],arcname="package")';
const r=spawnSync('python',['-c',tarCode,npm,path.join(release,'dsh-whale-notify-2.5.0.tgz')],{encoding:'utf8',windowsHide:true});if(r.status!==0)throw Error(r.stderr||r.error?.message);
const artifacts=fs.readdirSync(release).filter(n=>/\.(zip|tgz)$/.test(n));
fs.writeFileSync(path.join(release,'SHA256SUMS.txt'),artifacts.map(n=>createHash('sha256').update(fs.readFileSync(path.join(release,n))).digest('hex')+'  '+n).join('\n')+'\n');
fs.writeFileSync(path.join(output,'latest-release.json'),JSON.stringify({directory:release,artifacts},null,2));
console.log(JSON.stringify({directory:release,artifacts},null,2));
