# Codex Island

[简体中文](README.zh-CN.md)

Codex Island is a small macOS app that displays Codex activity in a Dynamic Island style overlay near the notch.

It runs independently from LocalServer. The `codexisland` CLI installs, starts, restarts, and upgrades the app through a user LaunchAgent.

## Requirements

- macOS 14+
- Git
- Xcode Command Line Tools, including SwiftPM
- Codex Desktop or Codex CLI

If an agent is helping with installation, check these requirements first and install any missing dependencies before running the setup commands.

## Install

Clone the repository outside Documents/Desktop/Downloads. The recommended location is `~/codex-island`:

```bash
git clone https://github.com/haoyubai212/codex-island.git ~/codex-island
cd ~/codex-island
swift run codexisland
```

On first run, this command:

1. Installs Codex global hooks into `~/.codex/hooks.json`.
2. Copies the hook writer to `~/.codex-island/codex_island_hook.py`.
3. Builds `CodexIslandApp` in release mode.
4. Copies the app binary to `~/Library/Application Support/CodexIsland/CodexIslandApp`.
5. Installs the CLI to `~/Library/Application Support/CodexIsland/codexisland`.
6. Creates the CLI symlink at `~/.local/bin/codexisland`.
7. Registers and starts `~/Library/LaunchAgents/com.haoyu.codex-island.plist`.

Codex may ask you to review or trust the newly installed hooks. That trust prompt is part of Codex's hook safety model.

After the first run, use:

```bash
codexisland
```

Make sure `~/.local/bin` is in your `PATH`.

## Install Locations

Codex Island keeps source code, runtime data, and installed binaries separate:

- Source checkout: `~/codex-island`
- App binary: `~/Library/Application Support/CodexIsland/CodexIslandApp`
- CLI binary: `~/Library/Application Support/CodexIsland/codexisland`
- CLI symlink: `~/.local/bin/codexisland`
- LaunchAgent: `~/Library/LaunchAgents/com.haoyu.codex-island.plist`
- Hook script: `~/.codex-island/codex_island_hook.py`
- Events/logs: `~/.codex-island/`
- Codex hooks config: `~/.codex/hooks.json`

The LaunchAgent runs the app from `~/Library/Application Support/CodexIsland`, not from the repository checkout.

## CLI

```bash
codexisland
codexisland restart
codexisland stop
codexisland upgrade
codexisland status
codexisland logs
```

Command semantics:

- `codexisland`: start the app. If it is not installed, install and start it.
- `codexisland restart`: stop and start the app only. It does not rebuild, reinstall hooks, or rewrite the LaunchAgent.
- `codexisland stop`: stop the LaunchAgent and current app process.
- `codexisland upgrade`: rebuild release, reinstall hooks, copy the app into Application Support, rewrite the LaunchAgent, and start.
- `codexisland status`: print whether the app process is running.
- `codexisland logs`: print log file locations and the system log command.

If you have not installed the global command yet, prefix commands with `swift run` from the repository:

```bash
swift run codexisland status
```

## Controls

Codex Island does not use a menu-bar icon. Open the island, then click the Codex badge in the lower-right corner to reveal app controls:

- Quit
- Launch at login

The Launch at login switch enables or disables `com.haoyu.codex-island` through `launchctl`. It does not remove the LaunchAgent file or quit the currently running app.

If Codex Island detects a newer upstream commit, the same control area shows:

- Update
- Ignore

Update fetches the source checkout, resets it to the upstream branch, then runs the full `codexisland upgrade` flow. Ignore hides the update prompt for one week.

## How It Works

- Process monitor: finds Codex host processes and watches child processes with `libproc` + `kqueue`.
- Hooks: `UserPromptSubmit` and `Stop` drive the thinking/completed animation; `PreToolUse` and `PostToolUse` provide fast command metadata.
- Event file: hooks append compact JSONL events to `~/.codex-island/events.jsonl`.
- Update check: the app checks the saved source checkout at startup and at most once per day. The source checkout path is saved during `codexisland upgrade`.

## Privacy

Codex Island only writes local files under your home directory and does not send telemetry.

Hook events keep command metadata and remove large tool output before writing.

## Uninstall

```bash
codexisland stop
codexisland uninstall-hooks
rm -f ~/.local/bin/codexisland
rm -rf "$HOME/Library/Application Support/CodexIsland"
rm -f ~/Library/LaunchAgents/com.haoyu.codex-island.plist
```

Runtime logs and events are kept in `~/.codex-island/`. Remove that directory only if you no longer need local history:

```bash
rm -rf "$HOME/.codex-island"
```
