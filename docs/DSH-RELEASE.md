# 鲸鱼娘 DSH 独立发行版

[下载最新版](https://github.com/jeagsdg/whale-companion/releases/latest) · Windows 10/11 · DeepSeek Harness 桌宠插件

解压发行包，双击 `Install-DSH.cmd`，完成后重启 DSH。无需克隆 Git 仓库、安装 Python 或手工复制插件文件。

前提：Windows 10/11、Windows PowerShell 5.1，以及已经启动并建立 desktop profile 的 DeepSeek Harness。安装不会替你安装 DSH。默认 profile 是 `%USERPROFILE%\.dsh\profiles\desktop`。

自定义目录可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/install.ps1 -DshHome 'D:\MyDsh'
```

完整桌宠运行时、104 张表情、宿主插件和原有 HTTP v1/v2 桥随包一起提供。待办、提醒、专注、称呼、新闻、游戏、签到、成就、隐藏恢复和审批逻辑使用现有 Windows 实现；没有改动原有 API。首次安装不需要 Node.js，DSH 自身的运行环境由 DSH 提供。`whale-mcp.mjs` 和原有 17 个工具定义也保留在运行时中；若需要其他 MCP 客户端调用，需单独配置相应客户端。

安装器会先备份已有 profile、插件和桌宠数据，更新程序并保留用户数据。重复运行可升级，默认安装当前用户的开机入口；使用 `-NoStartup` 禁用新增入口，`-NoStart` 仅安装而不启动。不静默关闭你的 DSH 工作；重启 DSH 后才加载新版宿主插件。

`dsh-whale-notify-2.5.0.tgz` 是包含桌宠运行时的 npm 格式分发包。没有自动执行的 postinstall。使用现有 Node.js 可执行：

```powershell
npm exec --yes --package .\dsh-whale-notify-2.5.0.tgz -- whale-dsh-install
```

该文件的存在不代表已经发布到 npm 注册表。普通用户优先使用 ZIP 中的双击安装入口。

升级前后都可以从宠物菜单打开“检查与修复建议”。卸载时先退出宠物，再从 DSH profile 中移除 `dsh-whale-notify` bundle 和 dependency，并删除启动目录的 `WhaleMusumePet.lnk`。个人数据位于 `.dsh\whale-pet`，请自行备份后决定是否删除。

MIT 许可和上游归属保留在 `LICENSE` 与 `docs/UPSTREAM.md`。发行包只读取程序文件白名单，不包含使用者的待办、日志、状态令牌、新闻收藏或签名私钥。`SHA256SUMS.txt` 可用于比对下载文件完整性。
