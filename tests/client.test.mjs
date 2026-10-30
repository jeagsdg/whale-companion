import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const path = new URL('../packages/dsh-whale-notify/lib/client.js', import.meta.url);
const source = fs.readFileSync(path, 'utf8').replace('    return module.exports;', `
    module.exports.test = { handleReaction, installApprovalBridge, installApprovalMirror, installPetDecisionPoller,
      wnResolveApprovalById, wnApprovalResolvers, petPost, petSession, ensurePetAlive, installGreetWatch, disposeWhaleNotify,
      get clientId() { return wnClientId; }, get writes() { return petWriteChain; } };
    return module.exports;`);

function setup(options = {}) {
  let factory, sequence = 0, activeSession = 'SESSION_A';
  let uiAlive = options.uiAlive !== false;
  const calls = [], clicks = [], timeouts = new Map(), intervals = new Map(), observers = [], panels = [];
  const listeners = new Map(), prefs = new Map();
  let pendingDecision = {}, onApproval, subscribers = [];
  const listenerAPI = {
    addEventListener(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); }
  };
  const sessions = { scopeOf: (owner) => owner?.sessionId, list: {
    getSnapshot: () => ({ ids: [activeSession], byId: { [activeSession]: { retainedBy: { mainView: 1 } } } }),
    subscribe(fn) { subscribers.push(fn); return () => { subscribers = subscribers.filter((candidate) => candidate !== fn); }; }
  } };
  const document = {
    ...listenerAPI, title: 'Project - DeepSeek Harness', visibilityState: 'visible', hasFocus: () => true,
    documentElement: { getAttribute: () => '', setAttribute() {} },
    querySelector: () => null,
    querySelectorAll(selector) { return selector === '[data-approval-key]' ? panels : []; }
  };
  const window = {
    ...listenerAPI, crypto: { randomUUID: () => Math.random().toString(36).slice(2) },
    localStorage: { getItem: (key) => prefs.get(key) ?? null, setItem: (key, value) => prefs.set(key, value) },
    setTimeout(fn, delay) { const id = ++sequence; timeouts.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timeouts.delete(id); },
    setInterval(fn, delay) { const id = ++sequence; intervals.set(id, { fn, delay }); return id; },
    clearInterval(id) { intervals.delete(id); }, dispatchEvent() {}
  };
  const context = vm.createContext({
    window, document, AbortController, Promise, URLSearchParams, Map, Set, Date, Math, console,
    CustomEvent: class {}, Event: class {},
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    MutationObserver: class { constructor(fn) { this.fn = fn; observers.push(this); } observe() {} disconnect() { this.disconnected = true; } },
    fetch: async (url, options = {}) => {
      const body = options.body ? JSON.parse(options.body) : undefined;
      calls.push({ url, ...options, body });
      if (url.endsWith('/session')) return { ok: true, status: 200, json: async () => ({ ok: true, protocol: 2, uiAlive, token: 'TEST_TOKEN' }) };
      if (url.endsWith('/ping')) return { ok: true, status: 200, json: async () => ({ ok: true, protocol: 2, uiAlive }) };
      if (url.includes('/decision?')) return { ok: true, status: 200, json: async () => pendingDecision };
      if (url.endsWith('/decision/ack')) pendingDecision = {};
      if (url.endsWith('/dsh-whale-notify/react')) return { ok: false, status: 404 };
      if (url.endsWith('/dsh-desktop-notify/activate')) return { ok: true, status: 200, json: async () => ({}) };
      return { ok: true, status: 200, json: async () => ({ ok: true }) };
    }
  });
  window.__ModuleLoader__ = { load(descriptor) { factory = descriptor.factory; } };
  vm.runInContext(source, context, { filename: 'client.js' });
  const exports = factory((name) => name === 'react/jsx-runtime' ? { jsx() {}, jsxs() {} } : {});
  const test = exports.test;
  const effects = [];
  const ctx = {
    remote: { $on(name, fn) { onApproval = fn; return () => { onApproval = undefined; }; } },
    get(name) {
      if (name === 'sessions') return sessions;
      if (name === 'remote') return ctx.remote;
      if (name === 'slots') return { inject() {}, register() {} };
      return null;
    },
    effect(fn) { effects.push(fn()); },
    inject(names, fn) { fn({ sessions }); }
  };
  return {
    test, exports, ctx, sessions, document, calls, clicks, timeouts, intervals, observers, prefs, panels, effects,
    get handler() { return onApproval; }, set decision(value) { pendingDecision = value; },
    set uiAlive(value) { uiAlive = value; },
    switchSession(id) { activeSession = id; subscribers.forEach((fn) => fn()); },
    async flush() { for (let i = 0; i < 12; i += 1) await Promise.resolve(); await test.writes; },
    runTimeout(delay) { for (const [id, item] of [...timeouts]) if (item.delay === delay) { timeouts.delete(id); item.fn(); } },
    async runInterval(delay) { for (const item of [...intervals.values()]) if (item.delay === delay) await item.fn(); },
    panel(key) {
      const attrs = new Map([['data-approval-key', key]]);
      const panel = { isConnected: true, textContent: key, getAttribute: (name) => attrs.get(name) ?? null,
        getBoundingClientRect: () => ({ width: 200, height: 80 }), closest: () => null,
        setKey(value) { attrs.set('data-approval-key', value); }, querySelectorAll() { return [yes, no]; }
      };
      const button = (text, outcome) => ({ textContent: text, isConnected: true, disabled: false,
        getAttribute: () => null, getBoundingClientRect: () => ({ width: 60, height: 25 }),
        click: () => clicks.push({ session: activeSession, key: attrs.get('data-approval-key'), outcome }) });
      const yes = button('允许一次', 'allowed-once'), no = button('拒绝', 'rejected');
      return panel;
    }
  };
}

