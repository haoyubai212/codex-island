import AppKit
import Foundation

enum CodexIslandControls {
    static let label = "com.haoyu.codex-island"

    private static var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    static func refreshAutoStartEnabled(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let enabled = isAutoStartEnabledSync()
            DispatchQueue.main.async {
                completion(enabled)
            }
        }
    }

    static func setAutoStartEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            setAutoStartEnabledSync(enabled)
            let confirmed = isAutoStartEnabledSync()
            DispatchQueue.main.async {
                completion(confirmed)
            }
        }
    }

    static func quit() {
        NSApp.terminate(nil)
    }

    private static func isAutoStartEnabledSync() -> Bool {
        guard FileManager.default.fileExists(atPath: launchAgentPath) else { return false }
        let output = runLaunchctl(arguments: ["print-disabled", "gui/\(getuid())"])
        if output.contains("\"\(label)\" => disabled") {
            return false
        }
        return true
    }

    private static func setAutoStartEnabledSync(_ enabled: Bool) {
        if enabled {
            ensureLaunchAgentPlist()
            _ = runLaunchctl(arguments: ["enable", "gui/\(getuid())/\(label)"])
            _ = runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", launchAgentPath])
        } else {
            _ = runLaunchctl(arguments: ["disable", "gui/\(getuid())/\(label)"])
        }
    }

    private static func ensureLaunchAgentPlist() {
        guard !FileManager.default.fileExists(atPath: launchAgentPath) else { return }
        guard let executablePath = Bundle.main.executablePath else { return }

        let supportDir = NSHomeDirectory() + "/.codex-island"
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            atPath: (launchAgentPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
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

        try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
