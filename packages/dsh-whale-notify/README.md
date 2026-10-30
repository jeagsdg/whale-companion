# dsh-whale-notify 1.1

DeepSeek Harness 桌面端插件，配合独立 Windows 鲸鱼娘桌宠使用。安装与日常操作见项目根目录 README.md。

## 当前行为

- 默认仅由桌宠提醒；系统 Toast 和额外 WPF 通知卡片默认关闭，可在 cordis.patch.yml 显式启用。
- 客户端不注入第二只网页宠物，不自动显示或启动桌面程序。
- 宿主健康检查使用有退避和次数上限的单实例启动器，尊重手动隐藏和退出。
- 审批由接管的原生请求或捕获的精确活审批条处理；身份缺失时交回 DSH 原审批。宿主反应本身只提供通知和原会话入口。
- v2 本地桥校验来源及令牌；独立审批队列不会被台词覆盖，裁决按 clientId 领取并在执行确认后删除。

## 更新与配置

修改后运行根目录 tools/install.ps1 或 tools/update-global-install.cmd。安装器完整备份已有程序和数据，保留用户 JSON 和自定义台词。

必须彻底退出并重启 DSH 才能加载宿主更新；Ctrl+R 仅刷新客户端。配置键与默认值见 cordis.patch.yml，协议见 docs/ARCHITECTURE.md。

## 主要文件

| 文件 | 作用 |
|---|---|
| lib/index.js / pet-lifecycle.js | 宿主装配与有限、安静的恢复检查 |
| lib/notify.js | 事件识别、焦点门控、等待请求存活校验、去重与通知反应 |
| lib/client.js | 原生审批桥、精确审批镜像、领取确认和卸载清理 |
| lib/whale-assets.js | 包内静态资源路由 |
| lib/toast.ps1 / alert.ps1 | 可选系统通知通道 |
| lib/activator/ / dsh-notify-*.exe | 点击回会话激活器和前台窗口探针 |

## 卸载

1. 在托盘选择“退出”，避免后台恢复。
2. 若安装过开机自启，删除 Startup 文件夹中的 WhaleMusumePet.lnk；若自己另设了旧 watchdog 计划任务，也一并取消。
3. 从 desktop profile 的 package.json 删除 dependencies 中的 dsh-whale-notify 以及 dsh.profile.bundles 中的同名项目。
4. 关闭剩余的本安装目录 whale-pet-http.ps1 进程，移除插件副本后重启 DSH。

用户数据位于 DSH 数据目录的 whale-pet 文件夹，可保留以便以后重新安装。不要为了卸载插件而删除养成数据或整个 DSH profile。

## 许可

MIT，复用 dsh-whale-musume 的立绘与语义，以及 dsh-desktop-notify 的通知引擎与激活器；详见根目录 LICENSE 与 docs/UPSTREAM.md。