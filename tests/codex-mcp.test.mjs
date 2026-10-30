import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { tools, readJson, atomicJson, callTool, focusStatus, createLineReader, openCompanionPanel } from '../packages/desktop-pet/whale-mcp.mjs';

const workspace = fileURLToPath(new URL('../', import.meta.url));
const testRoot = path.join(workspace, '.diag');
const serverFile = fileURLToPath(new URL('../packages/desktop-pet/whale-mcp.mjs', import.meta.url));

function fixture(t, online = true) {
  const home = path.join(testRoot, 'mcp-test-' + randomUUID());
  fs.mkdirSync(home, { recursive: true });
  t.after(() => {
    const target = path.resolve(home);
    assert.equal(path.dirname(target), path.resolve(testRoot));
    assert.match(path.basename(target), /^mcp-test-[a-f\d-]+$/);
    fs.rmSync(target, { recursive: true, force: true });
  });
  if (online) atomicJson(path.join(home, 'alive.json'), { at: Date.now(), pid: 12345 });
  return home;
}

function commands(home) {
  const dir = path.join(home, 'commands');
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter(name => name.endsWith('.json')) : [];
}

const validCalls = [
  ['pet_say', { text: '一起慢慢来' }, 'say'],
  ['pet_set_names', { petName: '小鲸', userName: '老板' }, 'set_names'],
  ['pet_add_todo', { text: '给植物浇水' }, 'add_todo'],
  ['pet_set_todo_done', { taskId: 'task-123', done: true }, 'set_todo_done'],
  ['pet_focus', { minutes: 25 }, 'focus'],
  ['pet_pause_focus', {}, 'pause_focus'],
  ['pet_resume_focus', {}, 'resume_focus'],
  ['pet_cancel_focus', {}, 'cancel_focus'],
  ['pet_remind', { text: '喝水', minutes: 10 }, 'remind'],
  ['pet_refresh_news', {}, 'refresh_news'],
  ['pet_open_panel', { panel: 'tasks' }, 'open_panel'],
];

test('tool declarations and implementations enforce the same argument schema', t => {
  const home = fixture(t);
  assert.equal(new Set(tools.map(tool => tool.name)).size, tools.length);
  for (const tool of tools) {
    assert.equal(tool.inputSchema.type, 'object');
    assert.equal(tool.inputSchema.additionalProperties, false);
    const args = validCalls.find(([name]) => name === tool.name)?.[1]
      ?? (tool.name === 'pet_command_result' ? { id: randomUUID() } : {});
    assert.throws(() => callTool(home, tool.name, { ...args, unexpected: true }), /argument|property|unknown|unexpected|field/i, tool.name + ' rejects undeclared fields');
    for (const badArgs of [null, [], 'text', 42, true]) {
      assert.throws(() => callTool(home, tool.name, badArgs), /argument|object/i, tool.name + ' rejects non-object arguments');
    }
  }
  assert.equal(commands(home).length, 0);
  assert.throws(() => callTool(home, 'does_not_exist'), /unknown/i);
});

