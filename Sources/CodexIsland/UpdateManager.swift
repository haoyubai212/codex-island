import Foundation

enum UpdateState: Equatable {
    case idle
    case checking
    case available
    case updating
    case ignored
    case failed(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isUpdating: Bool {
        if case .updating = self { return true }
        return false
    }
}

final class UpdateManager: ObservableObject {
    @Published private(set) var state: UpdateState = .idle

    private struct Config: Codable {
        var sourceRepoPath: String?
        var lastUpdateCheckAt: TimeInterval?
        var ignoreUpdateUntil: TimeInterval?
        var pendingRemoteCommit: String?
    }

    private let fileManager = FileManager.default
    private let supportDir = NSHomeDirectory() + "/.codex-island"
    private let configPath = NSHomeDirectory() + "/.codex-island/config.json"
    private let updateLogPath = NSHomeDirectory() + "/.codex-island/update.log"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let ignoreInterval: TimeInterval = 7 * 24 * 60 * 60
    private var checkTimer: Timer?

    init() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdatesIfNeeded()
        }
    }

    deinit {
        checkTimer?.invalidate()
    }

    func checkForUpdatesIfNeeded(force: Bool = false) {
        guard !state.isUpdating else { return }

        let config = loadConfig()
        let now = Date().timeIntervalSince1970

        if let ignoreUntil = config.ignoreUpdateUntil, ignoreUntil > now {
            state = .ignored
            return
        }

        if let pending = config.pendingRemoteCommit, !pending.isEmpty, !force {
            confirmPendingUpdate(pendingCommit: pending, repoPath: config.sourceRepoPath)
            return
        }

        if !force,
           let lastCheck = config.lastUpdateCheckAt,
           now - lastCheck < checkInterval {
            return
        }

        guard let repoPath = config.sourceRepoPath, fileManager.fileExists(atPath: repoPath) else {
            state = .idle
            return
        }

        state = .checking

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                try self.runGit(["-C", repoPath, "fetch", "--quiet", "origin"])
                let local = try self.runGit(["-C", repoPath, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
                let remote = try self.runGit(["-C", repoPath, "rev-parse", "@{u}"]).trimmingCharacters(in: .whitespacesAndNewlines)

                var nextConfig = self.loadConfig()
                nextConfig.lastUpdateCheckAt = now
                if local != remote {
                    nextConfig.pendingRemoteCommit = remote
                } else {
                    nextConfig.pendingRemoteCommit = nil
                }
                self.saveConfig(nextConfig)

                DispatchQueue.main.async {
                    self.state = local == remote ? .idle : .available
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed("更新检查失败")
                }
            }
        }
    }

    func ignoreForOneWeek() {
        var config = loadConfig()
        config.ignoreUpdateUntil = Date().addingTimeInterval(ignoreInterval).timeIntervalSince1970
        config.pendingRemoteCommit = nil
        saveConfig(config)
        state = .ignored
    }

    func startUpdate() {
        guard !state.isUpdating else { return }
        let config = loadConfig()
        guard let repoPath = config.sourceRepoPath, fileManager.fileExists(atPath: repoPath) else {
            state = .failed("找不到源码仓库")
            return
        }

        var nextConfig = config
        nextConfig.pendingRemoteCommit = nil
        nextConfig.lastUpdateCheckAt = Date().timeIntervalSince1970
        saveConfig(nextConfig)

        state = .updating

        let updateCommand = [
            "set -e",
            "cd \(shellQuote(repoPath))",
            "/usr/bin/git fetch origin",
            "/usr/bin/git reset --hard '@{u}'",
            "/usr/bin/swift run --package-path \(shellQuote(repoPath)) codexisland upgrade"
        ].joined(separator: " && ")

        let detachedCommand = "nohup /bin/zsh -lc \(shellQuote(updateCommand)) >> \(shellQuote(updateLogPath)) 2>&1 &"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try self?.ensureSupportDir()
                try self?.runShell(detachedCommand)
            } catch {
                DispatchQueue.main.async {
                    self?.state = .failed("更新启动失败")
                }
            }
        }
    }

    private func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            return Config()
        }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
    }

    private func confirmPendingUpdate(pendingCommit: String, repoPath: String?) {
        guard let repoPath, fileManager.fileExists(atPath: repoPath) else {
            state = .available
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let local = (try? self.runGit(["-C", repoPath, "rev-parse", "HEAD"]))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            DispatchQueue.main.async {
                guard let local else {
                    self.state = .available
                    return
                }

                if local == pendingCommit {
                    var config = self.loadConfig()
                    config.pendingRemoteCommit = nil
                    self.saveConfig(config)
                    self.state = .idle
                } else {
                    self.state = .available
                }
            }
        }
    }

    private func saveConfig(_ config: Config) {
        do {
            try ensureSupportDir()
            let data = try JSONEncoder().encode(config)
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            print("[Codex Island] 保存更新配置失败: \(error)")
        }
    }

    private func ensureSupportDir() throws {
        try fileManager.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CodexIslandUpdate", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: output
            ])
        }
        return output
    }

    private func runShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CodexIslandUpdate", code: Int(process.terminationStatus))
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
