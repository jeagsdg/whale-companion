import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { apply } from '../packages/dsh-whale-notify/lib/notify.js';

function harness(config = {}, spawnDone = () => Promise.resolve({ exitCode: 0 })) {
  const handlers = new Map(), routes = new Map(), cleanups = [], spawns = [];
  const ctx = {
    get(name) {
      if (name === 'subprocess') return { spawn(options) { spawns.push(options); return { done: spawnDone(options) }; } };
      if (name === 'webServer') return { register(route) { routes.set(route.path, route.handler); return () => routes.delete(route.path); } };
      if (name === 'sessions') return { list: () => [] };
      return undefined;
    },
    on(name, handler) { handlers.set(name, handler); return () => handlers.delete(name); },
    effect(setup) { const cleanup = setup(); if (typeof cleanup === 'function') cleanups.push(cleanup); },
  };
  apply(ctx, { debug: false, greeting: false, minGapMs: 0, settleMs: 5, recheckMs: 20, minTurnMs: 0, ...config });
  function route(path, method = 'GET', body, since = 0, handler = routes.get(path)) {
    const req = new EventEmitter();
    Object.assign(req, { headers: { host: '127.0.0.1:3131' }, method, url: path + '?since=' + since });
    const res = { status: 0, writableEnded: false, writeHead(status) { this.status = status; },
      end(data) { this.data = data; this.writableEnded = true; } };
    assert.equal(typeof handler, 'function', 'expected route: ' + path);
    handler(req, res);
    if (body !== undefined) { req.emit('data', JSON.stringify(body)); req.emit('end'); }
    return res;
  }
  return {
    routes, spawns, route,
    event(id, type, data = {}) { handlers.get('session/event')({ id }, { type, data }); },
    error(id) { handlers.get('agent/error')({ agent: { id }, error: 'test' }); },
    approval(request, next) { return handlers.get('approval/request')(request, next); },
    focus(sessionId, focused) { route('/dsh-desktop-notify/focus', 'POST', { sessionId, focused }); },
    items(handler) { return JSON.parse(route('/dsh-whale-notify/react', 'GET', undefined, 0, handler).data).items; },
    dispose() { for (const cleanup of cleanups.reverse()) cleanup(); },
  };
}

test('reaction channel works with click-to-focus off; defaults create no native windows', async () => {
  const h = harness({ clickToFocus: false });
  try {
    assert(h.routes.has('/dsh-whale-notify/react'));
    assert(!h.routes.has('/dsh-desktop-notify/activate'));
    h.error('A'); await delay(10);
    assert.deepEqual(h.items().map(x => x.cls), ['failure']);
    assert.equal(h.spawns.length, 0);
  } finally { h.dispose(); }
});

test('final queue check suppresses a notification after focusing its session', async () => {
  const h = harness({ minGapMs: 70, recheckMs: 0 });
  try {
    h.error('warm'); await delay(10);
    h.error('A'); h.focus('A', true);
    await delay(90);
    assert.deepEqual(h.items().map(x => x.sessionId), ['warm']);
  } finally { h.dispose(); }
});

test('resolved approval cannot reappear when a focus recheck fires', async () => {
  const h = harness();
  try {
    h.focus('A', true);
    h.event('A', 'approval/asked', { requestId: 'r1' });
    h.event('A', 'approval/answered', { requestId: 'r1' });
    h.focus('A', false); await delay(45);
    assert.equal(h.items().length, 0);
  } finally { h.dispose(); }
});

test('a queued approval is canceled by its resolution', async () => {
  const h = harness({ minGapMs: 70 });
  try {
    h.error('warm'); await delay(10);
    h.event('A', 'approval/asked', { requestId: 'r1' });
    h.event('A', 'approval/resolved', { requestId: 'r1' });
    await delay(90);
    assert.deepEqual(h.items().map(x => x.sessionId), ['warm']);
  } finally { h.dispose(); }
});