test('each mutable tool validates text, names, reminder duration and focus duration', t => {
  const home = fixture(t);
  for (const [tool, field, max] of [['pet_say', 'text', 240], ['pet_add_todo', 'text', 120], ['pet_remind', 'text', 120], ['pet_set_names', 'petName', 24], ['pet_set_names', 'userName', 24]]) {
    for (const badText of ['', '  ', 42, null, 'x'.repeat(max + 1), 'one\ntwo', 'one\rtwo', 'one\ttwo', 'nul\u0000']) {
      const args = tool === 'pet_remind' ? { text: 'valid', minutes: 10 } : {};
      args[field] = badText;
      assert.throws(() => callTool(home, tool, args), /line|length|name|string|empty/i, tool + ' ' + field);
    }
  }
  assert.throws(() => callTool(home, 'pet_set_names', {}), /name|required/i);
  for (const taskId of ['', ' ', null, 1, 'x'.repeat(81), 'a\nb']) assert.throws(() => callTool(home, 'pet_set_todo_done', {taskId,done:true}), /line|length/i);
  for (const done of [undefined, null, 1, 0, 'true', 'false']) assert.throws(() => callTool(home, 'pet_set_todo_done', {taskId:'task-123',done}), /boolean/i);
  for (const panel of [undefined, null, '', 'pet', '../settings', true]) assert.throws(() => callTool(home, 'pet_open_panel', {panel}), /panel/i);
  for (const duration of [4, 181, 10.5, '25', NaN, Infinity, null, false]) {
    assert.throws(() => callTool(home, 'pet_focus', { minutes: duration }), /integer|minutes/i);
  }
  for (const duration of [0, 1441, 10.5, '25', NaN, Infinity, null, false, undefined]) {
    assert.throws(() => callTool(home, 'pet_remind', { text: '喝水', minutes: duration }), /integer|minutes/i);
  }
  assert.equal(commands(home).length, 0, 'invalid input never enters the command inbox');
  for (const [name, args] of [['pet_focus', {}], ['pet_focus', { minutes: 5 }], ['pet_focus', { minutes: 180 }], ['pet_remind', { text: '喝水', minutes: 1 }], ['pet_remind', { text: '喝水', minutes: 1440 }], ['pet_set_names', { petName: '小鲸' }], ['pet_set_names', { userName: '老板' }], ['pet_say', { text: 'x'.repeat(240) }]]) {
    assert.equal(callTool(home, name, args).queued, true, 'accepted boundary: ' + name);
  }
});

test('offline, stopped, stale and malformed heartbeat states never queue or launch anything', t => {
  const home = fixture(t, false);
  for (const heartbeat of [null, {}, { at: Date.now() - 45001 }, { at: 'not-a-date' }, { at: -1 }, { at: Date.now() + 600000 }, { at: Infinity }]) {
    if (heartbeat) atomicJson(path.join(home, 'alive.json'), heartbeat);
    else fs.rmSync(path.join(home, 'alive.json'), { force: true });
    for (const [name, args] of validCalls) {
      assert.throws(() => callTool(home, name, args), /offline|heartbeat|alive/i, name);
    }
    assert.deepEqual(commands(home), []);
    assert.equal(fs.existsSync(path.join(home, 'commands')), false);
    assert.equal(fs.existsSync(path.join(home, 'control.json')), false, 'offline tooling does not attempt a restart');
  }
  atomicJson(path.join(home, 'alive.json'), { at: Date.now() });
  atomicJson(path.join(home, 'control.json'), { stopped: true });
  for (const [name, args] of validCalls) assert.throws(() => callTool(home, name, args), /exited|manually|stopped/i);
  assert.equal(fs.existsSync(path.join(home, 'commands')), false);
  assert.deepEqual(fs.readdirSync(home).sort(), ['alive.json', 'control.json']);
});

test('valid operations atomically queue distinct commands and expose honest completion states', t => {
  const home = fixture(t);
  const ids = [];
  for (const [name, args, action] of validCalls) {
    const started = Date.now();
    const result = callTool(home, name, args);
    assert.equal(result.queued, true);
    assert.ok(result.expiresAt >= started + 300000 && result.expiresAt <= Date.now() + 300000);
    assert.match(result.id, /^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/);
    const queued = readJson(path.join(home, 'commands', result.id + '.json'));
    assert.equal(queued.id, result.id);
    assert.equal(queued.action, action);
    assert.ok(queued.at >= started && queued.at <= Date.now());
    for (const [key, value] of Object.entries(args)) assert.equal(queued[key], value);
    const pending = callTool(home, 'pet_command_result', { id: result.id });
    assert.equal(pending.id, result.id); assert.equal(pending.pending, true);
    assert.equal(pending.status,'queued'); assert.equal(pending.online,true);
    const completed = { id: result.id, status: 'completed', at: Date.now(), error: '' };
    atomicJson(path.join(home, 'command-results', result.id + '.json'), completed);
    assert.deepEqual(callTool(home, 'pet_command_result', { id: result.id }), completed);
    ids.push(result.id);
  }
  assert.equal(new Set(ids).size, validCalls.length);
  assert.equal(commands(home).length, validCalls.length);
  assert.ok(fs.readdirSync(path.join(home, 'commands')).every(name => name.endsWith('.json')), 'no temporary files left behind');
  for (const id of ['', '../alive.json', '..\\alive.json', 'C:\\file', 42, 'x'.repeat(36)]) {
    assert.throws(() => callTool(home, 'pet_command_result', { id }), /invalid|id/i);
  }
});