{
  const s = setup();
  await s.test.petSession();
  assert.equal(s.test.installApprovalBridge(s.ctx), true);
  const a = new AbortController(), b = new AbortController();
  const pa = s.handler({ requestId: 'REQUEST_A', sessionId: 'SESSION_A', toolName: '测试中文', reason: '你好', signal: a.signal }, () => 'delegated');
  const pb = s.handler({ requestId: 'REQUEST_B', sessionId: 'SESSION_B', signal: b.signal }, () => 'delegated');
  await s.flush();
  const entries = [...s.test.wnApprovalResolvers.values()];
  assert.equal(entries.length, 2);
  assert.equal(await s.test.wnResolveApprovalById(entries[0].id, 'allowed-once', 'FOREIGN_CLIENT'), false);
  assert.equal(await s.test.wnResolveApprovalById(entries[0].id, 'allowed-once', s.test.clientId, 'SESSION_B'), false);
  assert.equal(await s.test.wnResolveApprovalById('stale', 'allowed-once', s.test.clientId), false);
  assert.equal(await s.test.wnResolveApprovalById(entries[0].id, 'allowed-once', s.test.clientId, 'SESSION_A'), true);
  assert.equal(await pa, 'allowed-once');
  b.abort();
  assert.equal(await pb, 'cancelled');
  await s.flush();
  assert.equal(s.test.wnApprovalResolvers.size, 0);
  assert.equal(s.calls.filter((call) => call.body?.clearApprovalId).length, 2);
  const states = s.calls.filter((call) => call.url.endsWith('/state'));
  assert(states.every((call) => call.method === 'POST' && call.headers['X-Whale-Token'] === 'TEST_TOKEN'));
  assert(states.some((call) => call.body.approval?.tool === '测试中文'));
  assert.equal(s.handler({ toolName: 'missing identity' }, () => 'safe-native'), 'safe-native');
  s.test.disposeWhaleNotify();
  console.log('PASS: concurrent identity binding, cross-client/session rejection, cancellation and UTF-8 POST');
}

{
  const s = setup(); await s.test.petSession(); s.test.installApprovalBridge(s.ctx);
  const pending = s.handler({ id: 'TIMEOUT', sessionId: 'SESSION_A' }, () => 'native-timeout');
  await s.flush(); const entry = [...s.test.wnApprovalResolvers.values()][0];
  s.runTimeout(45000); assert.equal(await pending, 'native-timeout'); await s.flush();
  assert.equal(await s.test.wnResolveApprovalById(entry.id, 'allowed-once', s.test.clientId), false);
  assert(s.calls.some((call) => call.body?.clearApprovalId === entry.id));
  s.test.disposeWhaleNotify(); console.log('PASS: timeout releases original approval and clears exactly its id');
}

{
  const s = setup(); await s.test.petSession();
  s.test.handleReaction({ cls: 'approval', sessionId: 'SESSION_A', headline: '待审批' });
  s.test.handleReaction({ cls: 'completion', sessionId: 'SESSION_B', line: '完成了' });
  await s.flush();
  assert.equal(s.test.wnApprovalResolvers.size, 0);
  assert(s.calls.filter((call) => call.url.endsWith('/state')).every((call) => !('approval' in call.body) && !('clearApprovalId' in call.body)));
  s.test.disposeWhaleNotify(); console.log('PASS: host reactions are notifications only and normal state cannot clear approvals');
}

