import Darwin
import Foundation

@_silgen_name("proc_listallpids")
func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

enum CLIError: Error, CustomStringConvertible {
    case repoRootNotFound
    case commandFailed(String, Int32)
    case missingHookScript(String)

    var description: String {
        switch self {
        case .repoRootNotFound:
            return "找不到 Codex Island 仓库根目录"
        case .commandFailed(let command, let code):
            return "命令失败(\(code)): \(command)"
        case .missingHookScript(let path):
            return "找不到 hook 脚本: \(path)"
        }
    }
}

struct CodexIslandCLI {
    let fileManager = FileManager.default
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let label = "com.haoyu.codex-island"

    var supportDir: String { "\(home)/.codex-island" }
    var hooksJSONPath: String { "\(home)/.codex/hooks.json" }
    var hookInstallPath: String { "\(supportDir)/codex_island_hook.py" }
    var launchAgentPath: String { "\(home)/Library/LaunchAgents/\(label).plist" }

    func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "enable"

        switch command {
        case "enable", "start":
            try enable()
        case "disable", "stop":
            try stop()
        case "restart":
            try stop(quiet: true)
            try startApp()
        case "status":
            try status()
        case "install-hooks", "hooks":
            try installHooks()
        case "uninstall-hooks":
            try uninstallHooks()
        case "logs", "log":
            try logs()
        case "install-cli":
            try installCLI()
        case "help", "-h", "--help":
            printUsage()
        default:
            print("未知命令: \(command)")
            printUsage()
            Foundation.exit(2)
        }
    }

    private func enable() throws {
        try installHooks()
        try startApp()
    }

    private func startApp() throws {
        let root = try repoRoot()
        try ensureDirectory(supportDir)
        try runShell("swift build -c release --package-path \(shellQuote(root))")

        let appBinary = "\(root)/.build/release/CodexIslandApp"
        try writeLaunchAgent(appBinary: appBinary)

        let domain = "gui/\(getuid())"
        _ = try? runShell("launchctl bootout \(domain) \(shellQuote(launchAgentPath))", quiet: true)
        try runShell("launchctl bootstrap \(domain) \(shellQuote(launchAgentPath))")
        try runShell("launchctl kickstart -k \(domain)/\(label)")
        print("Codex Island 已启动")
    }

    private func stop(quiet: Bool = false) throws {
        let domain = "gui/\(getuid())"
        _ = try? runShell("launchctl bootout \(domain) \(shellQuote(launchAgentPath))", quiet: true)
        _ = try? runShell("pkill -x CodexIslandApp", quiet: true)
        if !quiet {
            print("Codex Island 已停止")
        }
    }

    private func status() throws {
        let processes = codexIslandProcesses()
        if processes.isEmpty {
            print("Codex Island 未运行")
        } else {
            print("Codex Island 正在运行:")
            for process in processes {
                print("\(process.pid) \(process.path)")
            }
        }
    }

    private func logs() throws {
        print("stdout: \(supportDir)/CodexIsland.out.log")
        print("stderr: \(supportDir)/CodexIsland.err.log")
        print("实时系统日志: log stream --predicate 'subsystem == \"com.codexisland\"' --style compact")
    }

    private func installHooks() throws {
        let root = try repoRoot()
        let sourceHook = "\(root)/scripts/codex_island_hook.py"
        guard fileManager.fileExists(atPath: sourceHook) else {
            throw CLIError.missingHookScript(sourceHook)
        }

        try ensureDirectory(supportDir)
        let hookData = try Data(contentsOf: URL(fileURLWithPath: sourceHook))
        try hookData.write(to: URL(fileURLWithPath: hookInstallPath), options: .atomic)
        try runShell("chmod +x \(shellQuote(hookInstallPath))", quiet: true)

        var rootObject = try readHooksJSON()
        var hooks = rootObject["hooks"] as? [String: Any] ?? [:]

        addHook(event: "UserPromptSubmit", command: hookCommand("UserPromptSubmit"), matcher: nil, hooks: &hooks)
        addHook(event: "Stop", command: hookCommand("Stop"), matcher: nil, hooks: &hooks)
        addHook(event: "PreToolUse", command: hookCommand("PreToolUse"), matcher: "^Bash$", hooks: &hooks)
        addHook(event: "PostToolUse", command: hookCommand("PostToolUse"), matcher: "^Bash$", hooks: &hooks)

        rootObject["hooks"] = hooks
        try writeHooksJSON(rootObject)
        print("Codex hooks 已安装到 \(hooksJSONPath)")
    }

    private func uninstallHooks() throws {
        var rootObject = try readHooksJSON()
        guard var hooks = rootObject["hooks"] as? [String: Any] else {
            print("没有发现 Codex hooks")
            return
        }

        for event in ["UserPromptSubmit", "Stop", "PreToolUse", "PostToolUse"] {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let filtered = entries.compactMap { entry -> [String: Any]? in
                guard let nested = entry["hooks"] as? [[String: Any]] else { return entry }
                let kept = nested.filter { hook in
                    let command = hook["command"] as? String ?? ""
                    return !command.contains("codex_island_hook.py")
                }
                if kept.isEmpty { return nil }
                var next = entry
                next["hooks"] = kept
                return next
            }
            hooks[event] = filtered
        }

        rootObject["hooks"] = hooks
        try writeHooksJSON(rootObject)
        print("Codex Island hooks 已移除")
    }

    private func installCLI() throws {
        let root = try repoRoot()
        try runShell("swift build -c release --package-path \(shellQuote(root))")
        let binDir = "\(home)/.local/bin"
        try ensureDirectory(binDir)
        let target = "\(binDir)/codexisland"
        if fileManager.fileExists(atPath: target) {
            let destination = (try? fileManager.destinationOfSymbolicLink(atPath: target)) ?? ""
            if destination == "\(root)/.build/release/codexisland" {
                print("命令已安装: \(target)")
                return
            }
            print("已存在: \(target)")
            print("请先手动处理这个文件，再重新运行 install-cli。")
            return
        }
        try fileManager.createSymbolicLink(atPath: target, withDestinationPath: "\(root)/.build/release/codexisland")
        print("已安装命令: \(target)")
        print("如果当前 shell 找不到 codexisland，请确认 ~/.local/bin 在 PATH 中。")
    }

    private func writeLaunchAgent(appBinary: String) throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appBinary)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>StandardOutPath</key>
            <string>\(supportDir)/CodexIsland.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(supportDir)/CodexIsland.err.log</string>
        </dict>
        </plist>
        """

        try ensureDirectory((launchAgentPath as NSString).deletingLastPathComponent)
        try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
    }

    private func addHook(event: String, command: String, matcher: String?, hooks: inout [String: Any]) {
        var entries = hooks[event] as? [[String: Any]] ?? []
        let exists = entries.contains { entry in
            guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
            return nested.contains { ($0["command"] as? String) == command }
        }
        guard !exists else { return }

        var entry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "timeout": 5
                ]
            ]
        ]
        if let matcher {
            entry["matcher"] = matcher
        }
        entries.append(entry)
        hooks[event] = entries
    }

    private func hookCommand(_ event: String) -> String {
        "/usr/bin/python3 \(hookInstallPath) \(event)"
    }

    private func readHooksJSON() throws -> [String: Any] {
        if !fileManager.fileExists(atPath: hooksJSONPath) {
            try ensureDirectory((hooksJSONPath as NSString).deletingLastPathComponent)
            return ["hooks": [:]]
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: hooksJSONPath))
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? ["hooks": [:]]
    }

    private func writeHooksJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: hooksJSONPath), options: .atomic)
    }

    private func repoRoot() throws -> String {
        let candidates = [
            fileManager.currentDirectoryPath,
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent().path
        ]

        for candidate in candidates {
            if let root = findPackageRoot(startingAt: candidate) {
                return root
            }
        }
        throw CLIError.repoRootNotFound
    }

    private func findPackageRoot(startingAt path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        for _ in 0..<8 {
            let package = url.appendingPathComponent("Package.swift").path
            if fileManager.fileExists(atPath: package) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    @discardableResult
    private func runShell(_ command: String, quiet: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        if quiet {
            let devNull = FileHandle(forWritingAtPath: "/dev/null")
            process.standardOutput = devNull
            process.standardError = devNull
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.commandFailed(command, process.terminationStatus)
        }
        return ""
    }

    private func codexIslandProcesses() -> [(pid: Int32, path: String)] {
        let allCount = proc_listallpids(nil, 0)
        guard allCount > 0 else { return [] }

        var allPIDs = [Int32](repeating: 0, count: Int(allCount))
        let actualCount = proc_listallpids(&allPIDs, Int32(MemoryLayout<Int32>.size * Int(allCount)))
        var matches: [(pid: Int32, path: String)] = []

        for i in 0..<Int(actualCount) {
            let pid = allPIDs[i]
            if pid <= 0 || pid == getpid() { continue }

            var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            let result = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
            guard result > 0 else { continue }

            let path = String(cString: pathBuffer)
            if (path as NSString).lastPathComponent == "CodexIslandApp" {
                matches.append((pid, path))
            }
        }

        return matches.sorted { $0.pid < $1.pid }
    }

    private func ensureDirectory(_ path: String) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func printUsage() {
        print("""
        Codex Island

        用法:
          codexisland                 安装 hooks、构建 release、注册 LaunchAgent 并启动
          codexisland enable          安装 hooks、构建 release、注册 LaunchAgent 并启动
          codexisland start           同 enable
          codexisland stop            停止 LaunchAgent 和当前进程
          codexisland restart         重启
          codexisland status          查看运行状态
          codexisland install-hooks   只安装 Codex 全局 hooks
          codexisland uninstall-hooks 移除 Codex Island hooks
          codexisland install-cli     安装 ~/.local/bin/codexisland
          codexisland logs            显示日志位置
        """)
    }
}

do {
    try CodexIslandCLI().run()
} catch {
    fputs("codexisland: \(error)\n", stderr)
    Foundation.exit(1)
}
