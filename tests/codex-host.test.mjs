import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';
const root = resolve('.');
const session = '01a13567-1329-7381-bb41-6ce4f4d18c47';
const windows = { skip: process.platform !== 'win32' };

function fixture(callback) {
  const home = mkdtempSync(join(tmpdir(), 'whale-codex-host-'));
  try { callback(home); }
  finally {
    const child = relative(resolve(tmpdir()), resolve(home));
    assert(child.startsWith('whale-codex-host-') && !child.startsWith('..') && !isAbsolute(child));
    rmSync(home, { recursive: true, force: true });
  }
}
function powershell(script, args) {
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
    { encoding: 'utf8', timeout: 20000, windowsHide: true });
  assert.equal(result.status, 0, (result.error?.message || '') + result.stdout + result.stderr);
  return result;
}
function rows(directory, name, meta, records = []) {
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, name + '.jsonl'), [
    { timestamp: new Date().toISOString(), type: 'session_meta', payload: { id: session, cwd: 'E:\\Projects\\鲸鱼项目', source: 'cli', ...meta } },
    ...records.map(record => ({ timestamp: new Date().toISOString(), ...record })),
  ].map(record => JSON.stringify(record)).join('\n') + '\n');
}
function events(home) {
  const directory = join(home, 'host-events');
  return existsSync(directory) ? readdirSync(directory).map(name => JSON.parse(readFileSync(join(directory, name), 'utf8'))) : [];
}
function watch(home, sessions, ...extra) {
  return powershell(join(root, 'packages/desktop-pet/whale-codex.ps1'), ['-PetHome', home, '-SessionRoot', sessions, '-Once', ...extra]);
}

test('Codex host adapters forward only metadata and incremental UTF8 decoding preserves boundary characters', windows, () => fixture(home => {
  const run = powershell(join(root, 'tests/codex-host.test.ps1'), ['-TestHome', home]);
  assert.match(run.stdout, /PASS: \d+ Codex host assertions/);
}));

test('watcher -Once -Replay maps live work while suppressing prompt, output, reasoning and tool floods', windows, () => fixture(home => {
  const sessions = join(home, 'sessions');
  rows(sessions, 'real-thread', {}, [
    { type: 'event_msg', payload: { type: 'user_message', message: 'TOP_SECRET_PROMPT' } },
    { type: 'event_msg', payload: { type: 'task_started' } },
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', arguments: 'TOP_SECRET_ARGS' } },
    { type: 'response_item', payload: { type: 'custom_tool_call', name: 'apply_patch', input: 'TOP_SECRET_PATCH' } },
    { type: 'response_item', payload: { type: 'function_call_output', output: 'TOP_SECRET_OUTPUT' } },
    { type: 'response_item', payload: { type: 'reasoning', summary: 'TOP_SECRET_REASONING' } },
    { type: 'event_msg', payload: { type: 'task_complete', message: 'TOP_SECRET_COMPLETION' } },
    { type: 'response_item', payload: { type: 'function_call', name: 'tools.request_user_input', arguments: 'TOP_SECRET_OPTIONS' } },
  ]);
  watch(home, sessions, '-Replay');
  const output = events(home);
  assert.deepEqual(output.map(event => event.kind).sort(), ['completion', 'question', 'running', 'tool']);
  for (const event of output) { assert.equal(event.sid, session); assert.equal(event.host, 'codex'); assert.equal(event.note, '鲸鱼项目'); }
  assert.doesNotMatch(JSON.stringify(output), /TOP_SECRET/);
}));

test('watcher starts at EOF by default and does not replay earlier completions', windows, () => fixture(home => {
  const sessions = join(home, 'sessions');
  rows(sessions, 'finished-thread', {}, [{ type: 'event_msg', payload: { type: 'task_complete' } }]);
  watch(home, sessions);
  assert.deepEqual(events(home), []);
}));

test('watcher ignores subagent rollouts, invalid session identity, invalid JSON and stale work', windows, () => fixture(home => {
  const sessions = join(home, 'sessions');
  const complete = { type: 'event_msg', payload: { type: 'task_complete' } };
  rows(sessions, 'subagent', { source: { subagent: { parent_thread_id: session } } }, [complete]);
  rows(sessions, 'unsafe-id', { id: '../escape' }, [complete]);
  rows(sessions, 'stale-event', {}, [{ ...complete, timestamp: new Date(Date.now() - 180000).toISOString() }]);
  writeFileSync(join(sessions, 'bad-header.jsonl'), 'not JSON\n' + JSON.stringify(complete) + '\n');
  watch(home, sessions, '-Replay');
  assert.deepEqual(events(home), []);
}));

test('watcher respects explicit stop and DSH host choice without emitting events', windows, () => fixture(home => {
  const sessions = join(home, 'sessions');
  rows(sessions, 'real-thread', {}, [{ type: 'event_msg', payload: { type: 'task_complete' } }]);
  writeFileSync(join(home, 'control.json'), '{"stopped":true}');
  watch(home, sessions, '-Replay');
  assert.deepEqual(events(home), []);
  writeFileSync(join(home, 'control.json'), '{"stopped":false}');
  writeFileSync(join(home, 'pet-preferences.json'), '{"host":"dsh"}');
  watch(home, sessions, '-Replay');
  assert.deepEqual(events(home), []);
}));