{
  const s = setup(); await s.test.petSession();
  const panel = s.panel('KEY_A'); s.panels.push(panel); s.test.installApprovalMirror(s.sessions); await s.flush();
  const old = [...s.test.wnApprovalResolvers.values()][0];
  panel.setKey('KEY_B'); await s.runInterval(3000); await s.flush();
  const fresh = [...s.test.wnApprovalResolvers.values()][0];
  assert.equal(fresh.requestId, 'KEY_B'); assert.notEqual(fresh.id, old.id);
  assert.equal(await s.test.wnResolveApprovalById(old.id, 'allowed-once', s.test.clientId), false);
  s.switchSession('SESSION_B');
  assert.equal(await s.test.wnResolveApprovalById(fresh.id, 'allowed-once', s.test.clientId), false);
  assert.equal(s.clicks.length, 0);
  await s.runInterval(3000); await s.flush();
  const b = [...s.test.wnApprovalResolvers.values()][0];
  assert.equal(b.sessionId, 'SESSION_B');
  assert.equal(await s.test.wnResolveApprovalById(b.id, 'rejected', s.test.clientId), true);
  assert.deepEqual(s.clicks, [{ session: 'SESSION_B', key: 'KEY_B', outcome: 'rejected' }]);
  s.test.disposeWhaleNotify(); console.log('PASS: mirror tracks real key swaps, binds session and clicks captured exact rejection button');
}

{
  const s = setup(); await s.test.petSession(); s.test.installApprovalBridge(s.ctx); s.test.installPetDecisionPoller();
  const pending = s.handler({ id: 'ACK', sessionId: 'SESSION_A' }, () => 'native'); await s.flush();
  const entry = [...s.test.wnApprovalResolvers.values()][0];
  s.decision = { id: entry.id, clientId: s.test.clientId, sessionId: 'SESSION_A', outcome: 'rejected' };
  await s.runInterval(1200); assert.equal(await pending, 'rejected');
  assert(s.calls.some((call) => call.url.endsWith('/decision/ack') && call.body.id === entry.id));
  s.decision = { id: 'unknown', clientId: s.test.clientId, outcome: 'allowed-once' };
  await s.runInterval(1200); assert.equal(s.clicks.length, 0);
  assert(s.calls.some((call) => call.url.endsWith('/decision/ack') && call.body.id === 'unknown'));
  s.test.disposeWhaleNotify(); assert.equal(s.intervals.size, 0);
  console.log('PASS: scoped decision polling, post-execution ACK, stale decisions discarded without DOM fallback');
}

{
  const s = setup();
  s.exports.apply(s.ctx); await s.flush();
  assert(s.effects.some((effect) => typeof effect === 'function'));
  const listener = s.handler; assert(listener);
  s.exports.dispose(); await s.flush();
  assert.equal(s.intervals.size, 0); assert.equal(s.timeouts.size, 0);
  assert(s.observers.every((observer) => observer.disconnected)); assert.equal(s.handler, undefined);
  assert.equal(s.calls.filter((call) => /\/(?:show|wake)(?:\?|$)/.test(call.url)).length, 0);
  console.log('PASS: disposal releases timers/observers/remote listener; health checks never launch/show a program');
}

{
  const s = setup();
  const lateRemote = s.ctx.remote;
  delete s.ctx.remote;
  s.exports.apply(s.ctx); await s.flush(); assert.equal(s.handler, undefined);
  for (let i = 0; i < 4; i += 1) await s.runInterval(2000);
  s.ctx.remote = lateRemote;
  await s.runInterval(2000); assert.equal(typeof s.handler, 'function');
  s.exports.dispose(); await s.flush(); assert.equal(s.intervals.size, 0);
  console.log('PASS: slow remote initialization retries until actual subscription succeeds');
}

{
  const s = setup(); delete s.ctx.remote; s.exports.apply(s.ctx); await s.flush();
  for (let i = 0; i < 40; i += 1) await s.runInterval(2000);
  assert(![...s.intervals.values()].some((item) => item.delay === 2000 && /bindApproval/.test(item.fn.toString())));
  s.exports.dispose(); await s.flush();
  console.log('PASS: unavailable remote retry stops after bounded attempts');
}