test('command result distinguishes never-existing, expired, offline pending and failed operations without modifying queues', t => {
  const home=fixture(t);
  const missing=randomUUID();
  assert.equal(callTool(home,'pet_command_result',{id:missing}).status,'unknown');
  assert.equal(callTool(home,'pet_command_result',{id:missing}).pending,false);
  const result=callTool(home,'pet_say',{text:'hello'});
  fs.rmSync(path.join(home,'alive.json'));
  const pending=callTool(home,'pet_command_result',{id:result.id});
  assert.equal(pending.pending,true);assert.equal(pending.online,false);
  const commandFile=path.join(home,'commands',result.id+'.json');
  const command=readJson(commandFile);command.at=Date.now()-300001;atomicJson(commandFile,command);
  const expired=callTool(home,'pet_command_result',{id:result.id});
  assert.equal(expired.status,'expired');assert.equal(expired.pending,false);
  assert.ok(fs.existsSync(commandFile),'reading does not delete expired queued work');
  atomicJson(path.join(home,'command-results',result.id+'.json'),{id:missing,status:'completed'});
  assert.equal(callTool(home,'pet_command_result',{id:result.id}).status,'expired','a mismatched receipt never reports success');
  const failed={id:result.id,status:'failed',error:'提醒已满',at:Date.now()};atomicJson(path.join(home,'command-results',result.id+'.json'),failed);
  assert.deepEqual(callTool(home,'pet_command_result',{id:result.id}),failed);
});

test('focus and reminder read tools report persisted countdown and paused time while offline', t => {
  const home=fixture(t,false),now=Date.now();
  assert.deepEqual(focusStatus({},now),{active:false,paused:false,minutes:null,remainingSeconds:0,until:null,completedCount:0});
  const running={focus:{minutes:25,until:new Date(now+90000).toISOString()},focusCompletedCount:7};
  assert.deepEqual(focusStatus(running,now),{active:true,paused:false,minutes:25,remainingSeconds:90,until:running.focus.until,completedCount:7});
  const paused={focus:{minutes:25,paused:true,remainingSeconds:100},focusCompletedCount:7};
  atomicJson(path.join(home,'companion-data.json'),paused);
  assert.deepEqual(callTool(home,'pet_focus_status'),{active:true,paused:true,minutes:25,remainingSeconds:100,until:null,completedCount:7});
  const reminders=[{id:'r1',text:'喝水',notified:false,dueAt:new Date(now+600000).toISOString()},{id:'r2',text:'已提醒',notified:true,dueAt:new Date(now-600000).toISOString()}];
  atomicJson(path.join(home,'companion-data.json'),{...running,reminders});
  assert.deepEqual(callTool(home,'pet_list_reminders'),{reminders});
  for(const focus of [null,{minutes:1},{minutes:'25'},{minutes:25,until:'invalid'},{minutes:25,paused:true,remainingSeconds:-1},{minutes:25,paused:true,remainingSeconds:'100'}])assert.equal(focusStatus({focus},now).active,false);
  assert.equal(fs.existsSync(path.join(home,'commands')),false);
});

