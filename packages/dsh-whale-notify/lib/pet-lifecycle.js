import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import { join } from 'node:path';

export function readPetHealth(timeoutMs = 900) {
  return new Promise((resolve) => {
    const req = http.get({hostname:'127.0.0.1', port:19390, path:'/ping', timeout:timeoutMs}, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; if (body.length > 8192) req.destroy(); });
      res.on('end', () => { try { resolve(res.statusCode === 200 ? JSON.parse(body) : null); } catch { resolve(null); } });
      res.on('error', () => resolve(null));
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

/** One owner, no show requests, no Explorer fallback, and a bounded retry budget. */
export function createPetSupervisor({petHome, spawn, health = readPetHealth, now = Date.now,
  readJson = (path) => { try { return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } },
  exists = existsSync, processAlive = (pid) => { try { process.kill(Number(pid), 0); return true; } catch { return false; } },
  log = () => {}}) {
  let busy = false, disposed = false, failures = 0, retryAt = 0;
  return {
    dispose() { disposed = true; },
    async check() {
      if (disposed || busy) return 'idle';
      if (readJson(join(petHome, 'control.json'))?.stopped === true) return 'stopped';
      busy = true;
      try {
        const status = await health();
        if (disposed) return 'disposed';
        const alive = readJson(join(petHome, 'alive.json'));
        const uiProcess = alive?.pid && processAlive(alive.pid);
        const fresh = uiProcess && now() - Number(alive.at) < 45000;
        if (status?.ok && (status.uiAlive === true || fresh)) { failures = 0; retryAt = 0; return 'online'; }
        // A live but stalled process is never a reason to create another UI.
        if (status?.ok && uiProcess) return 'unresponsive';
        if (now() < retryAt) return 'backoff';
        if (failures >= 3) return 'retry-limit';
        const launcher = join(petHome, 'whale-pet-start.ps1');
        if (!exists(launcher) || typeof spawn !== 'function') return 'unavailable';
        failures += 1;
        retryAt = now() + Math.min(300000, 30000 * 2 ** failures);
        // Recheck intent immediately before spawning, including after an awaited health check.
        if (disposed || readJson(join(petHome, 'control.json'))?.stopped === true) return 'stopped';
        const handle = spawn({argv:['powershell.exe','-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',launcher,'-PetHome',petHome,'-Auto'],
          cwd:petHome, stdio:{stdin:'ignore',stdout:{maxBytes:2048},stderr:{maxBytes:2048}},graceMs:10000});
        Promise.resolve(handle?.done).catch((error) => log(`launcher: ${error?.message ?? error}`));
        log(`single-instance recovery requested (attempt ${failures}/3)`);
        return 'starting';
      } catch (error) { log(`health check: ${error?.message ?? error}`); return 'failed'; }
      finally { busy = false; }
    }
  };
}
