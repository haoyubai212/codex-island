import Foundation
import SwiftUI
import os

// MARK: - Codex Hook 事件监控
// 读取 ~/.codex-island/events.jsonl，由全局 Codex hooks 追加事件。
class CodexHookWatcher: ObservableObject {
    private static let logger = Logger(subsystem: "com.codexisland", category: "codex-hook")

    @Published var currentState: AGWorkState = .idle
    @Published var compactCommand: HookCommandPresentation?
    @Published var recentToolCalls: [ToolCallRecord] = []
    @Published var isTurnActive = false
    @Published var activeTurnCount = 0

    private let eventsDir: String
    private let eventsPath: String
    private var fsEventStream: FSEventStreamRef?
    private let serialQueue = DispatchQueue(label: "com.codexisland.codex-hook", qos: .utility)
    private var readOffset: UInt64 = 0
    private var shadowIsEnabled = false
    private var activeSessionIDs = Set<String>()
    private var pendingSessionStops: [String: DispatchWorkItem] = [:]
    private var pendingSessionExpirations: [String: DispatchWorkItem] = [:]
    private var runningHookCommands: [String: RunningHookCommand] = [:]
    private var activeExpiryWork: [String: DispatchWorkItem] = [:]
    private var shortHookTimes: [Date] = []
    private var hookDisplayDismissWork: DispatchWorkItem?
    private let orphanSessionTimeout: TimeInterval = 180
    private let shortCommandDisplayDuration: TimeInterval = 1.0
    private let hookBurstWindow: TimeInterval = 1.0
    private let maxHookActiveDuration: TimeInterval = 180.0

    private struct RunningHookCommand {
        let id: String
        let command: String
        let displayName: String
        let compactName: String
        let category: ProcessMonitor.CommandCategory
        let startTime: Date
    }

    init(eventsDir: String = NSHomeDirectory() + "/.codex-island") {
        self.eventsDir = eventsDir
        self.eventsPath = eventsDir + "/events.jsonl"
        prepareEventsFile()
        startWatching()
    }

    deinit {
        stopWatching()
        pendingSessionStops.values.forEach { $0.cancel() }
        pendingSessionExpirations.values.forEach { $0.cancel() }
        activeExpiryWork.values.forEach { $0.cancel() }
        hookDisplayDismissWork?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        serialQueue.async { [weak self] in
            guard let self = self, self.shadowIsEnabled != enabled else { return }
            self.shadowIsEnabled = enabled
            guard enabled else {
                self.pendingSessionStops.values.forEach { $0.cancel() }
                self.pendingSessionStops.removeAll()
                self.pendingSessionExpirations.values.forEach { $0.cancel() }
                self.pendingSessionExpirations.removeAll()
                self.activeExpiryWork.values.forEach { $0.cancel() }
                self.activeExpiryWork.removeAll()
                self.hookDisplayDismissWork?.cancel()
                self.hookDisplayDismissWork = nil
                self.activeSessionIDs.removeAll()
                self.runningHookCommands.removeAll()
                self.shortHookTimes.removeAll()
                DispatchQueue.main.async {
                    self.currentState = .idle
                    self.compactCommand = nil
                    self.recentToolCalls = []
                    self.isTurnActive = false
                    self.activeTurnCount = 0
                }
                return
            }
            self.readNewEvents()
        }
    }