test('DSH approval id and tool-result message shapes cancel the correct queued wait', async () => {
  const h = harness({ minGapMs: 70 });
  try {
    h.error('warm'); await delay(10);
    h.event('A', 'approval/asked', { id: 'approval-id', callId: 'call-id' });
    h.event('A', 'approval/decided', { id: 'approval-id', outcome: 'allowed-once' });
    h.event('B', 'tool/call', { callId: 'question-call', name: 'ask_user_question', arguments: '{}' });
    h.event('B', 'tool/result', { message: { role: 'tool', toolCallId: 'question-call' } });
    await delay(90);
    assert.deepEqual(h.items().map(x => x.sessionId), ['warm']);
  } finally { h.dispose(); }
});

test('waterfall abort cancels delivery while preserving the downstream answer', async () => {
  const h = harness({ minGapMs: 70 });
  try {
    h.error('warm'); await delay(10);
    let resolve;
    const controller = new AbortController();
    const result = h.approval({ agent: { id: 'A' }, requestId: 'r1', signal: controller.signal },
      () => new Promise(done => { resolve = done; }));
    controller.abort(); await delay(90);
    assert.deepEqual(h.items().map(x => x.sessionId), ['warm']);
    resolve('cancelled'); assert.equal(await result, 'cancelled');
  } finally { h.dispose(); }
});

test('blocked fallback does not duplicate an approval still waiting in the queue', async () => {
  const h = harness({ minGapMs: 70 });
  try {
    h.error('warm'); await delay(10);
    h.event('A', 'approval/asked', { requestId: 'r1' });
    h.event('A', 'turn/end', { reason: 'blocked' });
    await delay(110);
    assert.deepEqual(h.items().map(x => x.cls), ['failure', 'approval']);
  } finally { h.dispose(); }
});

test('a late approval supersedes an already queued blocked fallback', async () => {
  const h = harness({ minGapMs: 70 });
  try {
    h.error('warm'); await delay(10);
    h.event('A', 'turn/end', { reason: 'blocked' });
    await delay(10);
    h.event('A', 'approval/asked', { requestId: 'r1' });
    await delay(110);
    assert.deepEqual(h.items().map(x => x.cls), ['failure', 'approval']);
  } finally { h.dispose(); }
});

test('a new turn cancels a previous completion settle timer', async () => {
  const h = harness({ settleMs: 25 });
  try {
    h.event('A', 'turn/end', { reason: 'completed' });
    h.event('A', 'turn/start'); await delay(50);
    assert.equal(h.items().length, 0);
  } finally { h.dispose(); }
});

test('reload cancels settle, recheck, greeting and queued deliveries', async () => {
  const h = harness({ greeting: true, minGapMs: 70, settleMs: 25 });
  h.error('warm'); await delay(10);
  h.error('B'); h.event('C', 'turn/end', { reason: 'completed' });
  h.focus('A', true); h.event('A', 'approval/asked', { requestId: 'r1' });
  const oldRoute = h.routes.get('/dsh-whale-notify/react');
  h.dispose(); await delay(100);
  assert.deepEqual(h.items(oldRoute).map(x => x.sessionId), ['warm']);
  const fresh = harness();
  try { assert.equal(fresh.items().length, 0); } finally { fresh.dispose(); }
});

test('native delivery rechecks focus after a slow foreground probe', async () => {
  let verdict;
  const h = harness({ channels: { toast: true, alert: true } },
    () => new Promise(done => { verdict = done; }));
  try {
    h.error('A'); await delay(10);
    assert.equal(h.spawns.length, 1);
    assert(h.spawns[0].argv[0].endsWith('dsh-notify-probe.exe'));
    h.focus('A', true); verdict({ exitCode: 0 }); await delay(10);
    assert.equal(h.spawns.length, 1);
  } finally { h.dispose(); }
});

test('greeting uses only the pet even if native channels are explicitly enabled', async () => {
  const h = harness({ greeting: true, channels: { toast: true, alert: true } });
  try {
    await delay(2550);
    assert.equal(h.items().length, 1);
    assert.equal(h.spawns.length, 0);
  } finally { h.dispose(); }
});

test('disabled plugin registers no routes and sends no greeting', () => {
  const h = harness({ enabled: false, greeting: true });
  try { assert.equal(h.routes.size, 0); assert.equal(h.spawns.length, 0); } finally { h.dispose(); }
});