test('valid primitive or null saved JSON never breaks read tools or incorrectly marks stopped false as exited', t => {
  const home=fixture(t,false);
  for(const value of [null,[],42,'corrupt']){
    for(const file of ['pet-preferences.json','pet-stats.json','state.json','control.json','alive.json','companion-data.json','news.json'])atomicJson(path.join(home,file),value);
    assert.equal(callTool(home,'pet_status').online,false);
    assert.deepEqual(callTool(home,'pet_list_todos'),{tasks:[]});
    assert.deepEqual(callTool(home,'pet_list_reminders'),{reminders:[]});
    assert.equal(callTool(home,'pet_focus_status').active,false);
    assert.deepEqual(callTool(home,'pet_news').items,[]);
  }
  atomicJson(path.join(home,'control.json'),{stopped:'false'});atomicJson(path.join(home,'alive.json'),{at:Date.now()});
  assert.equal(callTool(home,'pet_status').stopped,false);
  assert.equal(callTool(home,'pet_say',{text:'hello'}).queued,true);
});

test('only an explicitly requested offline panel starts the hidden support service using the existing launcher', t => {
  const home=fixture(t,false),calls=[];
  fs.writeFileSync(path.join(home,'whale-pet-start.ps1'),'# fixture');
  atomicJson(path.join(home,'control.json'),{stopped:true});
  const spawnProcess=(exe,args,options)=>{calls.push({exe,args,options});return {once(){},unref(){}}};
  const result=callTool(home,'pet_open_panel',{panel:'diagnostics'},{spawnProcess});
  assert.equal(result.opening,true);assert.equal(result.status,'requested');assert.equal(result.queued,undefined);
  assert.equal(calls.length,1);assert.match(calls[0].exe,/powershell\.exe$/i);
  assert.deepEqual(calls[0].args.slice(-5),['-File',path.join(home,'whale-pet-start.ps1'),'-SupportOnly','-OpenPanel','diagnostics'],'launcher opens only the requested panel');
  assert.equal(calls[0].options.windowsHide,true);assert.equal(calls[0].options.stdio,'ignore');
  for(const [name,args] of validCalls.filter(([name])=>name!=='pet_open_panel'))assert.throws(()=>callTool(home,name,args,{spawnProcess}),/exited|stopped|manually/i);
  assert.equal(calls.length,1,'ordinary writes do not revive an exited companion');
  assert.equal(fs.existsSync(path.join(home,'commands')),false);
  assert.throws(()=>openCompanionPanel(home,'tasks',()=>{throw new Error('launch failed')}),/launch failed/);
});

test('inbox backpressure refuses the 101st command and never silently deletes pending work', t => {
  const home = fixture(t);
  const dir = path.join(home, 'commands'); fs.mkdirSync(dir);
  for (let i = 0; i < 99; i++) atomicJson(path.join(dir, randomUUID() + '.json'), { at: Date.now() - 600000, action: 'say', text: 'expired' });
  fs.writeFileSync(path.join(dir, 'unrelated.txt'), 'kept');
  const last = callTool(home, 'pet_say', { text: 'last free slot' });
  assert.equal(last.queued, true); assert.equal(commands(home).length, 100);
  assert.throws(() => callTool(home, 'pet_add_todo', { text: 'too many' }), /inbox|full/i);
  assert.equal(commands(home).length, 100);
  assert.equal(fs.readFileSync(path.join(dir, 'unrelated.txt'), 'utf8'), 'kept');
});

test('readJson accepts UTF-8 BOM and the exact size limit but rejects corrupt or oversized files', t => {
  const home = fixture(t, false); const file = path.join(home, 'fixture.json');
  fs.writeFileSync(file, '\uFEFF{"name":"小鲸"}', 'utf8');
  assert.deepEqual(readJson(file), { name: '小鲸' });
  fs.writeFileSync(file, '"' + 'x'.repeat(1048574) + '"');
  assert.equal(fs.statSync(file).size, 1048576);
  assert.equal(readJson(file).length, 1048574);
  fs.appendFileSync(file, ' ');
  assert.deepEqual(readJson(file, { fallback: true }), { fallback: true });
  fs.writeFileSync(file, '{broken'); assert.equal(readJson(file, 'safe'), 'safe');
  assert.equal(readJson(path.join(home, 'missing.json'), 'missing'), 'missing');
  atomicJson(file, { version: 1 }); atomicJson(file, { version: 2 });
  assert.deepEqual(readJson(file), { version: 2 });
  assert.ok(!fs.readdirSync(home).some(name => name.endsWith('.tmp')));
});