    private func prepareEventsFile() {
        do {
            try FileManager.default.createDirectory(atPath: eventsDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: eventsPath) {
                FileManager.default.createFile(atPath: eventsPath, contents: nil)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: eventsPath)
            readOffset = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            Self.logger.error("Failed to prepare Codex hook events file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startWatching() {
        let pathsToWatch = [eventsDir] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            codexHookEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            Self.logger.error("Failed to create Codex hook FSEventStream")
            return
        }

        fsEventStream = stream
        FSEventStreamSetDispatchQueue(stream, serialQueue)
        FSEventStreamStart(stream)
    }

    private func stopWatching() {
        guard let stream = fsEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsEventStream = nil
    }

    func handleFSEvent(paths: [String]) {
        guard shadowIsEnabled else { return }
        guard paths.contains(where: { $0 == eventsPath || $0.hasSuffix("/events.jsonl") }) else { return }
        readNewEvents()
    }

    private func readNewEvents() {
        guard shadowIsEnabled else { return }
        guard let handle = FileHandle(forReadingAtPath: eventsPath) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: readOffset)
            let data = handle.readDataToEndOfFile()
            readOffset += UInt64(data.count)
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            for line in text.split(separator: "\n") {
                if let data = line.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    handleEvent(object)
                }
            }
        } catch {
            Self.logger.error("Failed to read Codex hook events: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleEvent(_ event: [String: Any]) {
        let name = (event["event"] as? String) ?? (event["hook_event_name"] as? String) ?? ""
        let sessionKey = sessionKey(from: event)
        let timestamp = eventDate(from: event)

        switch name {
        case "UserPromptSubmit":
            markSessionActive(sessionKey)
            publishState(.thinking)

        case "Stop":
            clearRunningHookCommands()
            publishState(activeSessionIDs.count <= 1 ? .completed : .thinking)
            scheduleSessionCompletion(sessionKey)

        case "PreToolUse":
            guard let command = commandString(from: event), !command.isEmpty else { return }
            let displayName = displayCommandName(command)
            let compactName = compactCommandName(command)
            let category = ProcessMonitor.categorizeCommand(command)
            markSessionActive(sessionKey)
            beginHookCommand(
                id: toolUseID(from: event, command: command, timestamp: timestamp),
                command: command,
                displayName: displayName,
                compactName: compactName,
                category: category,
                timestamp: timestamp
            )
            publishState(.executing(category, displayName))
            addRecord(displayName, icon: category.icon, color: category.color, status: "running", timestamp: timestamp)

        case "PostToolUse":
            guard let command = commandString(from: event), !command.isEmpty else { return }
            let displayName = displayCommandName(command)
            let compactName = compactCommandName(command)
            let category = ProcessMonitor.categorizeCommand(command)
            finishHookCommand(
                id: toolUseID(from: event, command: command, timestamp: timestamp),
                command: command,
                compactName: compactName,
                category: category,
                timestamp: timestamp
            )
            addRecord(displayName, icon: category.icon, color: category.color, status: "completed", timestamp: timestamp)
            refreshSessionExpiration(sessionKey)
            publishState(activeSessionIDs.isEmpty ? .completed : .thinking)

        default:
            break
        }
    }

    private func markSessionActive(_ sessionKey: String) {
        pendingSessionStops[sessionKey]?.cancel()
        pendingSessionStops[sessionKey] = nil
        activeSessionIDs.insert(sessionKey)
        refreshSessionExpiration(sessionKey)
        publishActivitySnapshot()
    }

    private func scheduleSessionCompletion(_ sessionKey: String) {
        pendingSessionStops[sessionKey]?.cancel()
        pendingSessionExpirations[sessionKey]?.cancel()
        pendingSessionExpirations[sessionKey] = nil

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingSessionStops[sessionKey] = nil
            self.activeSessionIDs.remove(sessionKey)
            self.publishActivitySnapshot()
            self.publishState(self.activeSessionIDs.isEmpty ? .idle : .thinking)
        }

        pendingSessionStops[sessionKey] = work
        serialQueue.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func refreshSessionExpiration(_ sessionKey: String) {
        pendingSessionExpirations[sessionKey]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingSessionExpirations[sessionKey] = nil
            guard self.activeSessionIDs.remove(sessionKey) != nil else { return }
            Self.logger.info("Expired orphan Codex session: \(sessionKey, privacy: .public)")
            self.publishActivitySnapshot()
            self.publishState(self.activeSessionIDs.isEmpty ? .idle : .thinking)
        }

        pendingSessionExpirations[sessionKey] = work
        serialQueue.asyncAfter(deadline: .now() + orphanSessionTimeout, execute: work)
    }

    private func publishActivitySnapshot() {
        let count = activeSessionIDs.count
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isTurnActive = count > 0
            self.activeTurnCount = count
        }
    }

    private func publishState(_ state: AGWorkState) {
        DispatchQueue.main.async { [weak self] in
            self?.currentState = state
        }
    }

    private func beginHookCommand(
        id: String,
        command: String,
        displayName: String,
        compactName: String,
        category: ProcessMonitor.CommandCategory,
        timestamp: Date
    ) {
        hookDisplayDismissWork?.cancel()
        hookDisplayDismissWork = nil

        let run = RunningHookCommand(
            id: id,
            command: command,
            displayName: displayName,
            compactName: compactName,
            category: category,
            startTime: timestamp
        )
        runningHookCommands[id] = run
        publishHookCommand(.active(category, compactName, timestamp: timestamp))
        scheduleActiveExpiry(for: id)
    }

    private func finishHookCommand(id: String, command: String, compactName: String, category: ProcessMonitor.CommandCategory, timestamp: Date) {
        activeExpiryWork[id]?.cancel()
        activeExpiryWork[id] = nil

        guard let run = runningHookCommands.removeValue(forKey: id) else {
            recordShortHookCommand(compactName: compactName, category: category, timestamp: timestamp, displayDuration: shortCommandDisplayDuration)
            return
        }

        let duration = max(0, timestamp.timeIntervalSince(run.startTime))
        if duration < shortCommandDisplayDuration {
            recordShortHookCommand(
                compactName: run.compactName,
                category: run.category,
                timestamp: timestamp,
                displayDuration: shortCommandDisplayDuration - duration
            )
        } else {
            publishBestHookCommand()
        }
    }

    private func recordShortHookCommand(compactName: String, category: ProcessMonitor.CommandCategory, timestamp: Date, displayDuration: TimeInterval) {
        shortHookTimes.append(timestamp)
        shortHookTimes = shortHookTimes.filter { timestamp.timeIntervalSince($0) < hookBurstWindow }

        if shortHookTimes.count >= 3 {
            publishHookCommand(.burst(category, compactName, count: shortHookTimes.count, timestamp: timestamp))
        } else {
            publishHookCommand(.recent(category, compactName, timestamp: timestamp))
        }

        scheduleHookDismiss(after: max(0.2, displayDuration))
    }

    private func scheduleActiveExpiry(for id: String) {
        activeExpiryWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.activeExpiryWork[id] = nil
            self.runningHookCommands.removeValue(forKey: id)
            self.publishBestHookCommand()
        }
        activeExpiryWork[id] = work
        serialQueue.asyncAfter(deadline: .now() + maxHookActiveDuration, execute: work)
    }

    private func scheduleHookDismiss(after delay: TimeInterval) {
        hookDisplayDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.hookDisplayDismissWork = nil
            self.shortHookTimes.removeAll()
            self.publishBestHookCommand()
        }
        hookDisplayDismissWork = work
        serialQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func publishBestHookCommand() {
        if let latest = runningHookCommands.values.max(by: { $0.startTime < $1.startTime }) {
            publishHookCommand(.active(latest.category, latest.compactName, timestamp: latest.startTime))
        } else {
            publishHookCommand(nil)
        }
    }

    private func clearRunningHookCommands() {
        activeExpiryWork.values.forEach { $0.cancel() }
        activeExpiryWork.removeAll()
        runningHookCommands.removeAll()
        publishBestHookCommand()
    }

    private func publishHookCommand(_ presentation: HookCommandPresentation?) {
        DispatchQueue.main.async { [weak self] in
            self?.compactCommand = presentation
        }
    }

    private func addRecord(_ name: String, icon: String, color: Color, status: String, timestamp: Date) {
        let record = ToolCallRecord(
            timestamp: timestamp,
            toolName: name,
            icon: icon,
            color: color,
            status: status,
            output: nil
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recentToolCalls.insert(record, at: 0)
            if self.recentToolCalls.count > 30 {
                self.recentToolCalls = Array(self.recentToolCalls.prefix(30))
            }
        }
    }

    private func commandString(from event: [String: Any]) -> String? {
        guard let toolName = event["tool_name"] as? String, toolName == "Bash" else { return nil }
        if let command = event["command"] as? String {
            return command
        }
        if let input = event["tool_input"] as? [String: Any],
           let command = input["command"] as? String {
            return command
        }
        return nil
    }

    private func sessionKey(from event: [String: Any]) -> String {
        for key in ["session_id", "conversation_id", "transcript_path"] {
            if let value = event[key] as? String, !value.isEmpty {
                return value
            }
        }
        return "unknown"
    }

    private func toolUseID(from event: [String: Any], command: String, timestamp: Date) -> String {
        if let value = event["tool_use_id"] as? String, !value.isEmpty {
            return value
        }
        if let value = event["tool_call_id"] as? String, !value.isEmpty {
            return value
        }
        return "\(sessionKey(from: event)):\(command):\(timestamp.timeIntervalSince1970)"
    }

    private func eventDate(from event: [String: Any]) -> Date {
        if let timestamp = event["timestamp"] as? Double {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = event["timestamp"] as? NSNumber {
            return Date(timeIntervalSince1970: timestamp.doubleValue)
        }
        if let timestamp = event["timestamp"] as? String, let value = Double(timestamp) {
            return Date(timeIntervalSince1970: value)
        }
        return Date()
    }

    private func displayCommandName(_ command: String) -> String {
        CommandDisplayFormatter.displayName(command)
    }

    private func compactCommandName(_ command: String) -> String {
        CommandDisplayFormatter.compactName(command)
    }
}

private extension HookCommandPresentation {
    static func active(_ category: ProcessMonitor.CommandCategory, _ name: String, timestamp: Date) -> HookCommandPresentation {
        HookCommandPresentation(phase: .active, category: category, name: name, count: 1, timestamp: timestamp)
    }

    static func recent(_ category: ProcessMonitor.CommandCategory, _ name: String, timestamp: Date) -> HookCommandPresentation {
        HookCommandPresentation(phase: .recent, category: category, name: name, count: 1, timestamp: timestamp)
    }

    static func burst(_ category: ProcessMonitor.CommandCategory, _ name: String, count: Int, timestamp: Date) -> HookCommandPresentation {
        HookCommandPresentation(phase: .burst, category: category, name: name, count: count, timestamp: timestamp)
    }
}

private func codexHookEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<CodexHookWatcher>.fromOpaque(info).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var swiftPaths: [String] = []
    for i in 0..<CFArrayGetCount(paths) {
        if let cfStr = CFArrayGetValueAtIndex(paths, i) {
            let str = Unmanaged<CFString>.fromOpaque(cfStr).takeUnretainedValue() as String
            swiftPaths.append(str)
        }
    }

    watcher.handleFSEvent(paths: swiftPaths)
}
