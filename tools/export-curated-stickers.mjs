// Export original transparent PNGs without captions/backgrounds; preview is separate.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const root=path.resolve(import.meta.dirname,'..');
let sharp;
for(const base of [root,path.dirname(process.execPath),process.env.USERPROFILE&&path.join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node')].filter(Boolean)){
  try{sharp=createRequire(path.join(base,'sticker-runtime.cjs'))('sharp');break}catch{}
}
if(!sharp)throw new Error('The bundled sharp image runtime is required to build the preview.');
const entries=JSON.parse(fs.readFileSync(path.join(root,'tools/sticker-v3.json'),'utf8'));
const output=path.join(root,'鲸鱼娘表情包','清爽新版');fs.mkdirSync(output,{recursive:true});
const layers=[],report=[];
const escape=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
for(let i=0;i<entries.length;i++){
  const entry=entries[i],source=path.join(root,'packages/desktop-pet/assets',entry.id+'.png');
  const {width,height,hasAlpha}=await sharp(source).metadata();
  const {data,info}=await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let transparent=0;for(let p=3;p<data.length;p+=info.channels)if(data[p]===0)transparent++;
  const ratio=transparent/(info.width*info.height);
  if(!hasAlpha||ratio<0.1||ratio>0.95)throw new Error('Invalid transparent silhouette: '+entry.id);
  const filename=entry.id+'-'+entry.caption+'.png';fs.copyFileSync(source,path.join(output,filename));
  const art=await sharp(source).resize(220,240,{fit:'inside'}).png().toBuffer();
  const tile=await sharp({create:{width:260,height:290,channels:4,background:'#F2F8FA'}})
    .composite([{input:art,gravity:'north'},{input:Buffer.from(`<svg width="260" height="290"><text x="130" y="273" text-anchor="middle" font-family="Microsoft YaHei, sans-serif" font-size="17" fill="#183B48">${escape(entry.caption)}</text></svg>`),top:0,left:0}]).png().toBuffer();
  layers.push({input:tile,top:Math.floor(i/4)*290,left:i%4*260});
  report.push({id:entry.id,caption:entry.caption,file:filename,width,height,transparentRatio:Number(ratio.toFixed(3))});
}
const preview=path.join(root,'out/curated-stickers-v3.png');fs.mkdirSync(path.dirname(preview),{recursive:true});
await sharp({create:{width:1040,height:Math.ceil(entries.length/4)*290,channels:4,background:'#F2F8FA'}}).composite(layers).png().toFile(preview);
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify({format:'Original transparent PNG, no text or background',stickers:report},null,2));
fs.writeFileSync(path.join(root,'out/curated-stickers-v3-report.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({count:entries.length,output,preview,transparentRatios:report.map(r=>r.transparentRatio)}));
