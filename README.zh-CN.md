# Codex Island

[English](README.md)

Codex Island 是一个轻量的 macOS Codex 灵动岛。它会检测并显示 Codex 正在运行的终端命令，并在消息开始运行、结束时用灵动岛动画提醒。

它不依赖 LocalServer。`codexisland` CLI 会通过用户级 LaunchAgent 完成安装、启动、重启和升级。

## 功能

- 在屏幕顶部用灵动岛样式展示 Codex 活动。
- 显示 Codex 正在执行或最近执行过的终端命令。
- 在 Codex 开始处理消息时显示思考动画。
- 在本轮对话结束时显示完成提醒。
- 支持岛内控制：退出、开机自起。
- 没有菜单栏图标，界面只保留灵动岛入口。

## 依赖

- macOS 14+
- Git
- Xcode Command Line Tools，包含 SwiftPM
- Codex Desktop 或 Codex CLI

如果 Agent 帮忙安装，请先确认这些依赖是否已经安装；如果缺少依赖，先安装依赖，再继续执行安装命令。

## 安装

建议把仓库克隆到 `~/codex-island`，避免放在 Documents、Desktop、Downloads 这类更容易触发 macOS 权限弹窗的位置：

```bash
git clone https://github.com/haoyubai212/codex-island.git ~/codex-island
cd ~/codex-island
swift run codexisland
```

第一次运行 `swift run codexisland` 会自动完成整套安装：

1. 安装 Codex 全局 hooks 到 `~/.codex/hooks.json`。
2. 复制 hook 写入脚本到 `~/.codex-island/codex_island_hook.py`。
3. 以 release 模式构建 `CodexIslandApp`。
4. 把 app 可执行文件复制到 `~/Library/Application Support/CodexIsland/CodexIslandApp`。
5. 把 CLI 安装到 `~/Library/Application Support/CodexIsland/codexisland`。
6. 在 `~/.local/bin/codexisland` 创建 CLI 软链接。
7. 注册并启动 `~/Library/LaunchAgents/com.haoyu.codex-island.plist`。

Codex 可能会提示你审核或信任新安装的 hooks，这是 Codex 的 hook 安全机制。

第一次安装完成后，以后直接运行：

```bash
codexisland
```

请确保 `~/.local/bin` 已经在你的 `PATH` 里。

## 安装位置

Codex Island 会把源码、运行数据和安装后的可执行文件分开放置：

- 源码仓库：`~/codex-island`
- App 可执行文件：`~/Library/Application Support/CodexIsland/CodexIslandApp`
- CLI 可执行文件：`~/Library/Application Support/CodexIsland/codexisland`
- CLI 软链接：`~/.local/bin/codexisland`
- LaunchAgent：`~/Library/LaunchAgents/com.haoyu.codex-island.plist`
- Hook 脚本：`~/.codex-island/codex_island_hook.py`
- 事件和日志：`~/.codex-island/`
- Codex hooks 配置：`~/.codex/hooks.json`

LaunchAgent 会从 `~/Library/Application Support/CodexIsland` 启动 app，不会依赖源码仓库里的构建产物。

## CLI

```bash
codexisland
codexisland restart
codexisland stop
codexisland upgrade
codexisland status
codexisland logs
```

命令说明：

- `codexisland`：启动 app。如果还没有安装，会先安装再启动。
- `codexisland restart`：只关闭并重新启动 app，不会重新构建、重装 hooks 或重写 LaunchAgent。
- `codexisland stop`：停止 LaunchAgent 和当前 app 进程。
- `codexisland upgrade`：重新构建 release，重装 hooks，复制 app 到 Application Support，重写 LaunchAgent，并启动 app。
- `codexisland status`：查看 app 进程是否正在运行。
- `codexisland logs`：输出日志文件位置和系统日志查看命令。

如果还没有安装全局 `codexisland` 命令，可以在仓库目录里使用：

```bash
swift run codexisland status
```

## 岛内控制

Codex Island 没有菜单栏图标。展开灵动岛后，点击右下角 Codex 徽标可以显示 app 控制项：

- 退出
- 开机自起

“开机自起”开关会通过 `launchctl` 启用或禁用 `com.haoyu.codex-island`。它不会删除 LaunchAgent 文件，也不会退出当前正在运行的 app。

如果 Codex Island 检测到远端有新提交，同一个控制区会显示：

- 更新
- 忽略

“更新”会拉取源码仓库，把本地 tracked 文件重置到上游分支，然后执行完整的 `codexisland upgrade` 流程。“忽略”会在一周内隐藏这次更新提醒。

## 工作原理

- 进程监控：查找 Codex host 进程，并通过 `libproc` + `kqueue` 监听子进程。
- Hooks：`UserPromptSubmit` 和 `Stop` 负责思考/完成动画；`PreToolUse` 和 `PostToolUse` 提供更快的命令元数据。
- 事件文件：hooks 会把精简后的 JSONL 事件追加到 `~/.codex-island/events.jsonl`。
- 更新检查：app 启动时检查保存的源码仓库路径，每天最多检查一次。源码仓库路径会在 `codexisland upgrade` 时写入配置。

## 隐私

Codex Island 只在你的用户目录下写入本地文件，不会发送遥测数据。

Hook 事件只保留命令元数据，并会在写入前移除大段工具输出。

## 卸载

```bash
codexisland stop
codexisland uninstall-hooks
rm -f ~/.local/bin/codexisland
rm -rf "$HOME/Library/Application Support/CodexIsland"
rm -f ~/Library/LaunchAgents/com.haoyu.codex-island.plist
```

运行日志和事件保存在 `~/.codex-island/`。如果不再需要本地历史记录，可以删除：

```bash
rm -rf "$HOME/.codex-island"
```
