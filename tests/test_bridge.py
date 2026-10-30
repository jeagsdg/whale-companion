"""Real loopback integration tests; temporary home, random port, no desktop UI."""
import hashlib
import json
import pathlib
import socket
import subprocess
import tempfile
import time
import unittest
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]

class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / '.diag').mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(prefix='bridge-v2-', dir=ROOT / '.diag')
        cls.home = pathlib.Path(cls.temp.name)
        cls.sessions = cls.home / 'sessions'
        cls.sessions.mkdir()
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            cls.port = reserve.getsockname()[1]
        cls.args = ['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',
                    str(ROOT / 'packages/desktop-pet/whale-pet-http.ps1'),'-Port',str(cls.port),'-PetHome',str(cls.home),'-SessionRoot',str(cls.sessions)]
        cls.process = subprocess.Popen(cls.args, creationflags=subprocess.CREATE_NO_WINDOW,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    status, _, body = cls.request('GET','/session',auth=False)
                    if status == 200:
                        cls.token = body['token']
                        break
                    raise RuntimeError(f'session returned {status}: {body}')
                except (ConnectionError, OSError):
                    if cls.process.poll() is not None:
                        raise RuntimeError(cls.process.stderr.read().decode(errors='replace'))
                    time.sleep(.1)
            else:
                raise RuntimeError('bridge failed to start')
        except BaseException:
            cls.process.terminate(); cls.process.wait(timeout=10); cls.temp.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate(); cls.process.wait(timeout=10)
        errors=cls.process.stderr.read().decode('utf-8',errors='replace')
        if errors: print('BRIDGE STDERR:',errors)
        cls.process.stderr.close(); cls.temp.cleanup()

    @classmethod
    def request(cls, method, path, payload=None, origin='dsh-app://app', auth=True, host=None):
        body = b'' if payload is None else json.dumps(payload,ensure_ascii=False).encode('utf-8')
        headers = [f'{method} {path} HTTP/1.1',f'Host: {host or "127.0.0.1:"+str(cls.port)}',f'Origin: {origin}','Connection: close']
        if auth: headers.append('X-Whale-Token: '+cls.token)
        if payload is not None: headers += ['Content-Type: application/json',f'Content-Length: {len(body)}']
        with socket.create_connection(('127.0.0.1',cls.port),timeout=5) as stream:
            stream.sendall(('\r\n'.join(headers)+'\r\n\r\n').encode('ascii')+body)
            chunks=[]
            while chunk:=stream.recv(8192): chunks.append(chunk)
        head, raw = b''.join(chunks).split(b'\r\n\r\n',1)
        return int(head.split(b' ')[1]), head.decode('ascii'), json.loads(raw) if raw else None

    def put_approval(self, client, aid, session='session-A'):
        return self.request('POST','/state',{'clientId':client,'pose':'wait','approval':{
            'id':aid,'clientId':client,'sessionId':session,'requestId':'request-'+aid,'tool':'test','reason':'中文请求'}})

    def cancel(self, client, aid):
        return self.request('POST','/approval/cancel',{'clientId':client,'id':aid})

    def test_untrusted_origin_and_missing_token_rejected(self):
        self.assertEqual(self.request('GET','/session',origin='https://untrusted.example',auth=False)[0],403)
        self.assertEqual(self.request('GET','/session',host='evil.example',auth=False)[0],403)
        self.assertEqual(self.request('GET','/decision?clientId=a',auth=False)[0],401)
        self.assertEqual(self.request('GET','/show',auth=False)[0],401)
        self.assertFalse((self.home/'show.json').exists())

    def test_health_survives_corrupt_heartbeat_and_bridge_has_its_own_signal(self):
        alive = self.home / 'alive.json'
        try:
            for record in ({'pid':'broken','at':'broken'},{'pid':1,'at':'NaN'},{'pid':1,'at':1e100}):
                alive.write_text(json.dumps(record), encoding='utf-8')
                status, _, body = self.request('GET','/ping',auth=False)
                self.assertEqual(status, 200)
                self.assertFalse(body['uiAlive'])
            signal = json.loads((self.home/'bridge-alive.json').read_text(encoding='utf-8'))
            self.assertEqual(signal['pid'], self.process.pid)
            self.assertGreater(signal['at'], 0)
        finally:
            alive.unlink(missing_ok=True)

    def test_utf8_post_and_ordinary_state_preserves_approval_queue(self):
        start=time.monotonic()
        self.assertEqual(self.put_approval('unicode','a')[0],200)
        self.assertLess(time.monotonic()-start,2)
        self.assertEqual(self.request('POST','/state',{'clientId':'other','pose':'ok','line':'完成啦','approval':None})[0],200)
        state=json.loads((self.home/'state.json').read_text(encoding='utf-8'))
        self.assertEqual(state['approval']['id'],'a')
        self.assertEqual(state['sid'],'session-A')
        self.assertEqual(state['line'],'完成啦')
        self.assertEqual(self.put_approval('unicode','a','wrong-session')[0],400)
        self.cancel('unicode','a')

    def test_decision_is_owned_repeatable_and_acknowledged(self):
        client, aid='owner','decision-1'
        self.put_approval(client,aid)
        folder=self.home/'decisions'/hashlib.sha256(client.encode()).hexdigest()
        folder.mkdir(parents=True,exist_ok=True)
        path=folder/(hashlib.sha256(aid.encode()).hexdigest()+'.json')
        path.write_text(json.dumps({'id':aid,'clientId':client,'sessionId':'session-A','requestId':'request-'+aid,'outcome':'allowed-once'}),encoding='utf-8')
        self.assertEqual(self.request('GET','/decision?clientId=other')[2],{})
        for _ in range(2): self.assertEqual(self.request('GET','/decision?clientId=owner')[2]['id'],aid)
        self.assertEqual(self.request('OPTIONS','/decision',auth=False)[0],204)
        self.assertTrue(path.exists())
        self.request('POST','/decision/ack',{'clientId':'other','id':aid})
        self.assertTrue(path.exists())
        self.request('POST','/decision/ack',{'clientId':client,'id':aid})
        self.assertFalse(path.exists())
        self.assertEqual(self.request('GET','/decision?clientId=owner')[2],{})

    def test_cancelling_one_request_keeps_the_next(self):
        self.put_approval('first','one')
        self.put_approval('second','two','session-B')
        self.request('POST','/state',{'clientId':'first','pose':'idle','clearApprovalId':'one'})
        state=json.loads((self.home/'state.json').read_text(encoding='utf-8'))
        self.assertEqual(state['approval']['id'],'two')
        self.assertEqual(state['approvalCount'],1)
        self.cancel('second','two')

    def test_existing_bridge_prevents_duplicate_process(self):
        duplicate=subprocess.run(self.args,creationflags=subprocess.CREATE_NO_WINDOW,capture_output=True,timeout=10)
        self.assertEqual(duplicate.returncode,0,duplicate.stderr)
        self.assertIsNone(self.process.poll())
        self.assertEqual(self.request('GET','/ping',auth=False)[0],200)


class CodexBridgeTests(unittest.TestCase):
    """Separate runtime and port: Codex preferences never contaminate DSH tests."""
    request = classmethod(BridgeTests.request.__func__)

    @classmethod
    def setUpClass(cls):
        (ROOT / '.diag').mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(prefix='codex-bridge-', dir=ROOT / '.diag')
        cls.home = pathlib.Path(cls.temp.name)
        cls.sessions = cls.home / 'sessions'
        cls.sessions.mkdir()
        cls.rollout = cls.sessions / 'root.jsonl'
        cls.rollout.write_text(json.dumps({'type':'session_meta','payload':{
            'id':'01a13567-1329-7381-bb41-6ce4f4d18c47','cwd':'E:/Projects/reader-test','source':'cli'}})+'\n', encoding='utf-8')
        (cls.home / 'pet-preferences.json').write_text(
            json.dumps({'host': 'codex', 'quiet': True}), encoding='utf-8')
        cls.cachedAt = int(time.time() * 1000) - 1000000
        (cls.home / 'state.json').write_text(json.dumps({'host':'codex', 'kind':'approval',
            'noticeId':'cached-old-notice', 'pose':'wait', 'at':cls.cachedAt}), encoding='utf-8')
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            cls.port = reserve.getsockname()[1]
        cls.args = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                    str(ROOT / 'packages/desktop-pet/whale-pet-http.ps1'),
                    '-Port', str(cls.port), '-PetHome', str(cls.home), '-SessionRoot', str(cls.sessions)]
        cls.process = subprocess.Popen(cls.args, creationflags=subprocess.CREATE_NO_WINDOW,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    status, _, body = cls.request('GET', '/session', origin='', auth=False)
                    if status == 200:
                        cls.token = body['token']
                        break
                    raise RuntimeError(f'Codex session returned {status}: {body}')
                except (ConnectionError, OSError):
                    if cls.process.poll() is not None:
                        raise RuntimeError(cls.process.stderr.read().decode(errors='replace'))
                    time.sleep(.1)
            else:
                raise RuntimeError('Codex bridge failed to start')
        except BaseException:
            cls.process.terminate(); cls.process.wait(timeout=10); cls.temp.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate(); cls.process.wait(timeout=10)
        errors = cls.process.stderr.read().decode('utf-8', errors='replace')
        if errors:
            print('CODEX BRIDGE STDERR:', errors)
        cls.process.stderr.close(); cls.temp.cleanup()

    def state(self):
        # Python's Windows file handle cannot share deletion during atomic replacement.
        # Retry the brief swap window; the actual UI reader uses FileShare.Delete.
        for attempt in range(20):
            try:
                return json.loads((self.home / 'state.json').read_text(encoding='utf-8-sig'))
            except (PermissionError, FileNotFoundError, json.JSONDecodeError):
                if attempt == 19:
                    raise
                time.sleep(.01)

    def test_a_cached_notice_keeps_original_time_after_start(self):
        self.assertEqual(self.state()['at'], self.cachedAt)
        self.assertGreater(time.time()*1000-self.state()['at'],900000)

    def test_b_bridge_reads_codex_work_without_a_separate_worker(self):
        with self.rollout.open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'timestamp':datetime.now(timezone.utc).isoformat(),
                'type':'response_item','payload':{'type':'function_call','name':'exec_command',
                'arguments':'npm test TOP_SECRET_COMMAND'}})+'\n')
        self.wait_for(lambda: self.state().get('activity') == 'test', 'integrated reader did not publish work stage')
        state = self.state()
        self.assertEqual(state['note'], 'reader-test')
        self.assertIn('运行测试和验证', state['line'])
        self.assertNotIn('TOP_SECRET', json.dumps(state))

    def wait_for(self, predicate, message, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.assertIsNone(self.process.poll(), 'Codex bridge unexpectedly exited')
            try:
                if predicate():
                    return
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.05)
        self.fail(message)

    def event(self, kind='completion', **changes):
        stamp = int(time.time() * 1000)
        value = {'host': 'codex', 'kind': kind,
                 'sid': '01a13567-1329-7381-bb41-6ce4f4d18c47',
                 'at': stamp, 'noticeId': f'notice-{time.time_ns()}',
                 'pose': 'wait' if kind in ('approval', 'question') else 'ok',
                 'line': '{user}，隔离测试完成啦', 'note': '中文项目'}
        value.update(changes)
        folder = self.home / 'host-events'
        folder.mkdir(exist_ok=True)
        destination = folder / f'{stamp}-{time.time_ns()}.json'
        # Commit a complete file; the bridge does not need an HTTP request to see it.
        temporary = destination.with_suffix('.tmp')
        temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
        temporary.replace(destination)
        return destination, value

    def test_invalid_and_stale_files_are_pruned_without_an_http_request(self):
        before = self.state()
        folder = self.home / 'host-events'
        folder.mkdir(exist_ok=True)
        malformed = folder / 'malformed.json'
        malformed.write_text('{ this is incomplete JSON', encoding='utf-8')
        oversized = folder / 'oversized.json'
        oversized.write_text('x' * 17000, encoding='utf-8')
        files = [malformed, oversized]
        for changes in ({'at': int(time.time() * 1000) - 180000},
                        {'at': int(time.time() * 1000) + 60000},
                        {'at': 'not-a-number'}, {'at': 0},
                        {'sid': '../unsafe'}, {'kind': 'unsupported'},
                        {'host': 'dsh'}, {'line': 'x' * 501}):
            files.append(self.event(**changes)[0])
        self.wait_for(lambda: all(not file.exists() for file in files),
                      'Invalid host events were not removed by the background pump')
        self.assertEqual(self.state(), before)

    def test_valid_metadata_pumps_without_an_http_request(self):
        destination, event = self.event()
        self.wait_for(lambda: self.state().get('noticeId') == event['noticeId'],
                      'Codex metadata did not reach state.json without HTTP traffic')
        state = self.state()
        self.assertFalse(destination.exists())
        self.assertEqual((state['host'], state['kind'], state['sid']),
                         ('codex', 'completion', event['sid']))
        self.assertEqual(state['note'], '中文项目')
        self.assertIsNone(state['approval'])
        self.assertEqual(state['approvalCount'], 0)
        self.assertFalse((self.home / 'show.json').exists())

    def test_native_attention_is_notification_only_and_clears_on_progress(self):
        for kind in ('approval', 'question', 'tool', 'completion'):
            _, event = self.event(kind)
            self.wait_for(lambda: self.state().get('noticeId') == event['noticeId'],
                          f'Codex {kind} did not reach the bridge state')
            self.assertEqual(self.state()['kind'], kind)
            self.assertIsNone(self.state()['approval'])
            self.assertEqual(self.state()['approvalCount'], 0)
        self.assertFalse(list((self.home / 'decisions').glob('**/*.json')))
        self.assertFalse((self.home / 'show.json').exists())

    def test_codex_mode_rejects_dsh_origin_and_creates_no_decision(self):
        before = self.state()
        self.assertEqual(self.request('GET', '/session', auth=False)[0], 403)
        status = self.request('POST', '/state', {'clientId': 'legacy', 'pose': 'wait',
            'approval': {'id': 'legacy-approval', 'clientId': 'legacy',
                         'sessionId': 'legacy-session', 'requestId': 'legacy-request',
                         'tool': 'never execute', 'reason': 'legacy approval'}})[0]
        self.assertEqual(status, 403)
        self.assertEqual(self.state(), before)
        self.assertFalse(list((self.home / 'decisions').glob('**/*.json')))
        self.assertFalse((self.home / 'show.json').exists())

    def test_z_stopped_intent_ends_bridge(self):
        (self.home/'control.json').write_text('{"stopped":true}',encoding='utf-8')
        self.process.wait(timeout=4)
        self.assertEqual(self.process.returncode,0)

if __name__=='__main__': unittest.main(verbosity=2)