{
  const s = setup({ uiAlive: false });
  await s.test.petSession(); s.test.installApprovalBridge(s.ctx);
  await s.test.petPost({ pose: 'idle', line: 'bridge-only' });
  assert.equal(s.handler({ id: 'UI_ABSENT', sessionId: 'SESSION_A' }, () => 'native-ui-dead'), 'native-ui-dead');
  assert.equal(s.test.wnApprovalResolvers.size, 0);
  s.uiAlive = true; s.test.ensurePetAlive(); await s.flush();
  const controller = new AbortController();
  const pending = s.handler({ id: 'UI_PRESENT', sessionId: 'SESSION_A', signal: controller.signal }, () => 'native');
  await s.flush(); assert.equal(s.test.wnApprovalResolvers.size, 1);
  s.uiAlive = false; await s.runInterval(15000);
  assert.equal(s.handler({ id: 'UI_DIED', sessionId: 'SESSION_A' }, () => 'native-after-ui-death'), 'native-after-ui-death');
  controller.abort(); assert.equal(await pending, 'cancelled');
  s.exports.dispose(); await s.flush();
  console.log('PASS: authenticated bridge without a live UI never intercepts; ping UI death restores native approval');
}

{
  const s = setup(); await s.test.petSession();
  /* remote 注入作用域没有 sessions 服务时，必须从父上下文取回官方 scopeOf。 */
  assert.equal(s.test.installApprovalBridge({ remote: s.ctx.remote }, s.ctx), true);
  const pending = s.handler.call({ sessionId: 'SESSION_OFFICIAL' }, {
    callId: 'CALL_OFFICIAL', toolName: '官方结构', displayReason: { zh: '中文授权说明', en: 'English reason' }
  }, () => 'native');
  await s.flush();
  const entry = [...s.test.wnApprovalResolvers.values()][0];
  assert.equal(entry.sessionId, 'SESSION_OFFICIAL'); assert.equal(entry.requestId, 'CALL_OFFICIAL');
  assert.equal(entry.reason, '中文授权说明');
  assert.equal(await s.test.wnResolveApprovalById(entry.id, 'allowed-once', s.test.clientId, 'SESSION_OFFICIAL'), true);
  assert.equal(await pending, 'allowed-once');
  assert.equal(s.handler.call({}, { callId: 'NO_OWNER' }, () => 'native-unscoped'), 'native-unscoped');
  assert.equal(s.handler.call({ sessionId: 'OWNER' }, { callId: 'MISMATCH', sessionId: 'OTHER' }, () => 'native-mismatch'), 'native-mismatch');
  s.sessions.scopeOf = () => { throw new Error('released scope'); };
  assert.equal(s.handler.call({}, { callId: 'RELEASED' }, () => 'native-released'), 'native-released');
  s.exports.dispose(); await s.flush();
  console.log('PASS: official owner scope + callId identity, parent-scope injection fallback, localized reason and safe scope failures');
}

{
  const s = setup(); await s.test.petSession();
  s.test.handleReaction({ cls: 'completion', body: '目录：E:\\workspace\\项目A', line: 'done' });
  await s.flush(); assert.equal(s.calls.filter((call) => call.url.endsWith('/state')).at(-1).body.note, '项目A');
  s.test.handleReaction({ cls: 'completion', body: '目录：D:\\other\\项目B\\', line: 'done' });
  await s.flush(); assert.equal(s.calls.filter((call) => call.url.endsWith('/state')).at(-1).body.note, '项目B');
  s.document.title = '无关的会话标题 - DeepSeek Harness';
  s.test.handleReaction({ cls: 'completion', body: '任务完成，没有目录信息', line: 'done' });
  await s.flush(); assert.equal(s.calls.filter((call) => call.url.endsWith('/state')).at(-1).body.note, '项目B');
  s.test.installGreetWatch(); s.runTimeout(6000); await s.flush();
  assert.equal(s.calls.filter((call) => call.url.endsWith('/state')).at(-1).body.note, '项目B');
  s.exports.dispose(); await s.flush();
  const empty = setup(); await empty.test.petSession();
  empty.document.title = '不得当作项目名的标题 - DeepSeek Harness';
  empty.test.installGreetWatch(); empty.runTimeout(6000); await empty.flush();
  assert.equal(empty.calls.filter((call) => call.url.endsWith('/state')).at(-1).body.note, '');
  empty.exports.dispose(); await empty.flush();
  console.log('PASS: project A-to-B directory updates, missing directory preserves memory and greetings never infer projects from page title');
}
