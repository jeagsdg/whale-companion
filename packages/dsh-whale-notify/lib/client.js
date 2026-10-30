/**
 * dsh-whale-musume 客户端插件:把鲸鱼娘桌宠注入 DSH Web UI(纯 DOM 注入)。
 *
 * 零侵入:不改任何内置包文件、不读业务 DOM、无外部请求。
 * 资源经宿主路由 /api/dsh-whale-musume/assets?f=<path> 加载,
 * 注入顺序:样式 → 状态机(whale-moe-core)→ 表现层(dsh-whale-moe),
 * 表现层的资源根与校准表路径会被改写为宿主路由。
 *
 * v1.4.2 起,额外把「看板娘」设置栏目注册进 DSH 设置面板
 * (settings.section, id=mascot)——与 scripts/apply-theme.mjs
 * --mascot-settings v27 注入的面板同源(读 whale-moe:* localStorage,
 * 监听 whale-moe-prefs-change),使 bundle 安装方式同样自带设置面板。
 */
window.__ModuleLoader__.load({
  id: "dsh-whale-notify",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;

    var React = require("react");
    var jsxRuntime = require("react/jsx-runtime");
    var jsx = jsxRuntime.jsx;
    var jsxs = jsxRuntime.jsxs;

    const BASE = "/api/dsh-whale-musume/assets?f=";
    const BOOT_FLAG = "__dshWhaleMusumeBooted";
    const MIMO_TTS_EVENT = "dsh-whale-musume:interaction-line";

    function injectStyle(text) {
      const el = document.createElement("style");
      el.setAttribute("data-dsh-whale-musume", "css");
      el.textContent = text;
      document.head.appendChild(el);
    }

    function injectScript(text) {
      const el = document.createElement("script");
      el.setAttribute("data-dsh-whale-musume", "js");
      el.textContent = text;
      document.body.appendChild(el);
    }

    async function boot() {
      if (window[BOOT_FLAG]) return;
      window[BOOT_FLAG] = true;
      try {
        const css = await (await fetch(BASE + "dsh-whale-moe.css")).text();
        injectStyle(css);
        const core = await (await fetch(BASE + "whale-moe-core.js")).text();
        injectScript(core);
        const raw = await (await fetch(BASE + "dsh-whale-moe.js")).text();
        const presenter = raw
          .replace('var ASSET_ROOT = "/assets/generated/";', 'var ASSET_ROOT = "' + BASE + 'generated/";')
          /* 旧版还有一处 ANIM_ROOT 替换，但 presenter 里从来没有这个常量
             （assets/anim/*.webm 未被引用），那处 replace 永不命中，已删除以免误导。 */
          .replace('fetch("/assets/peek-calibration.json")', 'fetch("' + BASE + 'peek-calibration.json")');
        injectScript(presenter);
      } catch (error) {
        console.warn("[dsh-whale-musume] 资源加载失败:", error);
      }
    }

    /* ---- 设置面板「看板娘」栏目(与 apply-theme.mjs --mascot-settings v27 同源) ---- */

    const MASCOT_NS = "settings.mascot";
    const MASCOT_ROW_STYLE = { alignItems: "center", borderBottom: "1px solid var(--dsw-alias-border-l2)", display: "flex", gap: "12px", justifyContent: "space-between", padding: "10px 0" };
    const MASCOT_CARD_STYLE = { background: "var(--dsw-alias-bg-module-platform, transparent)", border: "1px solid var(--dsw-alias-border-l2)", borderRadius: "14px", display: "flex", flexDirection: "column", gap: "2px", marginTop: "10px", padding: "6px 14px", width: "100%" };
    function MascotCard({ title, children }) {
      return jsxs("div", { style: MASCOT_CARD_STYLE, children: [jsx("div", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", fontWeight: "600", padding: "6px 0 2px" }, children: title }), children] });
    }
    function MascotValue(key, fallback) {
      try { const v = window.localStorage.getItem("whale-moe:" + key); return v === null ? fallback : v; } catch (e) { return fallback; }
    }
    function MascotPrefRow({ label, prefKey, compact }) {
      /* 涉及额外读取或外部能力的功能默认关闭。 */
      const defaultOff = prefKey === "mimoTts" || prefKey === "keywords" || prefKey === "balance" ||
        prefKey === "balanceDetail" || prefKey === "a11y";
      const [isOn, setIsOn] = React.useState(MascotValue(prefKey, defaultOff ? "0" : "1") !== "0");
      return jsxs("div", { style: compact ? { alignItems: "center", display: "flex", gap: "8px", justifyContent: "space-between", minWidth: 0, padding: "6px 0" } : MASCOT_ROW_STYLE, children: [jsx("span", { style: compact ? { fontSize: "12px", minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } : undefined, children: label }), jsx("button", {
        type: "button", role: "switch",
        "aria-checked": isOn,
        style: { alignItems: "center", background: isOn ? "var(--dsw-static-accent, #4da3ff)" : "var(--dsw-alias-border-l3, #c9cdd6)", border: "none", borderRadius: "999px", cursor: "pointer", display: "flex", height: "24px", justifyContent: isOn ? "flex-end" : "flex-start", padding: "3px", transition: "background 160ms ease", width: "44px" },
        onClick: (event) => {
          event.stopPropagation();
          event.preventDefault();
          const next = !isOn;
          try { window.localStorage.setItem("whale-moe:" + prefKey, next ? "1" : "0"); } catch (e) {}
          setIsOn(next);
          window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: prefKey, value: next ? "1" : "0" } }));
        },
        children: jsx("span", { style: { background: "#fff", borderRadius: "50%", boxShadow: "0 1px 3px rgb(0 0 0 / 25%)", height: "18px", width: "18px" } })
      }) ] });
    }
    function MascotTitleRow({ compact }) {
      return jsxs("label", { style: compact ? { alignItems: "center", display: "flex", gap: "12px", justifyContent: "space-between", padding: "2px 0" } : MASCOT_ROW_STYLE, children: [jsx("span", { children: "如何称呼我" }), jsx("input", {
        type: "text",
        defaultValue: MascotValue("title", "主人"),
        maxLength: 8,
        placeholder: "主人",
        style: { flex: 1, maxWidth: "150px", minWidth: 0 },
        onChange: (event) => {
          try { window.localStorage.setItem("whale-moe:title", event.target.value); } catch (e) {}
          window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: "title", value: event.target.value } }));
        }
      }) ] });
    }
    /* 自定义自称：与「如何称呼我」成对，留空回落到默认的「鲸鱼娘」。 */
    function MascotSelfNameRow({ compact }) {
      return jsxs("label", { style: compact ? { alignItems: "center", display: "flex", gap: "12px", justifyContent: "space-between", padding: "2px 0" } : MASCOT_ROW_STYLE, children: [jsx("span", { children: "她的自称" }), jsx("input", {
        type: "text",
        defaultValue: MascotValue("selfName", "鲸鱼娘"),
        maxLength: 12,
        placeholder: "鲸鱼娘",
        style: { flex: 1, maxWidth: "150px", minWidth: 0 },
        onChange: (event) => {
          try { window.localStorage.setItem("whale-moe:selfName", event.target.value); } catch (e) {}
          window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: "selfName", value: event.target.value } }));
        }
      }) ] });
    }
    function MascotWeatherRow() {
      const [status, setStatus] = React.useState("");
      const [busy, setBusy] = React.useState(false);
      const save = (key, value) => {
        try { window.localStorage.setItem("whale-moe:" + key, value); } catch (e) {}
        window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key, value } }));
      };
      const testNow = () => {
        setBusy(true);
        setStatus("⏳ 正在连接 Open-Meteo…");
        const city = window.localStorage.getItem("whale-moe:weatherCity") || "";
        const key = window.localStorage.getItem("whale-moe:weatherKey") || "";
        const p = window.DshWhaleMoeWeatherTest ? window.DshWhaleMoeWeatherTest(city, key) : Promise.reject(new Error("天气服务未就绪"));
        p.then((text) => { setStatus(text); setBusy(false); }, (error) => {
          setStatus("❌ 连接失败：" + (error && error.message ? error.message : "未知错误") + "（无 Key 也可用）");
          setBusy(false);
        });
      };
      return jsxs("div", { style: { display: "flex", flexDirection: "column", width: "100%" }, children: [
        jsxs("label", { style: MASCOT_ROW_STYLE, children: [jsx("span", { children: "天气城市" }), jsx("input", {
          type: "text",
          defaultValue: MascotValue("weatherCity", ""),
          placeholder: "如：上海（留空不联网）",
          maxLength: 24,
          onChange: (event) => save("weatherCity", event.target.value)
        })] }),
        jsxs("label", { style: MASCOT_ROW_STYLE, children: [jsx("span", { children: "API Key（选填）" }), jsx("input", {
          type: "password",
          defaultValue: MascotValue("weatherKey", ""),
          placeholder: "Open-Meteo 免费无需 Key",
          maxLength: 128,
          onChange: (event) => save("weatherKey", event.target.value)
        })] }),
        jsxs("div", { style: { ...MASCOT_ROW_STYLE, borderBottom: "none", flexWrap: "wrap" }, children: [
          jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", lineHeight: "16px", wordBreak: "break-all" }, children: status }),
          jsx("button", { type: "button", disabled: busy, onClick: testNow, children: busy ? "测试中…" : "测试连接" })
        ] })
      ]});
    }
    function MascotStatRow({ label, value, suffix }) {
      return jsxs("label", { style: MASCOT_ROW_STYLE, children: [jsx("span", { children: label }), jsx("span", { children: String(value) + (suffix || "") })] });
    }
    const MASCOT_ACHIEVEMENTS = [
      ["first-pat", "🫳", "初次摸头", "第一次摸 鲸鱼娘的头"], ["ten-pats", "🖐️", "摸头十连", "累计摸头 10 次"], ["hundred-pats", "💯", "摸头百连", "累计摸头 100 次"],
      ["first-feed", "🍰", "投喂成功", "第一次投喂小点心"], ["first-triple", "🎉", "三连击", "触发比心彩蛋"], ["thanks", "💬", "嘴甜", "对 鲸鱼娘说谢谢"],
      ["lv5", "⭐", "五级", "好感度达到 Lv5"], ["lv10", "👑", "十级", "好感度达到 Lv10"], ["signin3", "📅", "常客", "连续签到 3 天"],
      ["signin7", "🗓️", "一周之约", "连续签到 7 天"], ["night-owl", "🌙", "深夜陪伴", "深夜互动一次"], ["comeback", "👋", "欢迎回来", "久别重逢"],
      ["day1", "💞", "一日之缘", "陪伴满 1 天"], ["day7", "💎", "一周相伴", "陪伴满 7 天"], ["day30", "🏛️", "三十日契约", "陪伴满 30 天"],
      ["first-tool", "🛠️", "开工啦", "第一次工具运行"], ["tools-10", "🔧", "工具十连", "工具运行 10 次"], ["tools-50", "🏭", "工具五十连", "工具运行 50 次"], ["tools-100", "🛰️", "工具百连", "工具运行 100 次"],
      ["first-code", "💻", "代码初体验", "第一次代码/终端"], ["code-20", "📟", "代码狂人", "代码/终端 20 个"], ["first-success", "✅", "旗开得胜", "第一次任务完成"],
      ["success-10", "🏆", "任务十连", "任务完成 10 次"], ["first-failure", "🩹", "初次翻车", "第一次任务报错"], ["fail-10", "🚑", "翻车十连", "任务报错 10 次"],
      ["messages-100", "💌", "会话百条", "会话消息 100 条"], ["messages-500", "📚", "消息五百条", "会话消息 500 条"], ["keyword-master", "🔍", "关键词大师", "关键词互动 10 次"],
      ["night-work", "🦉", "深夜赶工", "深夜工具仍在运行"], ["balance-low", "🪙", "余额告急", "触发余额不足提醒"],
      ["game-first", "🫧", "初次开玩", "第一次结算一局小游戏"], ["game-win", "👑", "泡泡之王", "单局戳泡泡得分达到 300"], ["game-combo10", "🔥", "连击达人", "单局最高连击达到 10"], ["game-highscore", "🏆", "纪录刷新", "打破一次历史最高分"],
      ["quest-first", "🎯", "任务初体验", "完成第一个每日任务"], ["quest-all", "🎟️", "一日全勤", "单日 3 个每日任务全部领取"], ["week-signin7", "🏆", "周常满勤", "本周签到板集满 7 格"],
      ["bond-action", "🌟", "新动作解锁", "好感度达到 Lv3"], ["bond-badge", "🎖️", "称号首解锁", "好感度达到 Lv5"]
    ];
    function MascotAchievementWall({ ids }) {
      const unlocked = ids.length;
      return jsxs("div", { style: { alignItems: "flex-start", display: "flex", flexDirection: "column", gap: "8px", padding: "4px 0 10px", width: "100%" }, children: [
        jsxs("div", { style: { display: "flex", justifyContent: "space-between", width: "100%" }, children: [jsx("span", { children: "成就墙" }), jsx("span", { children: unlocked + " / " + MASCOT_ACHIEVEMENTS.length })] }),
        jsx("div", { style: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(88px, 1fr))", gap: "6px", width: "100%" }, children: MASCOT_ACHIEVEMENTS.map(([id, icon, name]) => {
          const on = ids.indexOf(id) !== -1;
          return jsxs("div", { title: name, style: { alignItems: "center", background: on ? "var(--dsw-alias-interactive-bg-hover)" : "transparent", border: "1px solid var(--dsw-alias-border-l2)", borderRadius: "10px", display: "flex", flexDirection: "column", gap: "2px", opacity: on ? 1 : 0.38, padding: "6px 4px", textAlign: "center" }, children: [jsx("span", { style: { fontSize: "16px" }, children: icon }), jsx("span", { style: { fontSize: "11px", lineHeight: "14px" }, children: name })] });
        }) })
      ]});
    }
    function MascotBar({ label, value, text, max }) {
      const pct = Math.max(0, Math.min(100, Math.round((Number(value) || 0) / (Number(max) || 100) * 100)));
      return jsxs("div", { style: { alignItems: "center", display: "flex", gap: "10px", padding: "2px 0" }, children: [
        jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", minWidth: "58px" }, children: label }),
        jsx("div", { style: { background: "var(--dsw-alias-border-l3, #c9cdd6)", borderRadius: "4px", flex: 1, height: "6px", overflow: "hidden" }, children: jsx("div", { style: { background: "var(--dsw-static-accent, #4da3ff)", borderRadius: "4px", height: "100%", transition: "width 160ms ease", width: pct + "%" } }) }),
        jsx("span", { style: { fontSize: "12px", fontWeight: "600", minWidth: "44px", textAlign: "right" }, children: text })
      ] });
    }
    function MascotOverviewCard() {
      const [tick, setTick] = React.useState(0);
      React.useEffect(() => {
        const refresh = () => setTick((v) => v + 1);
        window.addEventListener("whale-moe-prefs-change", refresh);
        window.addEventListener("storage", refresh);
        return () => { window.removeEventListener("whale-moe-prefs-change", refresh); window.removeEventListener("storage", refresh); };
      }, []);
      const mood = MascotValue("mood", "70");
      const affinity = MascotValue("affinity", "0");
      const level = MascotValue("level", "1");
      const streak = MascotValue("signinStreak", "0");
      const since = Number(MascotValue("companionSince", ""));
      const days = since > 0 ? Math.max(0, Math.floor((Date.now() - since) / 86400000)) : 0;
      const chips = [["😊", String(mood), "心情"], ["💗", String(affinity), "好感度"], ["⭐", "Lv." + level, "等级"], ["📅", streak + " 天", "签到"], ["⏳", days + " 天", "陪伴"]];
      return jsxs("div", { style: { background: "var(--dsw-alias-bg-module-platform, transparent)", border: "1px solid var(--dsw-alias-border-l2)", borderRadius: "12px", margin: "10px auto 0", padding: "8px 14px", width: "95%" }, children: [
        jsx("div", { style: { display: "flex", gap: "6px", width: "100%" }, children: chips.map(([icon, value, label]) => jsxs("div", { style: { alignItems: "center", background: "var(--dsw-alias-interactive-bg-hover, transparent)", border: "1px solid var(--dsw-alias-border-l2)", borderRadius: "8px", display: "flex", flex: 1, flexDirection: "column", gap: "1px", minWidth: 0, overflow: "hidden", padding: "4px 2px" }, children: [
          jsxs("span", { style: { fontSize: "11px", fontWeight: "600", lineHeight: "15px", maxWidth: "100%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, children: [icon, " ", value] }),
          jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "10px", lineHeight: "13px", maxWidth: "100%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, children: label })
        ] })) }),
        jsx("div", { style: { background: "var(--dsw-alias-border-l2)", height: "1px", margin: "8px 0 2px" } }),
        jsx(MascotTitleRow, { compact: true }),
        jsx(MascotSelfNameRow, { compact: true })
      ] });
    }
    function hasMimoTts(ctx) {
      return typeof ctx?.get?.("xiaomiMimoTts")?.play === "function";
    }
    function MascotSwitchGrid({ ctx }) {
      /* 两个客户端 bundle 的启动顺序不固定。仅在设置面板挂载时短暂重试：
         插件安装本身需要重启 Web，因此没有必要持续探测未安装的插件。 */
      const [mimoTtsAvailable, setMimoTtsAvailable] = React.useState(() => hasMimoTts(ctx));
      React.useEffect(() => {
        if (hasMimoTts(ctx)) {
          setMimoTtsAvailable(true);
          return undefined;
        }
        let attempts = 0;
        const timer = window.setInterval(() => {
          const available = hasMimoTts(ctx);
          attempts += 1;
          if (available || attempts >= 10) {
            setMimoTtsAvailable(available);
            window.clearInterval(timer);
          }
        }, 250);
        return () => window.clearInterval(timer);
      }, [ctx]);
      const rows = [
        { label: "鲸鱼娘", prefKey: "pet" },
        { label: "台词气泡", prefKey: "chat" },
        { label: "粒子效果", prefKey: "particles" },
        ...(mimoTtsAvailable ? [{ label: "台词播报 (MiMoTTs)", prefKey: "mimoTts" }] : []),
        { label: "小游戏", prefKey: "game" },
        { label: "关键词感知", prefKey: "keywords" },
        { label: "摸鱼提醒", prefKey: "idle-nudge" },
        { label: "深夜模式", prefKey: "night" },
        { label: "天气特效", prefKey: "weatherFx" },
        { label: "工具细分", prefKey: "toolPose" },
        { label: "拖拽惯性", prefKey: "dragPhysics" },
        { label: "主动关怀", prefKey: "proactive" },
        { label: "无障碍", prefKey: "a11y" },
        { label: "余额关心", prefKey: "balance" },
        { label: "余额显示数字", prefKey: "balanceDetail" }
      ];
      return jsx("div", { style: { display: "grid", gap: "2px 14px", gridTemplateColumns: "1fr 1fr", padding: "2px 0 8px", width: "100%" }, children: rows.map((r) => jsx(MascotPrefRow, { key: r.prefKey, label: r.label, prefKey: r.prefKey, compact: true })) });
    }
    /* 余额显示：数据由桌宠侧轮询本机代理后写入 window.__dshWhaleMoeBalance。
       未开启「余额关心」或代理不可用时给出说明，不报错。 */
    function MascotBalanceRow() {
      const [text, setText] = React.useState("—");
      const [tier, setTier] = React.useState("");
      React.useEffect(() => {
        let timer = 0;
        const read = () => {
          const on = MascotValue("balance", "0") !== "0";
          const detailed = MascotValue("balanceDetail", "0") !== "0";
          if (!on) { setText("未开启"); setTier(""); return; }
          const b = window.__dshWhaleMoeBalance;
          if (!b || b.ok !== true) { setText("暂未获取到"); setTier("余额代理可能未运行"); return; }
          const fmt = window.DshWhaleMoeCore && window.DshWhaleMoeCore.formatBalance;
          setText(fmt ? fmt(b.amount, b.currency, detailed) : String(b.amount));
          const labels = { empty: "已见底", critical: "告急", low: "偏紧", ok: "正常", good: "充裕", rich: "很充裕" };
          setTier(detailed ? (labels[b.tier] || "") : "");
        };
        read();
        timer = window.setInterval(read, 5000);
        const onChange = () => read();
        window.addEventListener("whale-moe-prefs-change", onChange);
        return () => {
          window.clearInterval(timer);
          window.removeEventListener("whale-moe-prefs-change", onChange);
        };
      }, []);
      return jsxs("div", { style: { display: "flex", flexDirection: "column", gap: "2px", padding: "4px 0 6px", width: "100%" }, children: [
        jsxs("label", { style: MASCOT_ROW_STYLE, children: [
          jsx("span", { children: "账户余额" }),
          jsxs("span", { style: { display: "flex", alignItems: "baseline", gap: "6px", justifyContent: "flex-end" }, children: [
            jsx("span", { style: { fontSize: "14px", fontWeight: "600" }, children: text }),
            tier ? jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px" }, children: tier }) : null
          ] })
        ] }),
        jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px", lineHeight: "15px", padding: "0 0 4px" }, children: "数据来自本机余额代理（127.0.0.1:3020），仅在本机读取，不上报。关闭「余额显示数字」只显示档位。" })
      ] });
    }
    function formatWhen(at) {
      const then = Number(at);
      if (!isFinite(then) || then <= 0) return "";
      const diff = Date.now() - then;
      const day = 86400000;
      if (diff < 60000) return "刚刚";
      if (diff < 3600000) return Math.floor(diff / 60000) + " 分钟前";
      if (diff < day) return Math.floor(diff / 3600000) + " 小时前";
      if (diff < day * 30) return Math.floor(diff / day) + " 天前";
      const d = new Date(then);
      return (d.getMonth() + 1) + " 月 " + d.getDate() + " 日";
    }
    /* 成长日记：读 whale-moe:journal，倒序渲染最近若干条。 */
    function MascotJournalRow() {
      const [entries, setEntries] = React.useState([]);
      React.useEffect(() => {
        const read = () => {
          try {
            const raw = window.localStorage.getItem("whale-moe:journal");
            const list = raw ? JSON.parse(raw) : [];
            setEntries(Array.isArray(list) ? list.slice().reverse() : []);
          } catch (e) { setEntries([]); }
        };
        read();
        const onChange = () => read();
        window.addEventListener("whale-moe-prefs-change", onChange);
        window.addEventListener("storage", onChange);
        return () => {
          window.removeEventListener("whale-moe-prefs-change", onChange);
          window.removeEventListener("storage", onChange);
        };
      }, []);
      if (!entries.length) {
        return jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", lineHeight: "16px", padding: "4px 0" }, children: "还没有记录。陪她久一点，这里会慢慢长出回忆。" });
      }
      const icons = { bond: "💞", achievement: "🏅", first: "🎉" };
      return jsx("div", { style: { display: "flex", flexDirection: "column", gap: "7px", padding: "4px 0 6px", width: "100%" }, children: entries.slice(0, 12).map((e, i) => jsxs("div", { key: i, style: { display: "flex", gap: "8px", alignItems: "flex-start" }, children: [
        jsx("span", { style: { fontSize: "12px", lineHeight: "18px", flex: "none" }, children: icons[e.kind] || "•" }),
        jsxs("div", { style: { display: "flex", flexDirection: "column", minWidth: 0, flex: 1 }, children: [
          jsx("span", { style: { fontSize: "12px", lineHeight: "16px" }, children: String(e.text || "") }),
          jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "10px", lineHeight: "14px" }, children: formatWhen(e.at) })
        ] })
      ] })) });
    }
    function MascotDailyQuests() {
      const [tick, setTick] = React.useState(0);
      React.useEffect(() => {
        const refresh = () => setTick((v) => v + 1);
        window.addEventListener("whale-moe-prefs-change", refresh);
        window.addEventListener("storage", refresh);
        return () => { window.removeEventListener("whale-moe-prefs-change", refresh); window.removeEventListener("storage", refresh); };
      }, []);
      const pool = (window.DshWhaleMoeCore && window.DshWhaleMoeCore.QUEST_POOL) || [];
      const defOf = (id) => pool.find((q) => q.id === id) || { id, desc: id, target: 1, reward: { affinity: 0, mood: 0 } };
      let quests = null;
      try { const raw = window.localStorage.getItem("whale-moe:quests"); quests = raw ? JSON.parse(raw) : null; } catch (e) { quests = null; }
      const today = (() => { const d = new Date(); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate(); })();
      const slots = quests && quests.date === today && Array.isArray(quests.slots) ? quests.slots : [];
      const claim = (id) => {
        try { if (window.__dshWhaleMoeClaimQuest) window.__dshWhaleMoeClaimQuest(id); } catch (e) {}
        setTick((v) => v + 1);
      };
      if (!slots.length) return jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", padding: "4px 0" }, children: "今日任务加载中，稍后自动刷新" });
      return jsx("div", { style: { display: "flex", flexDirection: "column", padding: "2px 0 4px", width: "100%" }, children: slots.map((slot, index) => {
        const def = defOf(slot.id);
        const done = slot.progress >= def.target;
        const last = index === slots.length - 1;
        return jsxs("div", { style: { alignItems: "center", borderBottom: last ? "none" : "1px solid var(--dsw-alias-border-l2)", display: "flex", gap: "10px", minHeight: "44px" }, children: [
          jsx("span", { style: { flex: 1, fontSize: "13px", lineHeight: "18px", minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, children: def.desc }),
          jsxs("div", { style: { alignItems: "center", display: "flex", gap: "6px", width: "104px" }, children: [
            jsx("div", { style: { background: "var(--dsw-alias-border-l3, #c9cdd6)", borderRadius: "4px", flex: 1, height: "7px", overflow: "hidden" }, children: jsx("div", { style: { background: done ? "var(--dsw-static-accent, #4da3ff)" : "var(--dsw-alias-label-secondary, #888)", borderRadius: "4px", height: "100%", transition: "width 160ms ease", width: Math.min(100, Math.round(slot.progress / def.target * 100)) + "%" } }) }),
            jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px", lineHeight: "14px", whiteSpace: "nowrap" }, children: String(Math.min(slot.progress, def.target)) + "/" + String(def.target) })
          ] }),
          slot.claimed
            ? jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", textAlign: "right", width: "58px" }, children: "✅ 已领" })
            : jsx("button", { type: "button", disabled: !done, onClick: () => claim(slot.id), style: { background: done ? "var(--dsw-static-accent, #4da3ff)" : "transparent", border: "1px solid var(--dsw-alias-border-l3, #c9cdd6)", borderRadius: "8px", color: done ? "#fff" : "var(--dsw-alias-label-secondary)", cursor: done ? "pointer" : "default", fontSize: "12px", height: "26px", padding: "0 10px", width: "58px" }, children: "领取" })
        ] });
      }) });
    }
    function MascotWeekSignin() {
      const [tick, setTick] = React.useState(0);
      React.useEffect(() => {
        const refresh = () => setTick((v) => v + 1);
        window.addEventListener("whale-moe-prefs-change", refresh);
        return () => window.removeEventListener("whale-moe-prefs-change", refresh);
      }, []);
      let week = null;
      try { const raw = window.localStorage.getItem("whale-moe:weekSignin"); week = raw ? JSON.parse(raw) : null; } catch (e) { week = null; }
      const days = week && Array.isArray(week.days) ? week.days.length : 0;
      const labels = ["一", "二", "三", "四", "五", "六", "日"];
      return jsxs("div", { style: { display: "flex", flexDirection: "column", gap: "10px", padding: "4px 0 10px", width: "100%" }, children: [
        jsx("div", { style: { display: "flex", gap: "4px" }, children: Array.from({ length: 7 }, (_, i) => jsxs("div", { style: { alignItems: "center", display: "flex", flex: 1, flexDirection: "column", gap: "4px" }, children: [
          jsx("span", { style: { alignItems: "center", background: i < days ? "var(--dsw-static-accent, #4da3ff)" : "var(--dsw-alias-border-l3, #c9cdd6)", borderRadius: "50%", color: i < days ? "#fff" : "transparent", display: "flex", fontSize: "12px", height: "26px", justifyContent: "center", width: "26px" }, children: "✓" }),
          jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px", lineHeight: "14px" }, children: labels[i] })
        ] })) }),
        jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", lineHeight: "16px" }, children: "本周已签到 " + days + " / 7 天 · 集满 1/3/7 天有里程碑奖励" })
      ] });
    }
    function MascotBadgeRow() {
      const [tick, setTick] = React.useState(0);
      React.useEffect(() => {
        const refresh = () => setTick((v) => v + 1);
        window.addEventListener("whale-moe-prefs-change", refresh);
        return () => window.removeEventListener("whale-moe-prefs-change", refresh);
      }, []);
      const level = Number(MascotValue("level", "1")) || 1;
      const badges = (window.DshWhaleMoeCore && window.DshWhaleMoeCore.BOND && window.DshWhaleMoeCore.BOND.badges) || [];
      const unlocked = badges.filter((b) => level >= b.minLevel);
      const current = MascotValue("badge", "");
      if (!unlocked.length) return jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "12px", padding: "4px 0" }, children: "未解锁（好感度 Lv5 解锁首个称号）" });
      return jsxs("label", { style: { ...MASCOT_ROW_STYLE, borderBottom: "none" }, children: [jsx("span", { children: "称号" }), jsx("select", {
        value: current,
        onChange: (event) => { const value = event.target.value; try { if (window.__dshWhaleMoeApplyBadge) window.__dshWhaleMoeApplyBadge(value); else window.localStorage.setItem("whale-moe:badge", value); } catch (e) {} setTick((v) => v + 1); },
        children: [jsx("option", { value: "", children: "（不使用称号）" })].concat(unlocked.map((b) => jsx("option", { value: b.id, children: b.name })))
      }) ] });
    }
    function MascotAccordion({ title, icon, summary, defaultOpen, children }) {
      const [open, setOpen] = React.useState(!!defaultOpen);
      const left = jsxs("span", { style: { alignItems: "center", display: "flex", gap: "8px", minWidth: 0 }, children: [
        jsx("span", { style: { fontSize: "14px" }, children: icon || "" }),
        jsxs("span", { style: { alignItems: "flex-start", display: "flex", flexDirection: "column", minWidth: 0 }, children: [
          jsx("span", { style: { fontSize: "13px", fontWeight: "600" }, children: title }),
          summary ? jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px", fontWeight: "400" }, children: summary }) : null
        ] })
      ] });
      const right = jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px" }, children: open ? "▾" : "▸" });
      return jsxs("div", { style: { background: "var(--dsw-alias-bg-module-platform, transparent)", border: "1px solid var(--dsw-alias-border-l2)", borderRadius: "12px", marginTop: "10px", overflow: "hidden", width: "100%" }, children: [
        jsxs("button", { type: "button", onClick: () => setOpen(!open), style: { alignItems: "center", background: "transparent", border: "none", color: "inherit", cursor: "pointer", display: "flex", justifyContent: "space-between", padding: "10px 14px", width: "100%" }, children: [left, right] }),
        open ? jsx("div", { style: { padding: "0 14px 8px" }, children }) : null
      ] });
    }
    function MascotTabs({ active, onChange, tabs }) {
      const list = tabs || [{ id: "quests", label: "今日任务" }, { id: "week", label: "本周签到" }];
      return jsx("div", { style: { background: "var(--dsw-alias-interactive-bg-hover, transparent)", borderRadius: "10px", display: "flex", gap: "4px", marginBottom: "8px", padding: "3px" }, children: list.map((t) => jsx("button", { key: t.id, type: "button", onClick: () => onChange(t.id), style: { background: active === t.id ? "var(--dsw-static-accent, #4da3ff)" : "transparent", border: "none", borderRadius: "8px", color: active === t.id ? "#fff" : "inherit", cursor: "pointer", flex: 1, fontSize: "13px", padding: "6px 0" }, children: t.label })) });
    }
    function MascotDailyCard() {
      const [tab, setTab] = React.useState("quests");
      return jsxs(MascotAccordion, { title: "日常与养成", icon: "🎯", summary: "任务、签到与称号", defaultOpen: false, children: [
        jsx(MascotTabs, { active: tab, onChange: setTab, tabs: [{ id: "quests", label: "今日任务" }, { id: "week", label: "本周签到" }, { id: "badge", label: "称号" }] }),
        tab === "quests" ? jsx(MascotDailyQuests, {}) : (tab === "week" ? jsx(MascotWeekSignin, {}) : jsx(MascotBadgeRow, {}))
      ] });
    }
    function MascotAchievementRow() {
      const ids = MascotValue("achievements", "").split(",").filter(Boolean);
      return jsx(MascotAchievementWall, { ids });
    }
    function MascotResetRow() {
      return jsxs("label", { style: MASCOT_ROW_STYLE, children: [jsx("span", { children: "悬浮位置" }), jsx("button", { type: "button", onClick: () => { try { window.localStorage.removeItem("whale-moe:floatX"); window.localStorage.removeItem("whale-moe:floatY"); } catch (e) {} window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: "float-reset", value: true } })); }, children: "重置到默认位置" })] });
    }
    function MascotGrowthResetRow() {
      return jsxs("label", { style: MASCOT_ROW_STYLE, children: [jsx("span", { children: "养成数据" }), jsx("button", { type: "button", onClick: () => { ["mood", "affinity", "satiety", "lastSignin", "signinStreak", "achievements", "companionSince", "level", "quests", "weekSignin", "badge", "gameStats"].forEach((k) => { try { window.localStorage.removeItem("whale-moe:" + k); } catch (e) {} }); window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: "growth-reset", value: true } })); }, children: "重置养成" })] });
    }
    function MascotPrefRows({ ctx }) {
      return jsxs("div", { style: { display: "flex", flexDirection: "column", width: "100%" }, children: [
        jsx(MascotOverviewCard, {}),
        jsxs(MascotAccordion, { title: "陪伴表现", icon: "🎛️", summary: "鲸鱼娘怎么出现、怎么说话", defaultOpen: true, children: [jsx(MascotSwitchGrid, { ctx })] }),
        jsx(MascotAccordion, { title: "天气", icon: "⛅", summary: "城市与天气特效", defaultOpen: false, children: [jsx(MascotWeatherRow, {}), jsx("span", { style: { color: "var(--dsw-alias-label-secondary)", fontSize: "11px", lineHeight: "15px", padding: "0 0 6px" }, children: "特效需已填写城市、且天气数据新鲜时才会显示；工作繁忙时自动减弱，雷闪停播。" })] }),
        jsx(MascotAccordion, { title: "余额", icon: "🪙", summary: "账户余额与播报", defaultOpen: false, children: [jsx(MascotBalanceRow, {})] }),
        jsx(MascotDailyCard, {}),
        jsx(MascotAccordion, { title: "成就墙", icon: "🏅", summary: "已解锁 " + MascotValue("achievements", "").split(",").filter(Boolean).length + " / " + MASCOT_ACHIEVEMENTS.length, defaultOpen: false, children: [jsx(MascotAchievementRow, {})] }),
        jsx(MascotAccordion, { title: "成长日记", icon: "📖", summary: "和 " + MascotValue("selfName", "鲸鱼娘") + " 的回忆", defaultOpen: false, children: [jsx(MascotJournalRow, {})] }),
        jsx(MascotAccordion, { title: "数据与重置", icon: "🗂️", summary: "位置与养成数据", defaultOpen: false, children: [jsx(MascotResetRow, {}), jsx(MascotGrowthResetRow, {})] })
      ]});
    }
    /* 设置面板内容优先走子 slot 渲染（settings.mascot.item，可被其他插件扩展）；
       renderSlot 缺失或抛错时直接回落到 MascotPrefRows，保证任何宿主版本下面板都不空白。 */
    function MascotSection(props) {
      const ctx = props && props.ctx;
      const renderSlot = props && typeof props.renderSlot === "function" ? props.renderSlot : null;
      if (renderSlot !== null) {
        try {
          const rendered = renderSlot("settings.mascot.item", {});
          if (rendered !== null && rendered !== undefined) {
            return jsx("div", { style: { display: "flex", flexDirection: "column", width: "100%" }, children: rendered });
          }
        } catch (e) {
          console.warn("[dsh-whale-musume] settings.mascot.item 渲染失败，回落到内置面板", e);
        }
      }
      return jsx(MascotPrefRows, { ctx });
    }

    function registerMimoTtsBridge(ctx) {
      ctx.effect(() => {
        const playInteractionLine = (event) => {
          const enabled = MascotValue("mimoTts", "0") !== "0";
          const text = event && event.detail && typeof event.detail.text === "string" ? event.detail.text.trim() : "";
          if (!enabled || text.length === 0) return;
          const tts = ctx.get("xiaomiMimoTts");
          if (tts === undefined || typeof tts.play !== "function") return;
          try {
            const playback = tts.play(text);
            if (playback && typeof playback.catch === "function") playback.catch(() => {});
          } catch {
            /* 可选播放失败不影响桌宠交互。 */
          }
        };
        window.addEventListener(MIMO_TTS_EVENT, playInteractionLine);
        return () => window.removeEventListener(MIMO_TTS_EVENT, playInteractionLine);
      }, "dsh-whale-musume: 可选 MiMo TTS 桥接");
    }

    function registerSettings(ctx) {
      const slots = ctx.get("slots");
      if (slots === undefined) {
        console.warn("[dsh-whale-musume] slots 服务不可用，跳过设置面板注册（桌宠本体不受影响）");
        return;
      }
      slots.inject("settings.section", () => slots.register(
        { name: "settings.section", id: "mascot", order: 6, label: "看板娘", children: { "settings.mascot.item": { kind: "list", scope: "root" } } },
        (props) => jsx(MascotSection, { ...props, ctx })
      ));
      slots.inject("settings.mascot.item", () => slots.register(
        { name: "settings.mascot.item", id: "mascot-prefs", order: 0 },
        () => jsx(MascotPrefRows, { ctx })
      ));
    }

    function apply(ctx) {
      /* 此桥接完全可选：既不注入也不强制依赖 MiMo TTS。 */
      try {
        registerMimoTtsBridge(ctx);
      } catch (e) {
        console.warn("[dsh-whale-musume] MiMo TTS 联动注册失败，桌宠本体不受影响", e);
      }
      /* 设置面板是增强项：注册失败也要保证桌宠本体正常出现。 */
      try {
        registerSettings(ctx);
      } catch (e) {
        console.warn("[dsh-whale-musume] 设置面板注册失败，桌宠本体不受影响", e);
      }
    }


    /* ==================================================================
       dsh-whale-notify：桌面提醒联动（宿主引擎在 lib/notify.js）
         · 焦点心跳：告诉宿主「我正看着哪个对话」，它才决定要不要吵你
         · 点击唤起：接住宿主的长轮询，切到通知对应的对话并滚到最新
         · 提醒联动：轮询宿主取待播报的提醒 → 她换姿态 + 冒一句话 + 站内卡片
       ================================================================== */

    /** 宿主引擎注册的同源路由（与上游 dsh-desktop-notify 协议一致）。 */
    const FOCUS_ENDPOINT = "/dsh-desktop-notify/focus";
    const ACTIVATION_ENDPOINT = "/dsh-desktop-notify/activate";
    const ACTIVATED_ENDPOINT = "/dsh-desktop-notify/activated";
    /** 鲸鱼娘增量：待播报提醒的轮询口。 */
    const REACT_ENDPOINT = "/dsh-whale-notify/react";
    const HEARTBEAT_MS = 15000;
    const RETRY_MS = 2000;
    const REACT_POLL_MS = 1200;
    const CARD_MS = 14000;
    const BUBBLE_MS = 7000;
    /** 站内提醒卡片的开关（沿用桌宠的 localStorage 约定）。 */
    const PREF_CARD = "whale-moe:notify-card";
    const TO_BOTTOM_PATTERN = /回到底部|回到最新|返回底部|back to bottom|scroll to (?:bottom|latest|end)/i;

    function notifyPrefOn(key) {
      try { return window.localStorage.getItem(key) !== "0"; } catch (e) { return true; }
    }

    function setNotifyPref(key, on) {
      try { window.localStorage.setItem(key, on ? "1" : "0"); } catch (e) { /* 隐私模式等：忽略 */ }
      try {
        window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key, value: on ? 1 : 0 } }));
      } catch (e) { /* 事件派发失败不影响本体 */ }
    }

    /** 当前显示在主视图里的会话 id（宿主拿它做「你正在看」判定）。 */
    function activeSessionId(sessions) {
      try {
        const list = sessions?.list?.getSnapshot?.();
        if (!list) return undefined;
        const ids = list.ids ?? Object.keys(list.byId ?? {});
        for (const id of ids) {
          if ((list.byId?.[id]?.retainedBy?.mainView ?? 0) > 0) return id;
        }
      } catch (e) { /* 取不到就让宿主按「没在看」处理，宁可多提醒一次 */ }
      return undefined;
    }

    /** 找「回到底部」按钮点一下，让 DSH 自己的滚动逻辑处理虚拟列表。 */
    function clickToBottomButton() {
      const looksLike = (node) => {
        const label =
          node.getAttribute("aria-label") ||
          node.getAttribute("title") ||
          (node.textContent?.trim().length <= 10 ? node.textContent.trim() : "") ||
          "";
        return label !== "" && TO_BOTTOM_PATTERN.test(label);
      };
      for (const node of document.querySelectorAll('button, [role="button"]')) {
        if (looksLike(node)) { node.click(); return true; }
      }
      for (const node of document.querySelectorAll("[aria-label]")) {
        if (looksLike(node)) { node.click(); return true; }
      }
      return false;
    }

    /** 退化方案：把最长的可滚动容器拉到底并补发 scroll 事件。 */
    function scrollLargestContainer() {
      let best = null;
      let bestHeight = 0;
      for (const node of document.querySelectorAll("div, section, main")) {
        const overflow = node.scrollHeight - node.clientHeight;
        if (overflow > 80 && node.scrollHeight > bestHeight) { best = node; bestHeight = node.scrollHeight; }
      }
      if (!best) return false;
      best.scrollTop = best.scrollHeight;
      best.dispatchEvent(new Event("scroll", { bubbles: true }));
      return true;
    }

    function scrollToLatest() {
      for (const delay of [0, 300, 700, 1200, 2000]) {
        window.setTimeout(() => {
          try { if (!clickToBottomButton()) scrollLargestContainer(); } catch (e) { /* 尽力而为 */ }
        }, delay);
      }
    }

    function reportActivated(sessionId, opened) {
      try {
        fetch(ACTIVATED_ENDPOINT, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ sessionId, opened, at: Date.now() }),
          keepalive: true
        }).catch(() => {});
      } catch (e) { /* 回执失败无所谓 */ }
    }

    /** 切到宿主点名要看的会话；失败只影响「跳对话」，不影响提醒本身。 */
    function openSession(ctx, uiWorkspace, sessionId) {
      const workspace = uiWorkspace ?? ctx.get?.("uiWorkspace");
      if (!workspace || typeof workspace.openSession !== "function") {
        console.warn("[dsh-whale-notify] uiWorkspace.openSession 不可用，只能唤起窗口");
        return false;
      }
      try { workspace.openSession(sessionId); return true; } catch (error) {
        console.error("[dsh-whale-notify] openSession failed", error);
        return false;
      }
    }

    /* ---------------- 她换姿态 / 冒一句话 ---------------- */

    /** 官方口：window.DshWhaleMoeMood(kind, duration, animate)，kind 就是立绘 id。 */
    function whalePose(pose, ms) {
      try {
        const mood = window.DshWhaleMoeMood;
        if (typeof mood === "function" && pose) mood(pose, ms || BUBBLE_MS, true);
      } catch (e) { /* 表现层没起来就当没有 */ }
    }

    /** 台词气泡没有公开 API，直接写 presenter 的气泡 DOM 并周期复写（它有过期定时器）。 */
    function whaleSay(line, ms) {
      if (!line) return;
      const until = Date.now() + (ms || BUBBLE_MS);
      const paint = () => {
        const bubble = document.querySelector("[data-dsh-whale-bubble]");
        const text = document.querySelector("[data-dsh-whale-bubble-text]");
        if (!bubble || !text) return false;
        text.textContent = line;
        bubble.hidden = false;
        bubble.classList.remove("dsh-whale-out");
        bubble.classList.add("dsh-whale-pop");
        return Date.now() < until;
      };
      if (!paint()) return;
      const timer = window.setInterval(() => { if (!paint()) window.clearInterval(timer); }, 700);
    }

    /* ---------------- 站内提醒卡片（她举着的那块牌子） ---------------- */

    let whaleCard = null;
    let whaleCardTimer = 0;

    function ensureCardStyles() {
      if (document.querySelector("style[data-dsh-whale-notify-style]")) return;
      const style = document.createElement("style");
      style.setAttribute("data-dsh-whale-notify-style", "");
      style.textContent = [
        "[data-dsh-whale-notify-card]{position:fixed;right:236px;bottom:26px;z-index:61;width:344px;max-width:calc(100vw - 268px);box-sizing:border-box;padding:14px 16px 12px;border-radius:16px;border:1px solid rgba(56,189,248,.38);background:linear-gradient(158deg,rgba(6,24,44,.97),rgba(11,45,76,.97));color:#e8f6ff;font-size:12.5px;line-height:1.55;font-family:var(--dsw-font-family,'Microsoft YaHei',system-ui,sans-serif);box-shadow:0 20px 50px rgba(2,10,24,.6),inset 0 0 0 1px rgba(56,189,248,.12);backdrop-filter:blur(12px);animation:wn-card-in .34s cubic-bezier(.2,.9,.25,1);transition:opacity .22s ease,transform .22s ease}",
        "[data-dsh-whale-notify-card][data-wm-theme=light]{background:linear-gradient(158deg,rgba(240,249,255,.98),rgba(214,238,255,.98));color:#08243d;border-color:rgba(14,116,144,.34);box-shadow:0 18px 42px rgba(12,44,80,.22),inset 0 0 0 1px rgba(14,116,144,.1)}",
        "[data-dsh-whale-notify-card].wn-out{opacity:0;transform:translateX(24px) scale(.98)}",
        "[data-dsh-whale-notify-card] .wn-head{display:flex;align-items:center;gap:10px;margin-bottom:8px}",
        "[data-dsh-whale-notify-card] .wn-avatar{width:44px;height:44px;border-radius:12px;object-fit:contain;background:rgba(56,189,248,.12);box-shadow:0 6px 18px rgba(2,10,24,.4)}",
        "[data-dsh-whale-notify-card] .wn-kicker{font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;opacity:.62}",
        "[data-dsh-whale-notify-card] .wn-clock{margin-left:auto;font-size:10.5px;opacity:.6}",
        "[data-dsh-whale-notify-card] .wn-line{font-size:14px;font-weight:700;line-height:1.45;color:var(--wn-accent,#38bdf8)}",
        "[data-dsh-whale-notify-card] .wn-detail{margin-top:7px;white-space:pre-wrap;opacity:.86}",
        "[data-dsh-whale-notify-card] .wn-foot{display:flex;gap:8px;align-items:center;margin-top:12px}",
        "[data-dsh-whale-notify-card] button{cursor:pointer;border-radius:10px;border:1px solid transparent;font:inherit;font-size:12px;padding:6px 12px;transition:filter .18s ease,background .18s ease}",
        "[data-dsh-whale-notify-card] button:hover{filter:brightness(1.14)}",
        "[data-dsh-whale-notify-card] .wn-go{background:var(--wn-accent,#38bdf8);color:#04202f;font-weight:700}",
        "[data-dsh-whale-notify-card] .wn-ok{background:transparent;border-color:rgba(148,183,214,.5);color:inherit;opacity:.82}",
        "[data-dsh-whale-notify-card] .wn-bar{position:absolute;left:14px;right:14px;bottom:6px;height:2px;border-radius:2px;background:var(--wn-accent,#38bdf8);opacity:.5;transform-origin:left;animation:wn-bar linear forwards}",
        "@keyframes wn-card-in{from{opacity:0;transform:translateX(30px) scale(.96)}to{opacity:1;transform:none}}",
        "@keyframes wn-bar{from{transform:scaleX(1)}to{transform:scaleX(0)}}"
      ].join("");
      document.head.appendChild(style);
    }

    function hideWhaleCard() {
      if (!whaleCard) return;
      const node = whaleCard;
      whaleCard = null;
      window.clearTimeout(whaleCardTimer);
      node.classList.add("wn-out");
      window.setTimeout(() => { try { node.remove(); } catch (e) {} }, 240);
    }

    /**
     * 亮一张她举着的提醒牌子。
     * @param item - 宿主推来的提醒（cls/line/headline/body/sessionId/accent/pose）。
     */
    function showWhaleCard(item) {
      if (!notifyPrefOn(PREF_CARD)) return;
      ensureCardStyles();
      hideWhaleCard();
      const node = document.createElement("div");
      node.setAttribute("data-dsh-whale-notify-card", "");
      node.setAttribute("role", "alert");
      const accent = typeof item.accent === "string" ? item.accent : "#38BDF8";
      node.style.setProperty("--wn-accent", accent);
      /* 沿用桌宠留出的主题钩子：她是什么皮，牌子就是什么皮 */
      const theme = document.querySelector("[data-dsh-whale-root]")?.getAttribute("data-wm-theme");
      if (theme) node.setAttribute("data-wm-theme", theme);

      const head = document.createElement("div");
      head.className = "wn-head";
      const avatar = document.createElement("img");
      avatar.className = "wn-avatar";
      avatar.alt = "";
      avatar.src = BASE + "notify/avatar-" + (typeof item.cls === "string" ? item.cls : "question") + ".png";
      avatar.addEventListener("error", () => { avatar.style.visibility = "hidden"; });
      const kicker = document.createElement("div");
      const kickerTop = document.createElement("div");
      kickerTop.className = "wn-kicker";
      kickerTop.textContent = "Whale Musume · 桌面提醒";
      const kickerSub = document.createElement("div");
      kickerSub.style.opacity = "0.75";
      kickerSub.textContent = item.headline || "";
      kicker.appendChild(kickerTop);
      kicker.appendChild(kickerSub);
      const clock = document.createElement("div");
      clock.className = "wn-clock";
      clock.textContent = new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
      head.appendChild(avatar);
      head.appendChild(kicker);
      head.appendChild(clock);

      const line = document.createElement("div");
      line.className = "wn-line";
      line.textContent = item.line || "有事情找你～";

      const detail = document.createElement("div");
      detail.className = "wn-detail";
      detail.textContent = item.body || "";

      const foot = document.createElement("div");
      foot.className = "wn-foot";
      if (item.sessionId) {
        const go = document.createElement("button");
        go.className = "wn-go";
        go.type = "button";
        go.textContent = "带我去看 →";
        go.addEventListener("click", () => {
          openSession(null, undefined, item.sessionId);
          scrollToLatest();
          hideWhaleCard();
        });
        foot.appendChild(go);
      }
      const ok = document.createElement("button");
      ok.className = "wn-ok";
      ok.type = "button";
      ok.textContent = "知道了";
      ok.addEventListener("click", hideWhaleCard);
      foot.appendChild(ok);

      const bar = document.createElement("div");
      bar.className = "wn-bar";
      bar.style.animationDuration = CARD_MS + "ms";

      node.appendChild(head);
      node.appendChild(line);
      if (item.body) node.appendChild(detail);
      node.appendChild(foot);
      node.appendChild(bar);
      /* 她旁边已经有审批牌时，提醒牌往上让一格，别叠一起 */
      const approveBox = document.querySelector("[data-dsh-whale-approve]");
      if (approveBox) {
        const rect = approveBox.getBoundingClientRect();
        if (rect.height > 0) node.style.bottom = Math.round(rect.height + 38) + "px";
      }
      document.body.appendChild(node);
      whaleCard = node;
      whaleCardTimer = window.setTimeout(hideWhaleCard, CARD_MS);
    }

    /** 一条提醒的落地演出：姿态 → 台词 → 牌子 → 对外事件（可供其它插件接管）。 */
    function handleReaction(item) {
      if (wnDisposed || !item || typeof item !== "object") return;
      whalePose(typeof item.pose === "string" ? item.pose : "curious", BUBBLE_MS);
      whaleSay(typeof item.line === "string" ? item.line : "", BUBBLE_MS);
      /* 提醒只出在她身上：应用内不再亮牌（你要的是桌面上那一只） */
      const INAPP_CARD = false;
      if (INAPP_CARD && typeof document !== "undefined" && document.visibilityState === "visible") showWhaleCard(item);
      const project = wnNoteFromBody(item.body);
      if (project) wnProject = project;
      if (item.cls === "approval") {
        /* 宿主提醒不是可裁决的 request；只有真正接住请求或精确活审批条才能登记 resolver。 */
        petPost({ pose: "wait", line: item.line || "有操作要你点头，点「去查看」打开原会话", sid: item.sessionId || "", note: wnProject, at: Date.now() });
      } else {
        try { petPost({ pose: item.cls === "completion" ? "ok" : (item.cls === "failure" || item.cls === "aborted" ? "err" : "think"), line: String(item.line || ""), sid: item.sessionId || "", note: wnProject, at: Date.now() }); } catch (e) { /* 桌面版不在 */ }
      }
      try {
        window.dispatchEvent(new CustomEvent("dsh-whale-notify:reaction", { detail: item }));
      } catch (e) { /* 监听方出错不该影响提醒 */ }
    }

    /* ---------------- 设置面板：一个「桌面提醒卡片」开关 ---------------- */

    function registerNotifySettings(ctx) {
      const slots = ctx.get?.("slots");
      if (!slots || typeof slots.inject !== "function" || typeof slots.register !== "function") return;
      slots.inject("settings.mascot.item", () => slots.register(
        { name: "settings.mascot.item", id: "mascot-notify", order: 5 },
        () => jsxs("label", {
          style: { alignItems: "center", borderBottom: "1px solid var(--dsw-alias-border-l2)", display: "flex", gap: "12px", justifyContent: "space-between", padding: "10px 0" },
          children: [
            jsxs("span", { key: "text", style: { display: "flex", flexDirection: "column", gap: "2px" }, children: [
              jsx("span", { key: "t", style: { fontSize: "13px" }, children: "桌面提醒卡片" }),
              jsx("span", { key: "d", style: { color: "var(--dsw-alias-label-tertiary)", fontSize: "11px" }, children: "她来叫你的时候，应用内同步亮一张带立绘的牌子" })
            ] }),
            jsx("input", {
              key: "toggle",
              type: "checkbox",
              defaultChecked: notifyPrefOn(PREF_CARD),
              onChange: (event) => setNotifyPref(PREF_CARD, event.target.checked)
            })
          ]
        })
      ));
    }

    /* ---------------- 安装 ---------------- */

    function installWhaleNotify(ctx) {
      if (wnNotifyInstalled || wnDisposed) return;
      wnNotifyInstalled = true;
      if (typeof ctx.effect === "function") ctx.effect(() => () => disposeWhaleNotify(), "dsh-whale-notify: desktop lifecycle");
      window.addEventListener("pagehide", disposeWhaleNotify);
      let installed = false;
      const install = (scope) => {
        if (installed || wnDisposed) return;
        installed = true;
        const sessions = scope?.sessions ?? ctx.get?.("sessions");
        const uiWorkspace = scope?.uiWorkspace ?? ctx.get?.("uiWorkspace");

        const report = () => {
          if (wnDisposed) return;
          try {
            fetch(FOCUS_ENDPOINT, {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({
                focused: typeof document !== "undefined" && document.visibilityState === "visible" && document.hasFocus(),
                sessionId: activeSessionId(sessions),
                at: Date.now()
              }),
              keepalive: true
            }).catch(() => {});
          } catch (e) { /* 上报永远不该抛错 */ }
        };

        ctx.effect(
          () => {
            report();
            const onFocus = () => report();
            const onVisibility = () => report();
            window.addEventListener("focus", onFocus);
            window.addEventListener("blur", onFocus);
            document.addEventListener("visibilitychange", onVisibility);
            const unsubscribe = sessions?.list?.subscribe?.(report);
            const timer = window.setInterval(report, HEARTBEAT_MS);
            let stopped = false;
            const stop = () => {
              if (stopped) return;
              stopped = true;
              window.clearInterval(timer);
              window.removeEventListener("focus", onFocus);
              window.removeEventListener("blur", onFocus);
              document.removeEventListener("visibilitychange", onVisibility);
              if (typeof unsubscribe === "function") unsubscribe();
            };
            wnCleanups.push(stop);
            return stop;
          },
          "dsh-whale-notify: focus reporter"
        );

        ctx.effect(
          () => {
            const controller = new AbortController();
            wnCleanups.push(() => controller.abort());
            const loop = async () => {
              while (!controller.signal.aborted && !wnDisposed) {
                try {
                  const response = await fetch(ACTIVATION_ENDPOINT, { cache: "no-store", signal: controller.signal });
                  if (controller.signal.aborted || wnDisposed) return;
                  if (response.ok) {
                    const data = await response.json();
                    if (data?.sessionId) {
                      const opened = openSession(ctx, uiWorkspace, data.sessionId);
                      scrollToLatest();
                      reportActivated(data.sessionId, opened);
                    }
                  }
                  /* 路由关闭或返回空值时也退避，不能让失败响应形成忙循环。 */
                  await wnPause(RETRY_MS, controller.signal);
                } catch (error) {
                  if (controller.signal.aborted) return;
                  await wnPause(RETRY_MS, controller.signal);
                }
              }
            };
            loop();
            return () => controller.abort();
          },
          "dsh-whale-notify: activation watch"
        );

        ctx.effect(
          () => {
            const controller = new AbortController();
            wnCleanups.push(() => controller.abort());
            /* 首轮不带 since：只同步序号，绝不回放历史提醒（刷新页面不重播） */
            let since = null;
            const loop = async () => {
              while (!controller.signal.aborted && !wnDisposed) {
                try {
                  const url = since === null ? REACT_ENDPOINT : REACT_ENDPOINT + "?since=" + since;
                  const response = await fetch(url, { cache: "no-store", signal: controller.signal });
                  if (controller.signal.aborted || wnDisposed) return;
                  if (response.ok) {
                    const data = await response.json();
                    if (typeof data?.seq === "number") since = data.seq;
                    if (Array.isArray(data?.items)) for (const item of data.items) handleReaction(item);
                  }
                  await wnPause(REACT_POLL_MS, controller.signal);
                } catch (error) {
                  if (controller.signal.aborted) return;
                  await wnPause(RETRY_MS, controller.signal);
                }
              }
            };
            loop();
            return () => controller.abort();
          },
          "dsh-whale-notify: reaction poll"
        );

        try { registerNotifySettings(ctx); } catch (error) {
          console.warn("[dsh-whale-notify] 提醒开关注册失败（提醒本身不受影响）", error);
        }

        /* 服务慢启动可重试，但只在成功订阅后标记完成，最多尝试一分钟。 */
        let approvalInstalled = false;
        let approvalAttempts = 0;
        const bindApproval = (scope) => {
          if (approvalInstalled || wnDisposed) return;
          approvalAttempts += 1;
          try { approvalInstalled = installApprovalBridge(scope ?? ctx, ctx) === true; }
          catch (error) { console.warn("[dsh-whale-notify] 审批桥失败", error); }
          if (approvalInstalled) reportPet("pet:ap-bridge", true);
        };
        if (typeof ctx.inject === "function") ctx.inject(["remote"], (scope) => bindApproval(scope));
        bindApproval(ctx);
        const approvalRetry = window.setInterval(() => {
          bindApproval(ctx);
          if (approvalInstalled || approvalAttempts >= 30 || wnDisposed) window.clearInterval(approvalRetry);
        }, 2000);
        wnCleanups.push(() => window.clearInterval(approvalRetry));
        try { installApprovalMirror(sessions); } catch (error) { /* 原生审批仍然可用 */ }

        /* 应用内那只彻底取消：每次加载都把偏好按死成 0，不注入表现层、不自救。 */
        try {
          window.localStorage.setItem("whale-moe:pet", "0");
          window.localStorage.setItem("whale-moe:notify-desktop-only", "1");
          window.dispatchEvent(new CustomEvent("whale-moe-prefs-change", { detail: { key: "pet", value: false } }));
          reportPet("pet:inapp-off", true);
        } catch (e) { /* 存储不可写也照样不注入 */ }

        /* 上游彩蛋：关键词反应 + 时段/节日问候 */
        try { installKeywordWatch(); } catch (error) { /* ignore */ }
        try { installGreetWatch(); } catch (error) { /* ignore */ }

        /* 桌面版联动：领她在桌面上按下的 √/× */
        try { installPetDecisionPoller(); } catch (error) { /* 桥接不在不影响本体 */ }

        /* 皮肤可见性偏好：读出来（必要时把角色层打开），每条 ≤13 字符。 */
        wnLater(() => {
          try {
            const KEYS = ['dsh.skin-manager.preferences.v2', 'dsh-deep-whale.skin-manager.v1'];
            let raw = null, used = '';
            for (const k of KEYS) { const v = window.localStorage.getItem(k); if (v) { raw = v; used = k; break; } }
            reportPet('skraw=' + (raw ? raw.length : 0), true);
            if (!raw) return;
            const obj = JSON.parse(raw);
            const skins = obj.skins || obj;
            const maid = skins['maid-atelier'] || (obj.maid && obj.maid.atelier) || {};
            const flag = (v) => (v === undefined || v === null ? 'u' : (v ? '1' : '0'));
            reportPet('skA=' + flag(maid.artwork), true);
            reportPet('skC=' + flag(maid.character), true);
            reportPet('skX=' + flag(maid.modelExit), true);
            reportPet('skS=' + flag(obj.schedule && obj.schedule.enabled), true);
            reportPet('skF=' + flag(obj.activeSkin ? 1 : 0), true);
            let changed = 0;
            const fix = (o) => {
              if (!o || typeof o !== 'object') return;
              if (o.artwork === false) { o.artwork = true; changed += 1; }
              if (o.character === false) { o.character = true; changed += 1; }
            };
            fix(maid);
            if (obj.schedule && obj.schedule.enabled === true) { obj.schedule.enabled = false; changed += 1; }
            if (changed > 0) {
              window.localStorage.setItem(used, JSON.stringify(obj));
              reportPet('skfix=' + changed, true);
              wnLater(() => window.location.reload(), 1200);
            } else { reportPet('skfix=0', true); }
          } catch (err) { reportPet('skfail', false); }
        }, 7000);

        /* 一次性 DOM 普查（16 字符 token 限制 -> 每条 13 字符内）。 */
        wnLater(() => {
          try {
            const sel = '[data-maid-character],[data-orca-character],[data-skin-chrome],[class*="character" i],[class*="mascot" i]';
            const code = [...document.querySelectorAll(sel)].map((el) => {
              const cs = getComputedStyle(el);
              const r = el.getBoundingClientRect();
              const v = (el.getAttribute('data-maid-character') || el.getAttribute('data-skin-chrome') || 'x').slice(0, 1).toUpperCase();
              const d = cs.display === 'none' ? 'n' : 'b';
              const vis = cs.visibility === 'visible' ? 'v' : 'h';
              const op = String(Math.round(Number(cs.opacity) * 100)).padStart(3, '0');
              return v + d + vis + op + '_' + Math.round(r.width / 10) + 'x' + Math.round(r.height / 10) + '@' + Math.round(r.left / 10) + '.' + Math.round(r.top / 10);
            });
            reportPet('dc=' + code.length, true);
            code.slice(0, 14).forEach((s2, i) => reportPet('d' + (i + 1) + '=' + s2.slice(0, 13), true));
          } catch (err) { reportPet('dfail', false); }
        }, 9000);
        /* 应用内只清掉右边/输入框旁那个重复的角色层；左边壁纸与背景一律不动。 */
        try {
          /* 不再注入整份 CSS（避免缓存里的旧规则误伤壁纸层），只按元素精准处理 */
          reportPet("pet:nomascot-css", true);
          const DUP_SEL = '[data-maid-character="right"],[data-maid-character="vision"]';
          let hiddenTotal = 0;
          const sweep = () => {
            let n = 0;
            /* 皮肤的「模型退场」会在 Flash 模型下把左边壁纸立绘推到屏幕外：直接关掉它，让壁纸回来。 */
            try {
              const root = document.documentElement;
              if (root.getAttribute('data-dsh-whale-maid-model-exit') !== 'disabled') root.setAttribute('data-dsh-whale-maid-model-exit', 'disabled');
              if (root.getAttribute('data-dsh-whale-maid-art') !== 'visible') root.setAttribute('data-dsh-whale-maid-art', 'visible');
              if (!window.__whaleArtOn) { window.__whaleArtOn = true; reportPet('art=' + (root.getAttribute('data-dsh-whale-maid-art') || '-'), true); reportPet('mx=' + (root.getAttribute('data-dsh-whale-maid-model-exit') || '-'), true); }
            } catch (e) { /* ignore */ }
            try {
              document.querySelectorAll(DUP_SEL).forEach((el) => {
                if (el.dataset && el.dataset.whaleDupHidden === "1") return;
                el.style.setProperty("display", "none", "important");
                el.style.setProperty("visibility", "hidden", "important");
                el.style.setProperty("opacity", "0", "important");
                if (el.dataset) el.dataset.whaleDupHidden = "1";
                n += 1;
              });
            } catch (e) { /* ignore */ }
            if (n > 0) { hiddenTotal += n; reportPet("pet:dup-hidden+" + n, true); }
            /* 壁纸那张（left）被皮肤设成 display:none：强行复位，让她回来。 */
            try {
              document.querySelectorAll('[data-maid-character="left"]').forEach((el) => {
                const cs = getComputedStyle(el);
                if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) < 0.5) {
                  el.style.setProperty('display', 'block', 'important');
                  el.style.setProperty('visibility', 'visible', 'important');
                  el.style.setProperty('opacity', '1', 'important');
                  el.style.setProperty('transform', 'none', 'important');
                  el.style.setProperty('translate', 'none', 'important');
                }
                if (!el.dataset.whaleWallOn) { el.dataset.whaleWallOn = '1'; reportPet('wallOn', true); }
                /* 皮肤这个容器是空的（0x0）：用我们自己的立绘把它画出来。 */
                if (el.offsetWidth < 8 || el.offsetHeight < 8) {
                  const art = '/api/dsh-whale-musume/assets?f=generated/dsh-whale-state-daily-pajama.webp';
                  el.style.setProperty('position', 'absolute', 'important');
                  el.style.setProperty('left', '8px', 'important');
                  el.style.setProperty('bottom', '0', 'important');
                  el.style.setProperty('width', 'clamp(220px, 26vw, 380px)', 'important');
                  el.style.setProperty('height', 'clamp(300px, 56vh, 520px)', 'important');
                  el.style.setProperty('background-image', 'url(' + art + ')', 'important');
                  el.style.setProperty('background-size', 'contain', 'important');
                  el.style.setProperty('background-repeat', 'no-repeat', 'important');
                  el.style.setProperty('background-position', 'bottom center', 'important');
                  el.style.setProperty('filter', 'drop-shadow(0 18px 22px rgba(3,12,28,0.35))', 'important');
                  el.style.setProperty('pointer-events', 'none', 'important');
                  el.style.setProperty('z-index', '0', 'important');
                  if (!el.dataset.whaleWallArt) { el.dataset.whaleWallArt = '1'; reportPet('wallArt', true); }
                }
              });
            } catch (e) { /* ignore */ }
          };
          sweep();
          try {
            const mo = new MutationObserver(() => sweep());
            mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-maid-character", "class"] });
            wnCleanups.push(() => mo.disconnect());
          } catch (e) { /* 轮询兜底 */ }
          const forever = window.setInterval(sweep, 2000);
          wnCleanups.push(() => window.clearInterval(forever));
        } catch (e) { /* 注入失败也不影响桌宠 */ }
        /* 看门狗：她不出现就自己救一次，并把诊断回报宿主 */
        try { ensurePetAlive(); } catch (error) { /* 看门狗失败不影响本体 */ }      };
      if (typeof ctx.inject === "function") ctx.inject(["sessions", "uiWorkspace"], install);
      else install(ctx);
      wnLater(() => {
        if (!installed) {
          console.warn("[dsh-whale-notify] 服务 5 秒内没注入，先用现有能力装上（最多少个「点击跳对话」）");
          install(ctx);
        }
      }, 5000);
    }

    /* 桌宠本体 + 提醒联动合成一个 apply；任何半边炸了都不该拖垮另一半。 */
    /* ==================================================================
       dsh-whale-notify：把审批搬到她旁边（√ / ×）
         主路：抢在系统审批弹窗之前接住 approval/request，用她身边的牌子裁决；
         兜底：万一抢不到（内置面板已弹），也把她身边的 √/× 挂上——
               点它等于点内置面板的按钮，两条路都通；
         安全阀：45 秒没动就交回系统弹窗，绝不把 agent 卡死。
       ================================================================== */

    /** 需要在模块卸载时清理的东西。 */
    /* ==================================================================
       dsh-whale-notify：外链式引导（桌面端 CSP 不允许内联 <script>/<style>，
       上游那套 textContent 内联注入被静默拦掉——立绘因此永远不出现）。
       改成同源 <script src> / <link rel=stylesheet>，并带上页面 nonce。
       ================================================================== */
    function pageNonce() {
      try {
        const el = document.querySelector("script[nonce], style[nonce], link[nonce]");
        if (!el) return "";
        return el.nonce || el.getAttribute("nonce") || "";
      } catch (e) { return ""; }
    }

    function injectLink(href, nonce) {
      const el = document.createElement("link");
      el.rel = "stylesheet";
      el.href = href;
      if (nonce) el.setAttribute("nonce", nonce);
      el.setAttribute("data-dsh-whale-notify", "css");
      document.head.appendChild(el);
      return el;
    }

    function injectExternalScript(src, nonce) {
      return new Promise((resolve, reject) => {
        const el = document.createElement("script");
        el.src = src;
        el.async = false;
        el.setAttribute("data-dsh-whale-notify", "js");
        if (nonce) el.setAttribute("nonce", nonce);
        el.addEventListener("load", () => resolve(true));
        el.addEventListener("error", () => reject(new Error("script blocked or missing: " + src)));
        document.body.appendChild(el);
      });
    }

    /**
     * 应用内表现层不再注入：她只住在桌面上（画布上那只由 C:\Users\...\.dsh\whale-pet 的进程负责）。
     * 这里保留函数名给历史调用点用，直接返回，绝不往页面里塞 CSS / 状态机 / 表现层。
     */
    async function bootExternal() {
      window.__dshWhaleMusumeBooted = true;
      reportPet("pet:inapp-disabled", true);
    }

    /** 一次性自检：把她内部的状态吐给宿主日志（16 字符一格的暗号）。 */
    function petSelfCheck(tag) {
      try {
        const dbg = window.__dshWhaleMoeDebug;
        reportPet("pet:" + tag + ":core" + (window.DshWhaleMoeCore ? 1 : 0), !!window.DshWhaleMoeMood);
        reportPet("pet:" + tag + ":mood" + (typeof window.DshWhaleMoeMood === "function" ? 1 : 0), !!window.DshWhaleMoeMood);
        reportPet("pet:" + tag + ":dbg=" + String((dbg && dbg.state) || "-").slice(0, 6), !!dbg);
        let pref = null;
        try { pref = window.localStorage.getItem("whale-moe:pet"); } catch (e) { pref = "?"; }
        reportPet("pet:" + tag + ":pref=" + String(pref), pref !== "0");
        const modal = document.querySelector("[data-shortcut-modal=\"settings\"]");
        const head = document.querySelector("[data-slot=\"settings.header\"]");
        reportPet("pet:" + tag + ":sm" + (modal ? 1 : 0) + (head ? 1 : 0), false);
        const root = petRootNode();
        reportPet("pet:" + tag + ":disp=" + (root ? getComputedStyle(root).display.slice(0, 5) : "none"), !!root);
        reportPet("pet:" + tag + ":inapp=off", true);
      } catch (error) { /* 自检失败不影响本体 */ }
    }
    /* ==================================================================
       桌面版鲸鱼娘联动：把 DSH 的状态推给桌面上的她，把她桌面上的 √/× 收回来。
       桥接地址 http://127.0.0.1:19390（本地 TcpListener，带 CORS）。
       ================================================================== */
    const PET_BRIDGE = "http://127.0.0.1:19390";
    const wnCleanups = [];
    let wnDisposed = false;
    let wnNotifyInstalled = false;
    /* 不持久化：复制标签页也必须拥有不同的领取身份。 */
    const wnClientId = "whale-" + (window.crypto?.randomUUID?.() || Date.now().toString(36) + "-" + Math.random().toString(36).slice(2));
    let petBridgeAlive = false;
    let petToken = "";
    let petSessionPromise = null;
    let petSessionRetryAt = 0;
    let petWriteChain = Promise.resolve();
    let wnApprovalSequence = 0;
    const wnBridgeRequests = new Set();
    const wnPendingTimers = new Set();
    const wnApprovalResolvers = new Map();

    function wnLater(fn, delay) {
      const timer = window.setTimeout(() => {
        wnPendingTimers.delete(timer);
        if (!wnDisposed) fn();
      }, delay);
      wnPendingTimers.add(timer);
      return timer;
    }

    function wnPause(delay, signal) {
      return new Promise((resolve) => {
        if (signal.aborted) { resolve(); return; }
        const finish = () => { window.clearTimeout(timer); signal.removeEventListener("abort", finish); resolve(); };
        const timer = window.setTimeout(finish, delay);
        signal.addEventListener("abort", finish, { once: true });
      });
    }

    function disposeWhaleNotify() {
      if (wnDisposed) return;
      /* 卸载时的取消可在页面关闭期间完成；其它未完成网络请求随后一起终止。 */
      for (const entry of [...wnApprovalResolvers.values()]) {
        if (petToken) {
          try {
            fetch(PET_BRIDGE + "/approval/cancel", {
              method: "POST", keepalive: true,
              headers: { "content-type": "application/json", "X-Whale-Token": petToken },
              body: JSON.stringify({ clientId: wnClientId, id: entry.id })
            }).catch(() => {});
          } catch (e) { /* 服务已退出 */ }
        }
        try { entry.cancel?.(); } catch (e) { /* 独立清理剩余请求 */ }
      }
      wnDisposed = true;
      wnApprovalResolvers.clear();
      for (const timer of wnPendingTimers) window.clearTimeout(timer);
      wnPendingTimers.clear();
      for (const controller of wnBridgeRequests) controller.abort();
      wnBridgeRequests.clear();
      for (const cleanup of wnCleanups.splice(0).reverse()) {
        try { cleanup(); } catch (e) { /* 单项释放失败不影响其余项 */ }
      }
      hideWhaleCard();
      window.removeEventListener("pagehide", disposeWhaleNotify);
    }

    async function petFetch(path, options = {}) {
      const controller = new AbortController();
      wnBridgeRequests.add(controller);
      const timer = window.setTimeout(() => controller.abort(), 4000);
      try {
        return await fetch(PET_BRIDGE + path, { ...options, cache: "no-store", signal: controller.signal });
      } finally {
        window.clearTimeout(timer);
        wnBridgeRequests.delete(controller);
      }
    }

    async function petSession() {
      if (petToken) return petToken;
      if (petSessionPromise) return petSessionPromise;
      if (wnDisposed || Date.now() < petSessionRetryAt) return "";
      petSessionRetryAt = Date.now() + 15000;
      petSessionPromise = (async () => {
        try {
          const response = await petFetch("/session");
          if (!response.ok) { petBridgeAlive = false; return ""; }
          const data = await response.json();
          if (data?.ok && data.protocol === 2 && typeof data.token === "string" && data.token) {
            petToken = data.token;
            petBridgeAlive = data.uiAlive === true;
          } else { petBridgeAlive = false; }
        } catch (e) { petBridgeAlive = false; }
        return petToken;
      })();
      try { return await petSessionPromise; }
      finally { petSessionPromise = null; }
    }

    async function petRequest(path, payload) {
      for (let attempt = 0; attempt < 2; attempt += 1) {
        const token = await petSession();
        if (!token || wnDisposed) return null;
        try {
          const response = await petFetch(path, {
            method: payload === undefined ? "GET" : "POST",
            headers: { "X-Whale-Token": token, ...(payload === undefined ? {} : { "content-type": "application/json" }) },
            ...(payload === undefined ? {} : { body: JSON.stringify(payload) })
          });
          if ((response.status === 401 || response.status === 403) && attempt === 0) {
            if (petToken === token) { petToken = ""; petSessionRetryAt = 0; }
            continue;
          }
          if (!response.ok) petBridgeAlive = false;
          return response.ok ? response : null;
        } catch (e) {
          petBridgeAlive = false;
          petToken = "";
          return null;
        }
      }
      return null;
    }

    /** 程序状态和审批队列分别更新；只有 clearApprovalId 能取消指定审批。 */
    function petPost(payload) {
      const state = { ...payload, clientId: wnClientId, at: Date.now() };
      delete state.approval;
      if (payload?.approval) state.approval = { ...payload.approval, clientId: wnClientId };
      petWriteChain = petWriteChain.then(async () => {
        if (wnDisposed || (state.approval && !wnApprovalResolvers.has(state.approval.id))) return false;
        return !!(await petRequest("/state", state));
      }).catch(() => false);
      return petWriteChain;
    }

    function wnRegisterApproval(identity, resolver, cancel) {
      if (wnDisposed || !identity?.sessionId || !identity?.requestId || wnApprovalResolvers.size >= 64) return null;
      const id = wnClientId + ":" + (++wnApprovalSequence).toString(36);
      const entry = { ...identity, id, clientId: wnClientId, resolver, cancel };
      wnApprovalResolvers.set(id, entry);
      return entry;
    }

    function wnPublishApproval(entry) {
      return petPost({ pose: "wait", line: "有操作要你点头，点我身上的 √ 或 ×", sid: entry.sessionId, approval: {
        id: entry.id, clientId: wnClientId, sessionId: entry.sessionId, requestId: entry.requestId,
        tool: String(entry.tool || "工具").slice(0, 48), reason: String(entry.reason || "").slice(0, 180), expiresAt: Date.now() + 60000
      } });
    }

    function wnRemoveApproval(id) {
      const key = String(id);
      if (!wnApprovalResolvers.delete(key)) return;
      petPost({ clearApprovalId: key });
    }

    async function wnResolveApprovalById(id, outcome, clientId, sessionId) {
      if (wnDisposed || clientId !== wnClientId || (outcome !== "allowed-once" && outcome !== "rejected")) return false;
      const entry = wnApprovalResolvers.get(String(id));
      if (!entry || (sessionId && sessionId !== entry.sessionId)) return false;
      try {
        const accepted = await entry.resolver(outcome);
        if (accepted === false) return false;
        wnRemoveApproval(entry.id);
        return true;
      } catch (error) {
        console.warn("[dsh-whale-notify] 裁决回调失败，保留原审批", error);
        return false;
      }
    }

    function installPetDecisionPoller() {
      const handled = new Set();
      let busy = false;
      let renewing = false;
      const poll = async () => {
        if (busy || wnDisposed) return;
        busy = true;
        try {
          const response = await petRequest("/decision?clientId=" + encodeURIComponent(wnClientId));
          if (!response || wnDisposed) return;
          const decision = await response.json();
          if (!decision?.id || decision.clientId !== wnClientId) return;
          const known = wnApprovalResolvers.has(String(decision.id));
          if (!handled.has(decision.id) && known) {
            const accepted = await wnResolveApprovalById(decision.id, decision.outcome, decision.clientId, decision.sessionId);
            if (!accepted) return;
            handled.add(decision.id);
            if (handled.size > 256) handled.delete(handled.values().next().value);
            reactToDecision(decision.outcome);
            reportPet("pet:desk-verdict", decision.outcome === "allowed-once");
          }
          /* 旧裁决只确认丢弃；绝不猜测当前页面或其它会话的按钮。 */
          await petRequest("/decision/ack", { clientId: wnClientId, id: String(decision.id) });
        } catch (e) { /* 本地桥离线不会影响原会话 */ }
        finally { busy = false; }
      };
      const timer = window.setInterval(poll, 1200);
      const renewal = window.setInterval(async () => {
        if (renewing || wnDisposed) return;
        renewing = true;
        try {
          for (const entry of [...wnApprovalResolvers.values()]) {
            if (wnDisposed) break;
            await wnPublishApproval(entry);
          }
        } finally { renewing = false; }
      }, 20000);
      wnCleanups.push(() => { window.clearInterval(timer); window.clearInterval(renewal); });
    }


    /* ==================================================================
       上游彩蛋落地（桌面版）：关键词反应 / 时段问候 / 点击跳回对话。
       关键词表与姿态映射直接取自上游 whale-moe-core 与 presenter。
       ================================================================== */
    /** 从宿主推来的正文里抠项目名（正文里有「目录：E:\\xxx\\项目」）。 */
    let wnProject = "";
    function wnNoteFromBody(body) {
      try {
        const m = /目录：([^\n]+)/.exec(String(body || ""));
        if (!m) return "";
        const p = m[1].trim().replace(/[\\/]+$/, "");
        const base = p.split(/[\\/]/).pop() || "";
        return base.slice(0, 28);
      } catch (e) { return ""; }
    }

    const WHALE_KEYWORD_TABLE = [{"id":"thanks","words":["谢谢","感谢","多谢","thank"],"pose":"peek","line":"不客气啦，随时喊我～"},{"id":"tired","words":["好累","累了","困了","疲惫","好困"],"pose":"work-sleep","line":"累了就歇会儿，我帮你盯着"},{"id":"hungry","words":["饿了","好饿","吃饭","夜宵"],"pose":"peek","line":"去吃点东西！饿着写代码是要出 bug 的"},{"id":"goodnight","words":["晚安","睡了","去睡"],"pose":"peek","line":"晚安，我把灯给你留着"},{"id":"cheer","words":["加油","冲鸭","冲呀"],"pose":"bold","line":"冲！我给你打气 ✨"},{"id":"help","words":["救命","帮我","求助","完蛋"],"pose":"peek","line":"别慌，我在呢——先说哪儿出问题了？"},{"id":"praise","words":["太强了","厉害","牛","真棒","天才"],"pose":"peek","line":"嘿嘿，被夸到了（尾巴翘起来）"},{"id":"hug","words":["抱抱","贴贴","摸摸"],"pose":"peek","line":"抱抱！（蹭一下）"},{"id":"cute","words":["可爱","萌","好萌"],"pose":"peek","line":"你才可爱呢！"},{"id":"morning","words":["早安","早上好"],"pose":"peek","line":"早安主人！今天也是精神百倍的一天"},{"id":"worker","words":["打工人","打工","搬砖","社畜","上班","加班"],"pose":"peek","line":"打工人加油，我陪你一起搬砖"},{"id":"slack","words":["摸鱼","摆烂","躺平","不想上班","不想写","懒得"],"pose":"work-slack-phone","line":"摸鱼是吧？我可看见了 👀"},{"id":"ddl","words":["ddl","deadline","截止","赶不完","来不及","最后期限"],"pose":"work-deadline","line":"DDL 是吧……我陪你一起赶！"},{"id":"cake","words":["画饼","大饼","pua","老板","画大饼"],"pose":"work-boss","line":"又是画饼？别信，先摸鱼"},{"id":"crazy","words":["发疯","破防","绷不住","已老实","求放过","啊啊啊","疯了"],"pose":"abstract","line":"深呼吸，先喝口水，再战"},{"id":"flag","words":["立个 flag","立 flag","立flag","这把我","干完这单","flag"],"pose":"bold","line":"立 flag 了？我记下来了 📝"},{"id":"bugtalk","words":["bug 好玄学","bug好玄学","玄学","改一行","回滚","代码坏"],"pose":"work-debug","line":"玄学 bug 是吧，先回滚再说"},{"id":"kyun","words":["心动","好可爱","太可爱","aww","心动了","可爱死"],"pose":"meme-kyun","line":"呜哇，心动了（脸红）"},{"id":"omg","words":["我的天","天哪","omg","离谱","震惊","我靠","卧槽","不是吧"],"pose":"meme-omg","line":"什么？！让我看看"},{"id":"doge","words":["就这","呵呵","笑死","难蚌","绷不住笑"],"pose":"meme-doge","line":"就这？我见多了（狗头）"},{"id":"sike","words":["拿下","搞定","轻松","so easy","稳了","小意思"],"pose":"meme-sike","line":"稳了稳了，拿下！"},{"id":"worship","words":["大佬","膜拜","膝盖","牛批","nb","大神"],"pose":"meme-worship","line":"大佬大佬，膝盖给你 🙇"},{"id":"peace","words":["佛系","随缘","淡定","算了算了","无所谓"],"pose":"meme-peace","line":"佛系一点也挺好～"},{"id":"doubt","words":["真的假的","不会吧","确定吗","怀疑","是吗"],"pose":"meme-doubt","line":"（她歪头看着你）"},{"id":"wakuwaku","words":["期待","兴奋","冲了","开始吧","wow","等不及"],"pose":"meme-wakuwaku","line":"（她歪头看着你）"},{"id":"smilepain","words":["无语","累了累了","麻了","已黑化","微笑"],"pose":"meme-smile-pain","line":"（她歪头看着你）"},{"id":"ojisan","words":["无聊","好闲","没意思","就这？"],"pose":"meme-ojisan","line":"（她歪头看着你）"},{"id":"deploy","words":["部署","上线","发布","deploy","release"],"pose":"work-deploy","line":"（她歪头看着你）"},{"id":"meeting","words":["开会","会议","例会","评审会"],"pose":"work-meeting","line":"（她歪头看着你）"},{"id":"review","words":["review","评审","代码审查","cr"],"pose":"work-review","line":"（她歪头看着你）"}];
    const WHALE_GREET = {
      night: { pose: "night", line: "都这么晚了，我陪你一起熬（哈欠）" },
      morning: { pose: "greet", line: "早安主人，今天也要元气满满地修 bug 鸭" },
      forenoon: { pose: "idle", line: "上午的代码最香了" },
      noon: { pose: "daily-eat", line: "到饭点了，别饿着自己" },
      afternoon: { pose: "daily-coffee", line: "下午三点，来杯咖啡续命 ☕" },
      evening: { pose: "idle", line: "晚上好，今天辛苦了" }
    };
    function wnGreetBucket(h) {
      if (h >= 23 || h < 6) return "night";
      if (h < 9) return "morning";
      if (h < 12) return "forenoon";
      if (h < 14) return "noon";
      if (h < 18) return "afternoon";
      return "evening";
    }
    function wnFestivalPose() {
      const d = new Date(); const m = d.getMonth() + 1; const day = d.getDate();
      if (m === 10 && day === 31) return "festival-halloween";
      if (m === 12 && day === 25) return "festival-christmas";
      if (m === 2 && day === 14) return "valentine";
      return "";
    }
    /** 关键词反应：只扫最新一条对话节点，同类 60 秒一次、任意两条间隔 8 秒。 */
    function installKeywordWatch() {
      const lastHit = new Map();
      let lastText = "";
      let lastAny = 0;
      const scan = () => {
        try {
          if (window.localStorage.getItem("whale-moe:keywords") !== "1") return;
          const nodes = document.querySelectorAll('[data-slot="conversation.chat.node"]');
          if (nodes.length === 0) return;
          const text = (nodes[nodes.length - 1].textContent || "").slice(0, 2000);
          if (text === "" || text === lastText) return;
          lastText = text;
          const now = Date.now();
          if (now - lastAny < 8000) return;
          for (const k of WHALE_KEYWORD_TABLE) {
            const seen = lastHit.get(k.id);
            if (seen !== undefined && now - seen < 60000) continue;
            if (k.words.some((w) => text.indexOf(w) >= 0)) {
              lastHit.set(k.id, now);
              lastAny = now;
              reportPet("pet:kw-" + k.id.slice(0, 6), true);
              petPost({ pose: k.pose, line: k.line, at: now });
              break;
            }
          }
        } catch (e) { /* 扫描失败不影响本体 */ }
      };
      const timer = window.setInterval(scan, 1500);
      wnCleanups.push(() => window.clearInterval(timer));
    }
    /** 时段/节日问候：进页面来一次，之后每 10 分钟看一次时段有没有翻页。 */
    function installGreetWatch() {
      let bucket = "";
      const fire = (force) => {
        if (!notifyPrefOn("whale-moe:proactive")) return;
        const key = wnGreetBucket(new Date().getHours());
        if (!force && key === bucket) return;
        bucket = key;
        const fest = wnFestivalPose();
        const g = WHALE_GREET[key] || WHALE_GREET.evening;
        petPost({ pose: fest || g.pose, line: fest ? "今天过节！我换上节日衣服啦 🎉" : g.line, note: wnProject, at: Date.now() });
      };
      wnLater(() => fire(true), 6000);
      const timer = window.setInterval(() => fire(false), 600000);
      wnCleanups.push(() => window.clearInterval(timer));
    }

    /** 桌宠身边审批的开关（设置 → 看板娘）。 */
    const PREF_APPROVE = "whale-moe:notify-approve";
    /** 多久没裁决就交回系统弹窗。 */
    const APPROVE_FALLBACK_MS = 45000;

    function petRootNode() {
      return document.querySelector("[data-dsh-whale-root]");
    }

    /** 诊断用：把一小段状态塞进宿主已有的回执日志（16 字符以内）。 */
    function reportPet(marker, ok) {
      try {
        fetch("/dsh-desktop-notify/activated", {
          method: "POST",
          headers: { "content-type": "application/json" },
          keepalive: true,
          body: JSON.stringify({ sessionId: String(marker).slice(0, 16), opened: ok === true, at: Date.now() })
        }).catch(() => {});
      } catch (e) { /* 诊断失败不影响本体 */ }
    }

    function ensureApproveStyles() {
      if (document.querySelector("style[data-dsh-whale-approve-style]")) return;
      const style = document.createElement("style");
      style.setAttribute("data-dsh-whale-approve-style", "");
      style.textContent = [
        "[data-dsh-whale-approve]{position:fixed;right:236px;bottom:26px;z-index:62;width:330px;max-width:calc(100vw - 268px);box-sizing:border-box;padding:14px 16px 12px;border-radius:18px;border:1px solid rgba(56,189,248,.5);background:linear-gradient(158deg,rgba(4,20,38,.98),rgba(9,40,70,.98));color:#eaf7ff;font-size:12.5px;line-height:1.55;font-family:var(--dsw-font-family,Microsoft YaHei,system-ui,sans-serif);box-shadow:0 22px 56px rgba(2,10,24,.66),inset 0 0 0 1px rgba(56,189,248,.16);backdrop-filter:blur(12px);animation:wn-appr-in .32s cubic-bezier(.2,.9,.25,1)}",
        "[data-dsh-whale-approve][data-wm-theme=light]{background:linear-gradient(158deg,rgba(240,249,255,.99),rgba(214,238,255,.99));color:#06263f;border-color:rgba(14,116,144,.4)}",
        "[data-dsh-whale-approve] .wna-head{display:flex;align-items:center;gap:9px;margin-bottom:6px}",
        "[data-dsh-whale-approve] .wna-avatar{width:40px;height:40px;border-radius:12px;object-fit:contain;background:rgba(56,189,248,.14)}",
        "[data-dsh-whale-approve] .wna-kicker{font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;opacity:.62}",
        "[data-dsh-whale-approve] .wna-tool{font-size:14px;font-weight:700;color:#7dd3fc}",
        "[data-dsh-whale-approve] .wna-reason{margin-top:6px;max-height:96px;overflow:auto;white-space:pre-wrap;opacity:.88}",
        "[data-dsh-whale-approve] .wna-actions{display:flex;gap:10px;margin-top:12px}",
        "[data-dsh-whale-approve] button{flex:1;cursor:pointer;border-radius:12px;border:1px solid transparent;font:inherit;font-size:14px;font-weight:700;padding:9px 12px;transition:filter .16s ease,transform .16s ease}",
        "[data-dsh-whale-approve] button:hover{filter:brightness(1.12)}",
        "[data-dsh-whale-approve] button:active{transform:scale(.98)}",
        "[data-dsh-whale-approve] .wna-yes{background:linear-gradient(140deg,#34d399,#10b981);color:#052e2b}",
        "[data-dsh-whale-approve] .wna-no{background:transparent;border-color:rgba(251,113,133,.7);color:#fda4af}",
        "[data-dsh-whale-approve] .wna-hint{margin-top:8px;font-size:10.5px;opacity:.6;display:flex;justify-content:space-between;gap:8px}",
        "[data-dsh-whale-approve]{animation:wn-appr-in .32s cubic-bezier(.2,.9,.25,1),wn-pulse 1.8s ease-in-out .35s infinite}","[data-dsh-whale-approve] .wna-bar{position:absolute;left:14px;right:14px;bottom:6px;height:2px;border-radius:2px;background:#38bdf8;opacity:.55;transform-origin:left;animation:wna-bar linear forwards}",
        "@keyframes wn-appr-in{from{opacity:0;transform:translateX(28px) scale(.96)}to{opacity:1;transform:none}}",
        "@keyframes wna-bar{from{transform:scaleX(1)}to{transform:scaleX(0)}}",
        "@keyframes wn-pulse{0%,100%{box-shadow:0 22px 56px rgba(2,10,24,.66),0 0 0 0 rgba(56,189,248,.55)}50%{box-shadow:0 22px 56px rgba(2,10,24,.66),0 0 0 10px rgba(56,189,248,0)}}"
      ].join("");
      document.head.appendChild(style);
    }

    /** 在她身边升起一块审批牌；返回清理函数。 */
    /* 应用内一律不出牌子：只留桌面上的她（用户明确要求） */
    function showPetApproval() { return () => {}; }

    function showPetApprovalLegacy(request, decide) {
      /* 应用内不再出牌子：你要的只有桌面上那一只，她活着就把裁决交给她 */
      if (petBridgeAlive) return () => {};
      ensureApproveStyles();
      const node = document.createElement("div");
      node.setAttribute("data-dsh-whale-approve", "");
      node.setAttribute("role", "alertdialog");
      const theme = petRootNode()?.getAttribute("data-wm-theme");
      if (theme) node.setAttribute("data-wm-theme", theme);
      const head = document.createElement("div");
      head.className = "wna-head";
      const avatar = document.createElement("img");
      avatar.className = "wna-avatar";
      avatar.alt = "";
      avatar.src = BASE + "notify/avatar-approval.png";
      avatar.addEventListener("error", () => { avatar.style.visibility = "hidden"; });
      const title = document.createElement("div");
      const kicker = document.createElement("div");
      kicker.className = "wna-kicker";
      kicker.textContent = "在她旁边直接裁决";
      const tool = document.createElement("div");
      tool.className = "wna-tool";
      tool.textContent = (request && request.toolName) ? String(request.toolName) : "有操作要你点头";
      title.appendChild(kicker);
      title.appendChild(tool);
      head.appendChild(avatar);
      head.appendChild(title);
      const reasonText = (request && (request.displayReason || request.reason)) || "";
      const reason = document.createElement("div");
      reason.className = "wna-reason";
      reason.textContent = String(reasonText);
      const actions = document.createElement("div");
      actions.className = "wna-actions";
      const yes = document.createElement("button");
      yes.type = "button";
      yes.className = "wna-yes";
      yes.textContent = "√ 允许一次";
      const no = document.createElement("button");
      no.type = "button";
      no.className = "wna-no";
      no.textContent = "× 拒绝";
      actions.appendChild(yes);
      actions.appendChild(no);
      const hint = document.createElement("div");
      hint.className = "wna-hint";
      const hintLeft = document.createElement("span");
      hintLeft.textContent = "Enter = 允许 · Esc = 拒绝";
      const hintRight = document.createElement("span");
      hintRight.textContent = Math.round(APPROVE_FALLBACK_MS / 1000) + " 秒后交回系统弹窗";
      hint.appendChild(hintLeft);
      hint.appendChild(hintRight);
      const bar = document.createElement("div");
      bar.className = "wna-bar";
      bar.style.animationDuration = APPROVE_FALLBACK_MS + "ms";
      node.appendChild(head);
      if (reasonText) node.appendChild(reason);
      node.appendChild(actions);
      node.appendChild(hint);
      node.appendChild(bar);
      document.body.appendChild(node);
      let closed = false;
      const cleanup = () => {
        if (closed) return;
        closed = true;
        window.removeEventListener("keydown", onKey, true);
        try { node.remove(); } catch (e) { /* 已经没了 */ }
      };
      const onKey = (event) => {
        const el = event.target;
        if (el && el.closest && el.closest("input, textarea, select, [contenteditable=true]")) return;
        if (event.key === "Enter") { event.preventDefault(); event.stopPropagation(); decide("allowed-once"); }
        else if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); decide("rejected"); }
      };
      yes.addEventListener("click", () => decide("allowed-once"));
      no.addEventListener("click", () => decide("rejected"));
      window.addEventListener("keydown", onKey, true);
      return cleanup;
    }

    /** 裁决后她的反应。 */
    function reactToDecision(outcome) {
      if (outcome === "allowed-once") { whalePose("celebrate", 5000); whaleSay("放行！我盯着它干完 👀", 5000); }
      else { whalePose("meme-no", 5000); whaleSay("好，拒绝了，谁也别想动你的东西", 5000); }
    }

    /** 主路：抢在内置审批弹窗之前接住 approval/request。 */
    function approvalIdentity(request, owner, sessions) {
      const requestId = request?.requestId ?? request?.approvalId ?? request?.id ?? request?.callId;
      const explicitSession = request?.sessionId ?? request?.agent?.id;
      let ownedSession;
      try { ownedSession = sessions?.scopeOf?.(owner); }
      catch (e) { return null; }
      if (ownedSession && explicitSession && ownedSession !== explicitSession) return null;
      const sessionId = ownedSession ?? explicitSession;
      if ((typeof requestId !== "string" && typeof requestId !== "number") || !String(requestId) ||
          typeof sessionId !== "string" || !sessionId) return null;
      const display = request?.displayReason;
      return {
        requestId: String(requestId), sessionId,
        tool: String(request?.toolName || "工具"),
        reason: typeof display === "string" ? display : String(display?.zh || display?.en || request?.reason || ""),
        source: "request"
      };
    }

    function installApprovalBridge(ctx, fallbackCtx = ctx) {
      const remote = ctx.remote ?? ctx.get?.("remote");
      if (!remote || typeof remote.$on !== "function") return false;
      const sessions = ctx.sessions ?? ctx.get?.("sessions") ?? fallbackCtx.sessions ?? fallbackCtx.get?.("sessions");
      /* 官方远程 waterfall 把 owner 放在监听器 this，原 request 只携带 callId。 */
      const onRequest = function (request, next) {
        const delegate = () => typeof next === "function" ? next() : Promise.resolve("unavailable");
        const identity = approvalIdentity(request, this, sessions);
        /* 缺失真实请求身份时保留上游弹窗；不能用当前所看会话猜测请求归属。 */
        if (wnDisposed || !identity || !notifyPrefOn(PREF_APPROVE) || !petBridgeAlive) return delegate();
        if (request?.signal?.aborted) return Promise.resolve("cancelled");
        if ([...wnApprovalResolvers.values()].some((entry) =>
          entry.sessionId === identity.sessionId && entry.requestId === identity.requestId)) return delegate();
        return new Promise((resolve) => {
          let done = false, timer = 0, entry = null;
          const release = () => {
            window.clearTimeout(timer);
            request?.signal?.removeEventListener?.("abort", onAbort);
            if (entry) wnRemoveApproval(entry.id);
          };
          const finish = (outcome) => {
            if (done) return false;
            done = true;
            release();
            resolve(outcome);
            return true;
          };
          const handBack = () => {
            if (done) return;
            done = true;
            release();
            Promise.resolve().then(delegate).then(resolve, () => resolve("unavailable"));
          };
          const onAbort = () => finish("cancelled");
          entry = wnRegisterApproval(identity, finish, handBack);
          if (!entry) { handBack(); return; }
          timer = window.setTimeout(handBack, APPROVE_FALLBACK_MS);
          request?.signal?.addEventListener?.("abort", onAbort, { once: true });
          if (request?.signal?.aborted) { onAbort(); return; }
          /* 桥不可用时立刻交回原审批，不让 agent 等待整段超时。 */
          wnPublishApproval(entry).then((posted) => { if (!posted) handBack(); });
        });
      };
      try {
        let off;
        try { off = remote.$on("approval/request", onRequest, { prepend: true }); }
        catch (e) { off = remote.$on("approval/request", onRequest); }
        wnCleanups.push(() => {
          if (typeof off === "function") off();
          else if (typeof remote.$off === "function") remote.$off("approval/request", onRequest);
        });
        return true;
      } catch (error) {
        console.warn("[dsh-whale-notify] approval/request 订阅失败", error);
        return false;
      }
    }
    /** 镜像只绑定同一会话里具有真实 key 的当前审批条；历史卡片绝不参与。 */
    function installApprovalMirror(sessions) {
      const mirrors = new Map();
      let scheduled = false;
      const visible = (element) => {
        try {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return element.isConnected !== false && rect.width > 1 && rect.height > 1 &&
            style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
        } catch (e) { return false; }
      };
      const ownerSession = (panel) => panel.getAttribute("data-session-id") ||
        panel.closest("[data-session-id]")?.getAttribute("data-session-id") || activeSessionId(sessions);
      const buttonsOf = (panel) => {
        const buttons = [...panel.querySelectorAll("button, [role=button]")].filter((button) =>
          visible(button) && !button.disabled && button.getAttribute("aria-disabled") !== "true");
        const label = (button) => String(button.textContent || "").replace(/^[√✓×✕✖]\s*/, "").trim();
        return {
          yes: buttons.find((button) => /^(?:允许一次|仅允许一次|允许|Allow once|Allow|Approve once)$/i.test(label(button))),
          no: buttons.find((button) => /^(?:拒绝|Reject|Deny)$/i.test(label(button)))
        };
      };
      const sync = () => {
        scheduled = false;
        if (wnDisposed) return;
        const live = new Map();
        for (const panel of document.querySelectorAll("[data-approval-key]")) {
          if (!visible(panel) || panel.closest('[data-slot="conversation.chat.node"], [data-dsh-whale-approve]')) continue;
          const requestId = panel.getAttribute("data-approval-key");
          const sessionId = ownerSession(panel);
          if (!requestId || !sessionId) continue;
          const buttons = buttonsOf(panel);
          if (!buttons.yes || !buttons.no) continue;
          const key = JSON.stringify([sessionId, requestId]);
          /* 同一身份存在多个可见面板时保持原生审批，避免任何歧义。 */
          if (live.has(key)) { live.set(key, null); continue; }
          live.set(key, { panel, requestId, sessionId, ...buttons });
        }
        for (const [key, old] of mirrors) {
          const current = live.get(key);
          if (!current || current.panel !== old.panel || current.yes !== old.yes || current.no !== old.no ||
              !notifyPrefOn(PREF_APPROVE)) {
            wnRemoveApproval(old.entry.id);
            mirrors.delete(key);
          }
        }
        if (!notifyPrefOn(PREF_APPROVE)) return;
        for (const [key, current] of live) {
          if (!current || mirrors.has(key)) continue;
          if ([...wnApprovalResolvers.values()].some((entry) =>
            entry.sessionId === current.sessionId && entry.requestId === current.requestId)) continue;
          let entry;
          const resolve = (outcome) => {
            /* 回调检查捕获的面板、key、会话和按钮；切会话、换牌、换按钮后旧裁决全部失效。 */
            if (!visible(current.panel) || current.panel.getAttribute("data-approval-key") !== current.requestId ||
                ownerSession(current.panel) !== current.sessionId ||
                ![...document.querySelectorAll("[data-approval-key]")].includes(current.panel)) return false;
            const buttons = buttonsOf(current.panel);
            if (buttons.yes !== current.yes || buttons.no !== current.no) return false;
            const target = outcome === "allowed-once" ? current.yes : current.no;
            target.click();
            return true;
          };
          entry = wnRegisterApproval({
            sessionId: current.sessionId, requestId: current.requestId, source: "mirror",
            tool: current.panel.getAttribute("data-tool-name") || "有操作等你点头",
            reason: String(current.panel.textContent || "").trim().slice(0, 180)
          }, resolve, () => mirrors.delete(key));
          if (!entry) continue;
          mirrors.set(key, { ...current, entry });
          wnPublishApproval(entry);
        }
      };
      const schedule = () => {
        if (scheduled || wnDisposed) return;
        scheduled = true;
        wnLater(sync, 80);
      };
      const observer = new MutationObserver(schedule);
      observer.observe(document.documentElement, {
        childList: true, subtree: true, characterData: true, attributes: true,
        attributeFilter: ["data-approval-key", "data-session-id", "disabled", "aria-disabled", "hidden"]
      });
      const unsubscribe = sessions?.list?.subscribe?.(schedule);
      window.addEventListener("whale-moe-prefs-change", schedule);
      const timer = window.setInterval(sync, 3000);
      wnCleanups.push(() => {
        observer.disconnect();
        window.clearInterval(timer);
        window.removeEventListener("whale-moe-prefs-change", schedule);
        if (typeof unsubscribe === "function") unsubscribe();
        for (const old of mirrors.values()) wnRemoveApproval(old.entry.id);
        mirrors.clear();
      });
      sync();
    }
    /** 只读健康探测；页面加载、重连或定时器绝不请求显示/启动程序。 */
    function ensurePetAlive() {
      let busy = false;
      const probe = async () => {
        if (busy || wnDisposed) return;
        busy = true;
        try {
          const response = await petRequest("/ping");
          const health = response ? await response.json() : null;
          petBridgeAlive = health?.ok === true && health.uiAlive === true;
        } catch (e) { petBridgeAlive = false; }
        finally { busy = false; }
      };
      probe();
      const timer = window.setInterval(probe, 15000);
      wnCleanups.push(() => window.clearInterval(timer));
    }
    function applyAll(ctx) {
      if (wnDisposed || wnNotifyInstalled) return;
      apply(ctx);
      try {
        installWhaleNotify(ctx);
      } catch (error) {
        console.warn("[dsh-whale-notify] 提醒联动注册失败（桌宠本体不受影响）", error);
      }
    }

    exports.apply = applyAll;
    exports.dispose = disposeWhaleNotify;
    exports.inject = ["slots"];

    /* 桌面模式不向页面注入 presenter；设置与可选 TTS 在 apply 生命周期内注册。 */
    bootExternal();
    return module.exports;
  },
});
