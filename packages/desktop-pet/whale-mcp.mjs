import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';

export const tools = [
  {name:'pet_status',description:'Read the local Codex desktop companion settings, current task status and growth statistics.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true}},
  {name:'pet_say',description:'Send a short supportive message to the user’s own desktop companion. Hidden or focused mode delays presentation.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:240}},required:['text'],additionalProperties:false}},
  {name:'pet_set_names',description:'Set the companion name and the fixed name it uses to address the user, when requested.',inputSchema:{type:'object',properties:{petName:{type:'string',minLength:1,maxLength:24},userName:{type:'string',minLength:1,maxLength:24}},additionalProperties:false}},
  {name:'pet_list_todos',description:'Read local to-do items saved with the desktop companion.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true}},
  {name:'pet_add_todo',description:'Queue a local to-do item for the companion. This does not start another Codex task.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:120}},required:['text'],additionalProperties:false}},
  {name:'pet_set_todo_done',description:'Mark an existing saved to-do as completed, or reopen it. Use the exact task id from pet_list_todos.',inputSchema:{type:'object',properties:{taskId:{type:'string',minLength:1,maxLength:80},done:{type:'boolean'}},required:['taskId','done'],additionalProperties:false}},
  {name:'pet_focus_status',description:'Read the saved focus session, its remaining seconds, paused state and completed-session count, including while the companion is offline.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true}},
  {name:'pet_focus',description:'Start a single focus session, 5–180 minutes, or use the saved duration.',inputSchema:{type:'object',properties:{minutes:{type:'integer',minimum:5,maximum:180}},additionalProperties:false}},
  {name:'pet_pause_focus',description:'Pause an active focus session without losing its remaining time.',inputSchema:{type:'object',properties:{},additionalProperties:false}},
  {name:'pet_resume_focus',description:'Resume a paused focus session with its saved remaining time.',inputSchema:{type:'object',properties:{},additionalProperties:false}},
  {name:'pet_cancel_focus',description:'Cancel the companion focus timer without counting it as completed.',inputSchema:{type:'object',properties:{},additionalProperties:false}},
  {name:'pet_list_reminders',description:'Read saved one-off reminders and their delivery status. This does not create or deliver a reminder.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true}},
  {name:'pet_remind',description:'Create a one-off local reminder; presentation is delayed while the companion is hidden or awaiting approval.',inputSchema:{type:'object',properties:{text:{type:'string',minLength:1,maxLength:120},minutes:{type:'integer',minimum:1,maximum:1440}},required:['text','minutes'],additionalProperties:false}},
  {name:'pet_news',description:'Read the cached headlines with original source links and timestamps. Does not fabricate or silently refresh news.',inputSchema:{type:'object',properties:{limit:{type:'integer',minimum:1,maximum:10}},additionalProperties:false},annotations:{readOnlyHint:true}},
  {name:'pet_refresh_news',description:'Request a background refresh of selected public RSS sources. A completed command receipt confirms only that refresh was requested or already running, not that news was fetched successfully; read pet_news for the actual feed status.',inputSchema:{type:'object',properties:{},additionalProperties:false}},
  {name:'pet_open_panel',description:'Open a requested companion panel: tasks, focus, settings, news or diagnostics. If offline, this explicit action starts the existing background service and opens the panel while keeping the floating pet hidden.',inputSchema:{type:'object',properties:{panel:{type:'string',enum:['tasks','focus','settings','news','diagnostics']}},required:['panel'],additionalProperties:false}},
  {name:'pet_command_result',description:'Read whether a previously queued companion command completed, failed, expired, is still queued, or no longer has a retained receipt. A queued response is not completion.',inputSchema:{type:'object',properties:{id:{type:'string',pattern:'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'}},required:['id'],additionalProperties:false},annotations:{readOnlyHint:true}}
];
const toolDefinitions = new Map(tools.map(tool=>[tool.name,tool]));
const commandTtlMs = 300000;
const maxMessageBytes = 2097152;

export function readJson(file, fallback = null) {
  try { const stat=fs.statSync(file); if(stat.size>1048576) return fallback; return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')); }
  catch {return fallback;}
}
// Valid JSON can still be null, an array or a primitive after a partial/manual
// data repair. Such files must not turn all read-only tools into TypeErrors.
function readObject(file) {
  const value=readJson(file);
  return value&&typeof value==='object'&&!Array.isArray(value)?value:{};
}
function companionState(petHome) {
  const control=readObject(path.join(petHome,'control.json'));
  const alive=readObject(path.join(petHome,'alive.json'));
  const stamp=Number(alive.at),age=Date.now()-stamp;
  const stopped=control.stopped===true||control.stopped==='true';
  return {online:!stopped&&Number.isFinite(stamp)&&stamp>0&&age>=-30000&&age<45000,stopped,lastSeenAt:alive.at||null};
}
export function focusStatus(data,now=Date.now()) {
  const saved=data&&typeof data==='object'?data:{};
  const completedCount=Number.isInteger(saved.focusCompletedCount)&&saved.focusCompletedCount>=0?saved.focusCompletedCount:0;
  const focus=saved.focus;
  const duration=focus?.minutes;
  if(!focus||!Number.isInteger(duration)||duration<5||duration>180)return {active:false,paused:false,minutes:null,remainingSeconds:0,until:null,completedCount};
  const paused=focus.paused===true;
  const until=paused?NaN:Date.parse(focus.until);
  const remaining=paused?focus.remainingSeconds:Math.ceil((until-now)/1000);
  if(!Number.isFinite(remaining)||remaining<0||paused&&!Number.isInteger(remaining))return {active:false,paused:false,minutes:null,remainingSeconds:0,until:null,completedCount};
  return {active:true,paused,minutes:duration,remainingSeconds:Math.max(0,Math.min(duration*60,remaining)),until:paused?null:focus.until,completedCount};
}
export function atomicJson(file, value) {
  fs.mkdirSync(path.dirname(file),{recursive:true});
  const temp=file+'.'+randomUUID()+'.tmp';
  try{fs.writeFileSync(temp,JSON.stringify(value),'utf8');fs.renameSync(temp,file);}
  finally{if(fs.existsSync(temp)) fs.unlinkSync(temp);}
}
export function ensureHostWatcher(petHome,spawnProcess=spawn) {
  if(process.platform!=='win32')return false;
  try{petHome=fs.realpathSync.native(petHome);}catch{}
  const p=readObject(path.join(petHome,'pet-preferences.json'));
  if(p.host==='dsh'||p.autoWakeOnHostStart===false||p.autoWakeOnHostStart==='false')return false;
  const watcher=path.join(petHome,'whale-host-watch.ps1');
  const nativeWatcher=path.join(petHome,'whale-host-watch.exe');
  if(!fs.existsSync(watcher)&&!fs.existsSync(nativeWatcher))return false;
  const heartbeat=readObject(path.join(petHome,'host-watch-alive.json'));
  const age=Date.now()-Number(heartbeat.at);
  if(Number.isFinite(age)&&age>=-30000&&age<45000&&Number.isInteger(heartbeat.pid)&&heartbeat.pid>0){
    try{process.kill(heartbeat.pid,0);return false;}catch{}
  }
  const exe=path.join(process.env.SystemRoot||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');
  const logError=error=>{try{const file=path.join(petHome,'host-bootstrap.log');if(fs.existsSync(file)&&fs.statSync(file).size>65536)fs.writeFileSync(file,'');fs.appendFileSync(file,`${new Date().toISOString()} ${String(error.message||error).slice(0,1000)}\n`);}catch{}};
  try{
    const native=fs.existsSync(nativeWatcher);
    const child=spawnProcess(native?nativeWatcher:exe,native?['--pet-home',petHome]:['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',watcher,'-PetHome',petHome],{windowsHide:true,detached:true,stdio:'ignore'});
    child.once('error',logError);child.unref();return true;
  }catch(error){logError(error);return false;}
}

// A connection can predate installation or outlive a failed monitor. Keep checking
// its heartbeat; this timer never starts Codex or directly shows a hidden pet.
export function maintainHostWatcher(petHome,{ensure=ensureHostWatcher,schedule=setInterval,cancel=clearInterval}={}) {
  ensure(petHome);
  const timer=schedule(()=>ensure(petHome),30000);timer.unref?.();
  return ()=>cancel(timer);
}
export function openCompanionPanel(petHome,panel,spawnProcess=spawn) {
  try{petHome=fs.realpathSync.native(petHome);}catch{}
  const launcher=path.join(petHome,'whale-pet-start.ps1');
  if(process.platform!=='win32'||!fs.existsSync(launcher))throw new Error('The companion is offline and its panel launcher is unavailable. Start the installed companion manually.');
  const exe=path.join(process.env.SystemRoot||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');
  const child=spawnProcess(exe,['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',launcher,'-SupportOnly','-OpenPanel',panel],{windowsHide:true,detached:true,stdio:'ignore'});
  child.once('error',error=>{try{fs.appendFileSync(path.join(petHome,'panel-launch.log'),`${new Date().toISOString()} ${String(error.message||error).slice(0,1000)}\n`);}catch{}});
  child.unref();
  return {opening:true,status:'requested',message:'Requested the existing background service and panel. The floating pet stays hidden. This is not confirmation that the panel has opened; use pet_status to check service availability.'};
}
function text(value,max) {
  if(typeof value!=='string'||!value.trim()||value.length>max||/[\x00-\x1f\x7f]/.test(value)) throw new Error('Please provide one non-empty line within the allowed length.');
  return value.trim();
}
function minutes(value,min,max) {
  if(!Number.isInteger(value)||value<min||value>max) throw new Error(`Minutes must be an integer between ${min} and ${max}.`);
  return value;
}
export function callTool(petHome,name,args={},options={}) {
  if(!args||typeof args!=='object'||Array.isArray(args)) throw new Error('Object arguments required.');
  const definition=toolDefinitions.get(name);
  if(!definition)throw new Error('Unknown companion tool.');
  if(Object.keys(args).some(key=>!Object.hasOwn(definition.inputSchema.properties,key)))throw new Error('Unknown companion argument.');
  const prefs=()=>readObject(path.join(petHome,'pet-preferences.json'));
  const queue=(action,data={})=>{
    const state=companionState(petHome);
    if(state.stopped) throw new Error('The user exited the companion. Start it manually before adding commands.');
    if(!state.online) throw new Error('The companion is offline. No command was queued and no program was started.');
    const folder=path.join(petHome,'commands');
    if(fs.existsSync(folder)&&fs.readdirSync(folder).filter(f=>f.endsWith('.json')).length>=100) throw new Error('Companion command inbox is full.');
    const id=randomUUID(),at=Date.now();atomicJson(path.join(folder,id+'.json'),{id,at,action,...data});
    return {queued:true,id,expiresAt:at+commandTtlMs,message:'Queued locally, not yet completed. Commands expire after five minutes; hidden/focus mode delays companion speech. Use pet_command_result to check completion.'};
  };
  switch(name){
    case 'pet_status':{const p=prefs();const s=readObject(path.join(petHome,'state.json'));return {preferences:p,stats:readObject(path.join(petHome,'pet-stats.json')),host:s.host||p.host||'codex',status:s.kind||'idle',sessionId:s.sid||null,updatedAt:s.at||null,...companionState(petHome),hidden:fs.existsSync(path.join(petHome,'hidden.json'))};}
    case 'pet_say':return queue('say',{text:text(args.text,240)});
    case 'pet_set_names':{const names={};if(args.petName!==undefined)names.petName=text(args.petName,24);if(args.userName!==undefined)names.userName=text(args.userName,24);if(!Object.keys(names).length)throw new Error('At least one name is required.');return queue('set_names',names);}
    case 'pet_list_todos':{const data=readObject(path.join(petHome,'companion-data.json'));return {tasks:Array.isArray(data.tasks)?data.tasks:[]};}
    case 'pet_add_todo':return queue('add_todo',{text:text(args.text,120)});
    case 'pet_set_todo_done':{const taskId=text(args.taskId,80);if(typeof args.done!=='boolean')throw new Error('done must be a boolean.');return queue('set_todo_done',{taskId,done:args.done});}
    case 'pet_focus_status':return focusStatus(readObject(path.join(petHome,'companion-data.json')));
    case 'pet_focus':return queue('focus',args.minutes===undefined?{}:{minutes:minutes(args.minutes,5,180)});
    case 'pet_pause_focus':return queue('pause_focus');
    case 'pet_resume_focus':return queue('resume_focus');
    case 'pet_cancel_focus':return queue('cancel_focus');
    case 'pet_list_reminders':{const data=readObject(path.join(petHome,'companion-data.json'));return {reminders:Array.isArray(data.reminders)?data.reminders:[]};}
    case 'pet_remind':return queue('remind',{text:text(args.text,120),minutes:minutes(args.minutes,1,1440)});
    case 'pet_news':{const n=readObject(path.join(petHome,'news.json'));const limit=args.limit===undefined?5:minutes(args.limit,1,10);return {status:n.status||'empty',lastAttemptAt:n.lastAttemptAt||null,fetchedAt:n.lastFetchedAt||n.fetchedAt||null,items:Array.isArray(n.items)?n.items.slice(0,limit):[],sources:Array.isArray(n.sources)?n.sources:[],errors:Array.isArray(n.errors)?n.errors:[]};}
    case 'pet_refresh_news':return queue('refresh_news');
    case 'pet_open_panel':{if(!['tasks','focus','settings','news','diagnostics'].includes(args.panel))throw new Error('Invalid panel. Choose tasks, focus, settings, news or diagnostics.');return companionState(petHome).online?queue('open_panel',{panel:args.panel}):openCompanionPanel(petHome,args.panel,options.spawnProcess);}
    case 'pet_command_result':{
      if(typeof args.id!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(args.id))throw new Error('Invalid command id.');
      const receiptFile=path.join(petHome,'command-results',args.id+'.json');
      const receipt=readObject(receiptFile);
      if(receipt.id===args.id&&['completed','failed'].includes(receipt.status))return receipt;
      const command=readObject(path.join(petHome,'commands',args.id+'.json'));
      if(command.id!==args.id){
        // The worker writes its receipt before deleting the inbox entry. It may
        // have completed between the first receipt read and this inbox read.
        const finished=readObject(receiptFile);
        if(finished.id===args.id&&['completed','failed'].includes(finished.status))return finished;
        return {id:args.id,pending:false,status:'unknown',message:'No queued command or retained receipt was found. Nothing is confirmed as completed.'};
      }
      const at=Number(command.at),expiresAt=at+commandTtlMs;
      if(!Number.isFinite(at)||at<=0||at>Date.now()+30000)return {id:args.id,pending:false,status:'invalid',message:'The queued command has an invalid timestamp. Nothing is confirmed as completed.'};
      if(!Number.isFinite(expiresAt)||Date.now()>expiresAt)return {id:args.id,pending:false,status:'expired',expiresAt:Number.isFinite(expiresAt)?expiresAt:null,message:'The queued command expired before completion. It must be requested again.'};
      return {id:args.id,pending:true,status:'queued',expiresAt,...companionState(petHome)};
    }
    default:throw new Error('Unknown companion tool.');
  }
}

// Enforce the limit per protocol frame and discard a rejected frame through its
// newline. Resetting only the buffer would allow its next chunk to execute as a
// fresh command, even though it belonged to a rejected oversized message.
export function createLineReader(onLine,onTooLarge,limit=maxMessageBytes) {
  let pending='',bytes=0,discarding=false;
  return chunk=>{
    let start=0;
    while(start<chunk.length){
      const end=chunk.indexOf('\n',start);
      const terminated=end>=0;
      const fragment=chunk.slice(start,terminated?end:chunk.length);
      start=terminated?end+1:chunk.length;
      if(discarding){if(terminated)discarding=false;continue;}
      const fragmentBytes=Buffer.byteLength(fragment,'utf8');
      if(bytes+fragmentBytes>limit){pending='';bytes=0;discarding=!terminated;onTooLarge();continue;}
      pending+=fragment;bytes+=fragmentBytes;
      if(terminated){const line=pending;pending='';bytes=0;if(line.trim())onLine(line);}
    }
  };
}

export function startServer(petHome) {
  try{petHome=fs.realpathSync.native(petHome);}catch{}
  const stopWatcherMaintenance=maintainHostWatcher(petHome);
  process.stdin.once('end',stopWatcherMaintenance);
  process.stdin.once('close',stopWatcherMaintenance);
  process.stdin.setEncoding('utf8');
  const send=(id,result,error)=>process.stdout.write(JSON.stringify(error?{jsonrpc:'2.0',id,error}:{jsonrpc:'2.0',id,result})+'\n');
  process.stdin.on('data',createLineReader(line=>{
      let request;try{request=JSON.parse(line);}catch{send(null,null,{code:-32700,message:'Invalid JSON'});return;}
      if(!request||typeof request!=='object'||Array.isArray(request)||request.jsonrpc!=='2.0'||typeof request.method!=='string'||request.id!==undefined&&request.id!==null&&typeof request.id!=='string'&&(typeof request.id!=='number'||!Number.isFinite(request.id))){send(null,null,{code:-32600,message:'Invalid request'});return;}
      if(request.id===undefined)return;
      if(request.params!==undefined&&(!request.params||typeof request.params!=='object'||Array.isArray(request.params))){send(request.id,null,{code:-32602,message:'Object params required'});return;}
      try{
        if(request.method==='initialize')send(request.id,{protocolVersion:request.params?.protocolVersion||'2024-11-05',capabilities:{tools:{listChanged:false}},serverInfo:{name:'codex-whale-companion',version:'2.4.0'}});
        else if(request.method==='ping')send(request.id,{});
        else if(request.method==='tools/list')send(request.id,{tools});
        else if(request.method==='tools/call'){
          try{const value=callTool(petHome,request.params?.name,request.params?.arguments);send(request.id,{content:[{type:'text',text:JSON.stringify(value)}],isError:false});}
          catch(error){send(request.id,{content:[{type:'text',text:error.message}],isError:true});}
        }else send(request.id,null,{code:-32601,message:'Method not found'});
      }catch(error){send(request.id,null,{code:-32603,message:error.message});}
  },()=>send(null,null,{code:-32600,message:'Message too large'})));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const i=process.argv.indexOf('--pet-home');
  const home=i>=0?process.argv[i+1]:path.join(process.env.LOCALAPPDATA||process.env.USERPROFILE,'CodexWhalePet');
  startServer(path.resolve(home));
}