test('read-only tools report actual saved status, todos and cached news without changing files', t => {
  const home = fixture(t, false);
  const preferences = { petName: '小鲸', userName: '老板', host: 'codex' };
  const stats = { level: 6, pats: 25 };
  const state = { host: 'codex', kind: 'tool', sid: 'session-123', at: 123456789 };
  const tasks = [{ id: 'todo-1', text: '吃饭', done: false }, { id: 'todo-2', text: '休息', done: true }];
  atomicJson(path.join(home, 'pet-preferences.json'), preferences);
  atomicJson(path.join(home, 'pet-stats.json'), stats);
  atomicJson(path.join(home, 'state.json'), state);
  atomicJson(path.join(home, 'companion-data.json'), { tasks });
  const items = Array.from({ length: 12 }, (_, i) => ({ id: 'headline-' + i, title: '真实缓存标题 ' + i, url: 'https://news.mit.edu/2026/' + i, source: 'MIT News', publishedAt: '2026-10-13T09:00:00+00:00' }));
  const news = { status: 'offline', lastFetchedAt: '2026-10-13T10:00:00+00:00', lastAttemptAt: '2026-10-14T10:00:00+00:00', sources: [{ id: 'mit-ai', ok: false, message: '来源暂时不可用，已保留缓存' }], items };
  atomicJson(path.join(home, 'news.json'), news);
  const before = fs.readdirSync(home).sort();
  assert.deepEqual(callTool(home, 'pet_status'), { preferences, stats, host: 'codex', status: 'tool', sessionId: 'session-123', updatedAt: 123456789, online:false,stopped:false,hidden:false,lastSeenAt:null });
  assert.deepEqual(callTool(home, 'pet_list_todos'), { tasks });
  const cached = callTool(home, 'pet_news');
  assert.equal(cached.fetchedAt, news.lastFetchedAt);
  assert.equal(cached.status, 'offline', 'offline cache state is visible to Codex');
  assert.equal(cached.lastAttemptAt, news.lastAttemptAt);
  assert.deepEqual(cached.sources, news.sources);
  assert.deepEqual(cached.items, items.slice(0, 5));
  assert.deepEqual(callTool(home, 'pet_news', { limit: 1 }).items, items.slice(0, 1));
  assert.equal(callTool(home, 'pet_news', { limit: 10 }).items.length, 10);
  for (const limit of [0, 11, 1.5, '5', null, false]) assert.throws(() => callTool(home, 'pet_news', { limit }), /integer|limit|minutes/i);
  assert.deepEqual(fs.readdirSync(home).sort(), before);
  assert.equal(fs.existsSync(path.join(home, 'commands')), false);
});

test('stdio initializes, lists and calls tools with JSON-only output and silent notifications', { timeout: 15000 }, async t => {
  const home = fixture(t, false);
  const child = spawn(process.execPath, [serverFile, '--pet-home', home], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  t.after(() => { if (!child.killed) child.kill(); });
  let stdout = '', stderr = '';
  child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
  child.stdout.on('data', chunk => { stdout += chunk; }); child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdin.end([
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'test', version: '1' } } },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/list' },
    { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'pet_status', arguments: {} } },
    { jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'pet_say', arguments: { text: 'offline request' } } },
    { jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'pet_say', arguments: { text: 'hello', extra: true } } },
    { jsonrpc: '2.0', id: 6, method: 'ping' },
    { jsonrpc: '2.0', id: 7, method: 'does-not-exist' },
  ].map(value => JSON.stringify(value)).join('\n') + '\n');
  const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); });
  assert.equal(code, 0, stderr);
  assert.equal(stderr, '', 'no debug logs or local file paths leaked');
  const lines = stdout.trim().split('\n'); assert.equal(lines.length, 7);
  const responses = lines.map(line => JSON.parse(line));
  for (const response of responses) assert.equal(response.jsonrpc, '2.0');
  assert.equal(responses[0].result.protocolVersion, '2025-03-26');
  assert.equal(responses[0].result.serverInfo.name, 'codex-whale-companion');
  assert.deepEqual(responses[1].result.tools.map(tool => tool.name), tools.map(tool => tool.name));
  assert.equal(JSON.parse(responses[2].result.content[0].text).host, 'codex');
  assert.equal(responses[3].result.isError, true); assert.match(responses[3].result.content[0].text, /offline/i);
  assert.equal(responses[4].result.isError, true);
  assert.deepEqual(responses[5].result, {});
  assert.equal(responses[6].error.code, -32601);
  assert.equal(fs.existsSync(path.join(home, 'commands')), false);
});

