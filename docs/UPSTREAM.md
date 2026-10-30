# 上游复用清单

本项目站在两个 MIT 项目肩上（均为原作者版权，见 `LICENSE` 末尾署名）。

## dsh-whale-musume（立绘与「她是谁」）

复用：

- `assets/generated/*.webp` 92 张立绘（桌面版取用其中 **60 张** 转成 PNG）
- `assets/whale-moe-core.js` 纯状态机（`POSES` / `KEYWORDS` / `DIALOGUE` / `festivalKey` / `greetBucket` / `computeGrowth` 语义）
- `assets/dsh-whale-moe.js` 应用内表现层（客户端半边原样引导）
- `KEYWORD_POSES` 姿态映射、成就与成长语义、节日表

没有直接搬的：应用内看板娘的 DOM 布局（用户要求「只留桌面上那一只」，应用内已收起）。

## dsh-desktop-notify（通道与「怎么叫她」）

复用：

- `lib/host.js` 通知引擎（事件订阅、门控、去重、限速、settle 复核、全屏裁决、焦点心跳）
- `lib/toast.ps1` / `lib/alert.ps1`（本项目默认关闭通道，脚本仍随包分发）
- `lib/dsh-notify-activator.exe` / `lib/dsh-notify-probe.exe` 与 COM 激活器注册（点击横幅回到对话）
- `~/.dsh/dsh-desktop-notify.activate` 交接协议（本项目用它实现桌宠牌上的「带我去看 →」）

新增（本项目）：鲸鱼娘主题文案与主视觉、反应队列（`/dsh-whale-notify/react`）、裁决路由（id→回调表）、桌面宠物联动。

## 自己拉上游（仓库里不含快照）

```powershell
mkdir .src; cd .src
git clone --depth 1 https://github.com/Sutera-Diffusus/dsh-whale-musume.git
git clone --depth 1 https://github.com/VoodooB0Ys/dsh-desktop-notify.git
```

`.src/` 已在 `.gitignore` 里——**别把上游整仓提交上来**，我们只分发自己那份合成产物与署名。
