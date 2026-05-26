# Codex Island

Codex Island is a small macOS app that displays Codex activity in a Dynamic Island style overlay near the notch.

It is independent from LocalServer. The `codexisland` CLI installs, starts, restarts, and upgrades the app through a user LaunchAgent.

## Requirements

- macOS 14+
- Xcode Command Line Tools
- Codex Desktop or Codex CLI

## Quick Start

From this repository:

```bash
swift run codexisland
```

On first run, this command:

1. Installs Codex global hooks into `~/.codex/hooks.json`.
2. Copies the hook writer to `~/.codex-island/codex_island_hook.py`.
3. Builds `CodexIslandApp` in release mode.
4. Registers and starts `~/Library/LaunchAgents/com.haoyu.codex-island.plist`.

After installation, `swift run codexisland` only starts the app.

Codex may ask you to review or trust newly installed hooks. That trust prompt is part of Codex's hook safety model.

## CLI

```bash
swift run codexisland
swift run codexisland restart
swift run codexisland stop
swift run codexisland upgrade
swift run codexisland status
swift run codexisland install-hooks
swift run codexisland uninstall-hooks
swift run codexisland logs
```

Command semantics:

- `codexisland`: start the app; if not installed, install and start.
- `codexisland restart`: stop and start the app only. It does not rebuild, reinstall hooks, or rewrite the LaunchAgent.
- `codexisland upgrade`: rebuild release, reinstall hooks, rewrite the LaunchAgent, and start.
- `codexisland enable`: alias for `upgrade`.

After building once, you can install a shell command:

```bash
swift run codexisland install-cli
```

Make sure `~/.local/bin` is in your `PATH`, then run:

```bash
codexisland
```

## Controls

Codex Island does not use a menu-bar icon. Open the island, then click the Codex badge in the lower-right corner to reveal app controls:

- Quit
- Launch at login

## How It Works

- Process monitor: finds Codex host processes and watches child processes with `libproc` + `kqueue`.
- Hooks: `UserPromptSubmit` and `Stop` drive the thinking/completed animation; `PreToolUse` and `PostToolUse` provide fast command metadata.
- Event file: hooks append compact JSONL events to `~/.codex-island/events.jsonl`.

## Privacy

The app only writes local files under `~/.codex-island` and does not send telemetry. Hook events keep command metadata and remove large tool output before writing.