test('malformed stdio requests are rejected and a following valid request still works', { timeout: 15000 }, t => {
  const home = fixture(t, false);
  const input = ['{bad-json}', 'null', '[]', '42', JSON.stringify({ id: 1, method: 'ping' }), JSON.stringify({ jsonrpc: '2.0', id: 2, method: 7 }), JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'ping' })].join('\n') + '\n';
  const result = spawnSync(process.execPath, [serverFile, '--pet-home', home], { input, encoding: 'utf8', windowsHide: true, timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  const responses = result.stdout.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(responses.length, 7);
  assert.equal(responses[0].error.code, -32700);
  for (const response of responses.slice(1, -1)) assert.equal(response.error.code, -32600);
  assert.deepEqual(responses.at(-1), { jsonrpc: '2.0', id: 3, result: {} });
});

test('stdio rejects oversized input without executing queued tool requests', { timeout: 15000 }, t => {
  const home = fixture(t);
  const result = spawnSync(process.execPath, [serverFile, '--pet-home', home], { input: ' '.repeat(2097153), encoding: 'utf8', windowsHide: true, timeout: 10000, maxBuffer: 1048576 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  const response = JSON.parse(result.stdout.trim());
  assert.equal(response.error.code, -32600);
  assert.match(response.error.message, /large/i);
  assert.deepEqual(commands(home), []);
});

test('protocol framing limits UTF-8 bytes and discards every chunk of a rejected line through its delimiter', () => {
  const lines=[],errors=[];
  const read=createLineReader(line=>lines.push(line),()=>errors.push('large'),8);
  read('x'.repeat(9));
  read('tail that looks like a new command');
  read('\n{"x":1}\n');
  assert.deepEqual(errors,['large']);assert.deepEqual(lines,['{"x":1}']);
  read('鲸鲸鲸');read('\n');
  assert.equal(errors.length,2,'three CJK characters occupy nine UTF-8 bytes');
  read('{"x":1}\n'.repeat(100));
  assert.equal(lines.length,101,'a batch of small messages is limited per line, not per whole batch');
});

test('stdio rejects object ids and invalid params while allowing the next request', {timeout:15000},t=>{
  const home=fixture(t,false);
  const requests=[{jsonrpc:'2.0',id:{unexpected:true},method:'ping'},{jsonrpc:'2.0',id:1,method:'tools/list',params:[]},{jsonrpc:'2.0',id:2,method:'tools/call',params:'bad'},{jsonrpc:'2.0',id:3,method:'ping'}];
  const result=spawnSync(process.execPath,[serverFile,'--pet-home',home],{input:requests.map(request=>JSON.stringify(request)).join('\n')+'\n',encoding:'utf8',windowsHide:true,timeout:10000});
  assert.equal(result.status,0,result.stderr);
  const responses=result.stdout.trim().split('\n').map(line=>JSON.parse(line));
  assert.equal(responses[0].error.code,-32600);
  assert.equal(responses[1].error.code,-32602);assert.equal(responses[2].error.code,-32602);
  assert.deepEqual(responses[3],{jsonrpc:'2.0',id:3,result:{}});
});
