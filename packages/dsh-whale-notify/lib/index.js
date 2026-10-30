/** Host entry: asset routes, notifications, and silent single-instance recovery. */
import { homedir } from 'node:os';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { apply as whaleAssetsApply } from './whale-assets.js';
import { apply as notifyApply } from './notify.js';
import { createPetSupervisor } from './pet-lifecycle.js';

export const name = 'dsh-whale-notify';
export const inject = ['webServer'];

export function installedPetHome(config = {}) {
  if (config.petHome) return resolve(config.petHome);
  if (process.env.DSH_HOME) return join(process.env.DSH_HOME, 'whale-pet');
  const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
  const parent = dirname(packageRoot);
  if (basename(parent).toLowerCase() === 'whale-notify') return join(dirname(parent), 'whale-pet');
  if (basename(parent).toLowerCase() === 'node_modules' && basename(dirname(parent)).toLowerCase() === 'desktop') {
    return resolve(parent, '../../..', 'whale-pet');
  }
  return join(homedir(), '.dsh', 'whale-pet');
}

export async function apply(ctx, config = {}) {
  await whaleAssetsApply(ctx);
  const startEngine = (scope = ctx) => {
    try {
      const result = notifyApply(scope, config);
      if (result?.catch) result.catch((error) => ctx.logger?.warn?.('通知引擎启动失败', error));
    } catch (error) { ctx.logger?.warn?.('通知引擎启动失败', error); }
  };
  if (ctx.get?.('subprocess') === undefined && typeof ctx.inject === 'function') ctx.inject(['subprocess'], startEngine);
  else startEngine();

  if (config.petAutoStart !== false) {
    const supervisor = createPetSupervisor({
      petHome: installedPetHome(config),
      spawn: (options) => {
        const sub = ctx.get?.('subprocess') ?? ctx.subprocess;
        if (!sub?.spawn) throw new Error('subprocess unavailable');
        return sub.spawn(options);
      },
      log: (line) => ctx.logger?.debug?.(`桌宠: ${line}`)
    });
    const check = () => { void supervisor.check(); };
    check();
    const timer = setInterval(check, 60000);
    timer.unref?.();
    ctx.on?.('dispose', () => { supervisor.dispose(); clearInterval(timer); });
  }
  ctx.logger?.info?.('鲸鱼娘已挂载：后台检查不唤醒窗口，手动隐藏和退出保持有效');
}
