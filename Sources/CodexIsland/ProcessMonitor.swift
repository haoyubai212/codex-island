import Foundation
import Combine
import SwiftUI
import Darwin
import os

// MARK: - 零 fork 进程快照工具
// 使用 libproc/sysctl 内核 API 直接读取进程信息，完全避免 shell 调用

// macOS 有 proc_listchildpids 但没有公开头文件声明
@_silgen_name("proc_listchildpids")
func proc_listchildpids(_ ppid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

struct ProcessSnapshotter {
    // 获取指定进程的所有直接子进程 PID（O(1)，不扫描全表）
    static func childPIDs(of parentPID: Int32) -> [Int32] {
        // 先获取子进程数量
        let count = proc_listchildpids(parentPID, nil, 0)
        guard count > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(count))
        let actual = proc_listchildpids(parentPID, &pids, Int32(MemoryLayout<Int32>.size * Int(count)))
        guard actual > 0 else { return [] }

        return Array(pids.prefix(Int(actual))).filter { $0 > 0 }
    }

    // 获取进程可执行文件路径
    static func executablePath(of pid: Int32) -> String? {
        var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    // 获取进程完整 argv（通过 sysctl KERN_PROCARGS2）
    static func argv(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // 先获取缓冲区大小
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // 前 4 字节是 argc
        guard size > MemoryLayout<Int32>.size else { return nil }
        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)

        // 跳过 argc 和 exec_path（以 null 结尾）
        var offset = MemoryLayout<Int32>.size
        // 跳过可执行文件路径
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // 跳过 null 填充
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // 读取 argv
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            if end > offset {
                let str = String(bytes: buffer[offset..<end], encoding: .utf8) ?? ""
                args.append(str)
            }
            offset = end + 1
        }

        return args.isEmpty ? nil : args
    }

    // 获取进程的命令行字符串（合并 argv 前几个元素）
    static func commandString(of pid: Int32) -> String? {
        if let args = argv(of: pid) {
            // 取前 5 个参数，避免超长
            let relevant = args.prefix(5).map { arg -> String in
                // 去掉完整路径，只保留 basename
                if arg.hasPrefix("/") {
                    return (arg as NSString).lastPathComponent
                }
                return arg
            }
            return relevant.joined(separator: " ")
        }
        // 退而使用路径 basename
        if let path = executablePath(of: pid) {
            return (path as NSString).lastPathComponent
        }
        return nil
    }

    // Codex Desktop / CLI 宿主进程。Codex 命令通常由 codex app-server spawn 出 sh -lc。
    private static var cachedCodexHostPIDs: Set<Int32> = []
    private static var lastCodexHostScanTime: Date = .distantPast
    fileprivate(set) static var codexHostPIDs: Set<Int32> = []

    static func findCodexHostPIDs() -> Set<Int32> {
        let now = Date()

        if !cachedCodexHostPIDs.isEmpty {
            cachedCodexHostPIDs = cachedCodexHostPIDs.filter { kill($0, 0) == 0 }
            codexHostPIDs = codexHostPIDs.filter { kill($0, 0) == 0 }
        }

        if !cachedCodexHostPIDs.isEmpty && now.timeIntervalSince(lastCodexHostScanTime) < 30 {
            return cachedCodexHostPIDs
        }

        let allCount = proc_listallpids(nil, 0)
        guard allCount > 0 else { return cachedCodexHostPIDs }

        var allPIDs = [Int32](repeating: 0, count: Int(allCount))
        let actualCount = proc_listallpids(&allPIDs, Int32(MemoryLayout<Int32>.size * Int(allCount)))

        var hosts: Set<Int32> = []
        for i in 0..<Int(actualCount) {
            let pid = allPIDs[i]
            if pid <= 0 { continue }
            guard let path = executablePath(of: pid) else { continue }

            let name = (path as NSString).lastPathComponent
            guard name == "codex" else { continue }

            let args = argv(of: pid) ?? []
            if isCodexHost(path: path, argv: args) {
                hosts.insert(pid)
            }
        }

        cachedCodexHostPIDs = hosts
        codexHostPIDs = hosts
        lastCodexHostScanTime = now
        return cachedCodexHostPIDs
    }

    private static func isCodexHost(path: String, argv: [String]) -> Bool {
        let joined = argv.joined(separator: " ")

        if argv.contains("app-server") {
            return true
        }

        if path.contains("/Codex.app/Contents/Resources/codex") {
            return true
        }

        if path.contains("/openai.chatgpt-") && path.hasSuffix("/codex") {
            return true
        }

        if path.hasSuffix("/bin/codex") || path.hasSuffix("/codex") {
            return joined.contains("codex") || argv.isEmpty
        }

        return false
    }

    static func isShellExecutablePath(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name == "sh" || name == "zsh" || name == "bash" || name == "fish"
    }
}

// MARK: - 终端进程监控 (kqueue + 零 fork 快照)
class ProcessMonitor: ObservableObject {
    // 当前正在运行的命令（按 startTime 排序）
    @Published var activeCommands: [CommandInfo] = []
    @Published var isRunningCommand: Bool = false
    @Published var currentCommand: CommandInfo?

    // 命令事件历史
    @Published var commandHistory: [CommandEvent] = []

    // 短命令闪现 + 连续命令计数
    @Published var flashCommand: CommandEvent? = nil
    @Published var burstCount: Int = 0
    // 活跃会话数
    @Published var sessionCount: Int = 0

    // MARK: - 数据类型

    struct CommandInfo: Identifiable, Equatable {
        let id = UUID()
        let pid: Int32
        let command: String
        let category: CommandCategory
        let displayName: String
        let compactName: String  // compact 态用的短名

        static func == (lhs: CommandInfo, rhs: CommandInfo) -> Bool {
            lhs.pid == rhs.pid && lhs.command == rhs.command
        }
    }

    struct CommandEvent: Identifiable {
        let id = UUID()
        let pid: Int32
        let command: String
        let category: CommandCategory
        let displayName: String
        let compactName: String
        let startTime: Date
        var endTime: Date?

        var duration: TimeInterval { (endTime ?? Date()).timeIntervalSince(startTime) }
        var isFinished: Bool { endTime != nil }
    }

    // 命令类别
    enum CommandCategory: String, Equatable {
        case building, testing, serving, gitOp, searching
        case reading, writing, installing, managing, executing
        case collaboration, networking, remote, browsing

        var icon: String {
            switch self {
            case .building:   return "hammer.fill"
            case .testing:    return "flask.fill"
            case .serving:    return "globe"
            case .gitOp:      return "arrow.triangle.branch"
            case .searching:  return "magnifyingglass"
            case .reading:    return "doc.text"
            case .writing:    return "doc.text.fill"
            case .installing: return "shippingbox.fill"
            case .managing:   return "gearshape.fill"
            case .executing:  return "terminal.fill"
            case .collaboration: return "person.2.fill"
            case .networking: return "arrow.up.arrow.down.circle.fill"
            case .remote:     return "desktopcomputer"
            case .browsing:   return "cursorarrow.click.2"
            }
        }

        var color: Color {
            switch self {
            case .building:   return .orange
            case .testing:    return .purple
            case .serving:    return .green
            case .gitOp:      return .cyan
            case .searching:  return .blue
            case .reading:    return .white
            case .writing:    return .mint
            case .installing: return .yellow
            case .managing:   return .gray
            case .executing:  return .indigo
            case .collaboration: return .pink
            case .networking: return .teal
            case .remote:     return .red
            case .browsing:   return Color(red: 0.26, green: 0.52, blue: 0.96)  // Chrome 蓝 #4285F4
            }
        }

        var label: String {
            switch self {
            case .building:   return "编译中"
            case .testing:    return "测试中"
            case .serving:    return "运行服务"
            case .gitOp:      return "Git 操作"
            case .searching:  return "搜索中"
            case .reading:    return "查看文件"
            case .writing:    return "写文件"
            case .installing: return "安装依赖"
            case .managing:   return "管理进程"
            case .executing:  return "执行命令"
            case .collaboration: return "小组会"
            case .networking: return "网络请求"
            case .remote:     return "远程连接"
            case .browsing:   return "浏览器"
            }
        }
    }

    // MARK: - 内部状态（所有状态只在 monitorQueue 上读写）

    private var kqueueFD: Int32 = -1
    private var monitoredZshPIDs: Set<Int32> = []
    private var trackedChildren: [Int32: CommandEvent] = [:]
    // 每个 zsh 的已知子进程集合，用于 diff
    private var knownChildrenByShell: [Int32: Set<Int32>] = [:]
    // 子进程 → 父 zsh 的映射，用于退出时清理 knownChildren
    private var childToShell: [Int32: Int32] = [:]
    // 待确认的子进程（argv 暂时读不到，等重采样）
    private var pendingChildren: Set<Int32> = []
    // CodexIsland 自身的 PID，用于排除自身
    private let selfPID = getpid()

    private let monitorQueue = DispatchQueue(label: "com.codexisland.process-monitor", qos: .utility)
    private var discoveryTimer: DispatchSourceTimer?
    private var currentDiscoveryInterval: TimeInterval = 5.0
    private var kqueueThread: Thread?

    // 连续命令追踪
    private var recentCommandTimes: [Date] = []
    private var flashDismissWork: DispatchWorkItem?

    // os_log 调试日志（零磁盘IO）
    private static let logger = Logger(subsystem: "com.codexisland", category: "process")
    private func log(_ msg: String) {
        Self.logger.debug("\(msg, privacy: .public)")
    }

    // MARK: - 生命周期

    init() {
        setupKqueue()
        startDiscoveryTimer()
        startChildPollTimer()  // 轮询发现子进程（NOTE_FORK 已移除）
        monitorQueue.async { [weak self] in
            self?.discoverZshSessions()
        }
    }

    deinit {
        discoveryTimer?.cancel()
        childPollTimer?.cancel()
        if kqueueFD >= 0 { close(kqueueFD) }
    }

    private func resetMonitoringState() {
        monitoredZshPIDs.removeAll()
        trackedChildren.removeAll()
        knownChildrenByShell.removeAll()
        childToShell.removeAll()
        pendingChildren.removeAll()
        candidates.removeAll()
        recentCommandTimes.removeAll()
        flashDismissWork?.cancel()
        flashDismissWork = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeCommands = []
            self.isRunningCommand = false
            self.currentCommand = nil
            self.commandHistory = []
            self.flashCommand = nil
            self.burstCount = 0
            self.sessionCount = 0
        }
    }

    // MARK: - kqueue 设置

    private func setupKqueue() {
        kqueueFD = kqueue()
        guard kqueueFD >= 0 else {
            log("❌ 无法创建 kqueue")
            return
        }
        log("✅ kqueue 创建成功, fd=\(kqueueFD)")

        let thread = Thread { [weak self] in
            self?.kqueueLoop()
        }
        thread.name = "com.codexisland.kqueue"
        thread.qualityOfService = .utility
        thread.start()
        kqueueThread = thread
    }

    // kqueue 事件循环
    private func kqueueLoop() {
        var events = [Darwin.kevent](repeating: Darwin.kevent(), count: 16)

        while kqueueFD >= 0 {
            var timeout = timespec(tv_sec: 1, tv_nsec: 0)
            let count = kevent(kqueueFD, nil, 0, &events, Int32(events.count), &timeout)

            if count < 0 {
                if errno == EINTR { continue }
                log("❌ kevent 错误: \(errno)")
                break
            }

            for i in 0..<Int(count) {
                let ev = events[i]
                let pid = Int32(ev.ident)
                let fflags = ev.fflags

                // 只处理 NOTE_EXIT（不再用 NOTE_FORK，避免 exec 窗口 proc_lock 竞争）
                if fflags & UInt32(NOTE_EXIT) != 0 {
                    monitorQueue.async { [weak self] in
                        self?.handleExit(pid: pid)
                    }
                }
            }
        }
    }

    // 注册 kqueue 监控 zsh PID
    private func watchZsh(_ pid: Int32) {
        guard !monitoredZshPIDs.contains(pid), kqueueFD >= 0 else { return }

        var ev = Darwin.kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: UInt32(NOTE_EXIT),  // 只监控退出（不用 NOTE_FORK，改用轮询发现子进程）
            data: 0,
            udata: nil
        )
        let result = kevent(kqueueFD, &ev, 1, nil, 0, nil)
        if result >= 0 {
            monitoredZshPIDs.insert(pid)
            knownChildrenByShell[pid] = Set(ProcessSnapshotter.childPIDs(of: pid))
            let count = monitoredZshPIDs.count
            DispatchQueue.main.async { self.sessionCount = count }
            log("👁️ 开始监控 zsh PID \(pid)")
        } else {
            log("⚠️ 无法监控 zsh PID \(pid), errno=\(errno)")
        }
    }

    // 注册子进程退出监控
    private func watchChildExit(_ pid: Int32) {
        guard kqueueFD >= 0 else { return }
        var ev = Darwin.kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT),
            fflags: UInt32(NOTE_EXIT),
            data: 0,
            udata: nil
        )
        kevent(kqueueFD, &ev, 1, nil, 0, nil)
    }

    // MARK: - 轮询式子进程发现（替代 NOTE_FORK，避免 exec 窗口 proc_lock 竞争）

    // 候选子进程：首次发现但还没读 argv 的
    private struct CandidateChild {
        let shellPID: Int32
        let firstSeen: Date
    }
    private var candidates: [Int32: CandidateChild] = [:]
    private var childPollTimer: DispatchSourceTimer?
    private var currentPollInterval: Int = 1000  // 毫秒
    
    private func startChildPollTimer() {
        childPollTimer = DispatchSource.makeTimerSource(queue: monitorQueue)
        childPollTimer?.schedule(deadline: .now() + 0.5, repeating: .milliseconds(currentPollInterval))
        childPollTimer?.setEventHandler { [weak self] in
            self?.pollChildren()
            self?.adjustPollInterval()
        }
        childPollTimer?.resume()
    }

    // 自适应轮询：有活跃命令 → 200ms；空闲时 2000ms。
    private func adjustPollInterval() {
        let targetInterval = trackedChildren.isEmpty && candidates.isEmpty ? 2000 : 200
        if targetInterval != currentPollInterval {
            currentPollInterval = targetInterval
            childPollTimer?.schedule(deadline: .now() + .milliseconds(targetInterval), repeating: .milliseconds(targetInterval))
            log("⏱️ 轮询间隔调整为 \(targetInterval)ms")
        }
    }

    // 轮询所有监控宿主的子进程
    private func pollChildren() {
        let now = Date()

        for zshPID in monitoredZshPIDs {
            let currentChildren = Set(ProcessSnapshotter.childPIDs(of: zshPID))
            let known = knownChildrenByShell[zshPID] ?? []
            let newChildren = currentChildren.subtracting(known)

            knownChildrenByShell[zshPID] = currentChildren

            for childPID in newChildren {
                if childPID == selfPID { continue }
                if trackedChildren[childPID] != nil { continue }
                if candidates[childPID] != nil { continue }

                // Codex app-server/CLI 直出宿主会直接 spawn 临时 shell 或真实命令。
                if isDirectSpawnHost(zshPID) {
                    // 临时 shell → 穿透一层读取内部命令
                    if let path = ProcessSnapshotter.executablePath(of: childPID),
                       ProcessSnapshotter.isShellExecutablePath(path) {
                        if let cmd = commandStringForDisplay(pid: childPID), !Self.isNoise(cmd) {
                            registerChild(childPID, command: cmd, zshPID: zshPID)
                            log("🎯 Codex shell 命令: PID \(childPID) → \(cmd)")
                        } else {
                            childToShell[childPID] = zshPID
                            candidates[childPID] = CandidateChild(shellPID: zshPID, firstSeen: now)
                            watchChildExit(childPID)
                        }
                        continue
                    }

                    // 非 zsh 的直接子进程（git, swift, curl 等）→ 立即读 argv 注册
                    // language_server spawn 的进程 exec 已完成，无需 300ms grace
                    if let cmdString = commandStringForDisplay(pid: childPID), !Self.isNoise(cmdString) {
                        registerChild(childPID, command: cmdString, zshPID: zshPID)
                        log("⚡ 新架构直接命令: PID \(childPID) → \(cmdString)")
                    } else {
                        // 读不到 → 短命候选
                        childToShell[childPID] = zshPID
                        candidates[childPID] = CandidateChild(shellPID: zshPID, firstSeen: now)
                        watchChildExit(childPID)
                    }
                    continue
                }

                // 旧架构：新发现的子进程 → 先标记为候选，等 300ms 再读 argv
                childToShell[childPID] = zshPID
                candidates[childPID] = CandidateChild(shellPID: zshPID, firstSeen: now)
                watchChildExit(childPID)
            }
        }

        // 处理已成熟的候选（存活超过 300ms → exec 完成后安全读 argv）
        for (pid, candidate) in candidates {
            let age = now.timeIntervalSince(candidate.firstSeen)

            if kill(pid, 0) != 0 {
                // 已退出 → 根据存活时间决定处理方式
                candidates.removeValue(forKey: pid)
                if age < 0.3 {
                    // <300ms 快闪 → 只计 burst（不读 argv，避免 exec 争锁）
                    DispatchQueue.main.async { [weak self] in
                        self?.recordBurstTick()
                    }
                } else {
                    // 300ms+ → 尝试读 argv 做短命令闪现（exec 已完成）
                    if let cmdString = commandStringForDisplay(pid: pid), !Self.isNoise(cmdString) {
                        registerChild(pid, command: cmdString, zshPID: candidate.shellPID)
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            self?.recordBurstTick()
                        }
                    }
                }
                continue
            }

            // 还活着且超过 300ms → exec 完成后安全读 argv
            if age >= 0.3 {
                candidates.removeValue(forKey: pid)
                if let cmdString = commandStringForDisplay(pid: pid) {
                    if Self.isNoise(cmdString) { continue }
                    registerChild(pid, command: cmdString, zshPID: candidate.shellPID)
                } else {
                    // argv 还是读不到但还活着 → pending
                    pendingChildren.insert(pid)
                    log("🔱 POLL: PID \(pid), argv 待读取（pending）")
                }
            }
        }

        // 🐛 兜底：检查 trackedChildren 中的进程是否还活着
        // kqueue 偶尔会漏掉 NOTE_EXIT 事件，导致已退出的命令永远显示为运行中
        var deadPIDs: [Int32] = []
        for (pid, _) in trackedChildren {
            if kill(pid, 0) != 0 {
                deadPIDs.append(pid)
            }
        }
        for pid in deadPIDs {
            if var event = trackedChildren[pid] {
                event.endTime = Date()
                trackedChildren.removeValue(forKey: pid)
                if let shellPID = childToShell[pid] {
                    knownChildrenByShell[shellPID]?.remove(pid)
                }
                childToShell.removeValue(forKey: pid)
                log("🧹 兜底清理: PID \(pid) → \(event.displayName)（kqueue 漏掉了退出事件）")
                publishCompletedEvent(event)
            }
        }
        if !deadPIDs.isEmpty {
            updateActiveCommands()
        }
    }

    // 注册一个新的子进程命令
    private func registerChild(_ childPID: Int32, command: String, zshPID: Int32) {
        // 所有注册路径的最后一道入口保护。调用方通常已过滤，但新路径或
        // argv 短暂形态不应有机会把 MCP 宿主写入 trackedChildren。
        guard !Self.isNoise(command) else {
            pendingChildren.remove(childPID)
            candidates.removeValue(forKey: childPID)
            return
        }

        let category = Self.categorizeCommand(command)
        let displayName = makeDisplayName(command)
        let compactName = makeCompactName(command)

        let event = CommandEvent(
            pid: childPID,
            command: command,
            category: category,
            displayName: displayName,
            compactName: compactName,
            startTime: Date()
        )
        trackedChildren[childPID] = event
        childToShell[childPID] = zshPID
        pendingChildren.remove(childPID)
        log("🚀 新命令: PID \(childPID) → \(displayName) [\(category.label)]")
        if kill(childPID, 0) == 0 {
            watchChildExit(childPID)
            // 不立即更新 activeCommands，等 grace period
            scheduleActivePromotion(pid: childPID)
        } else {
            var completed = event
            completed.endTime = Date()
            trackedChildren.removeValue(forKey: childPID)
            log("⚡ 快闪: PID \(childPID) → \(displayName)")
            publishCompletedEvent(completed)
            updateActiveCommands()
        }
    }

    // Grace period：只有存活超过 1s 的命令才升格为 active
    private func scheduleActivePromotion(pid: Int32) {
        monitorQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            // 1s 后还在 trackedChildren 里 → 升格为 active
            if self.trackedChildren[pid] != nil {
                self.log("📌 升格 active: PID \(pid)")
                self.updateActiveCommands()
            }
        }
    }

    // resampleChild 已移除 — 轮询方案在 pollChildren() 中处理命令名解析

    private func handleExit(pid: Int32) {
        // pending child 退出
        if pendingChildren.contains(pid) {
            pendingChildren.remove(pid)
            // 从 knownChildren 中清理
            if let shellPID = childToShell[pid] {
                knownChildrenByShell[shellPID]?.remove(pid)
            }
            childToShell.removeValue(forKey: pid)
            return
        }

        // zsh 退出 → 同时清理所有属于这个 zsh 的子命令
        if monitoredZshPIDs.contains(pid) {
            monitoredZshPIDs.remove(pid)
            knownChildrenByShell.removeValue(forKey: pid)

            // 🐛 修复：zsh 退出时清理其下属的所有 trackedChildren
            // 否则复合命令（如 sleep 60 && cmd）取消后，记录会永远留在 active 列表
            let orphanedPIDs = childToShell.filter { $0.value == pid }.map { $0.key }
            for orphanPID in orphanedPIDs {
                if var event = trackedChildren[orphanPID] {
                    event.endTime = Date()
                    trackedChildren.removeValue(forKey: orphanPID)
                    log("🧹 清理孤儿命令: PID \(orphanPID) → \(event.displayName)")
                    publishCompletedEvent(event)
                }
                childToShell.removeValue(forKey: orphanPID)
                candidates.removeValue(forKey: orphanPID)
                pendingChildren.remove(orphanPID)
            }

            let count = monitoredZshPIDs.count
            DispatchQueue.main.async { self.sessionCount = count }
            log("🔚 zsh 退出: PID \(pid), 清理了 \(orphanedPIDs.count) 个孤儿命令")
            updateActiveCommands()
            return
        }

        // 子命令退出
        if var event = trackedChildren[pid] {
            event.endTime = Date()
            trackedChildren.removeValue(forKey: pid)

            // 从 knownChildren 中清理，防止 PID 复用漏检
            if let shellPID = childToShell[pid] {
                knownChildrenByShell[shellPID]?.remove(pid)
            }
            childToShell.removeValue(forKey: pid)

            log("🏁 完成: PID \(pid) → \(event.displayName), \(String(format: "%.1f", event.duration))s")

            publishCompletedEvent(event)
            updateActiveCommands()
        }
    }

    // 发布完成事件到主线程
    private func publishCompletedEvent(_ event: CommandEvent) {
        // 防止早期注册时漏网的后台宿主进入历史、短命令闪现或 burst。
        guard !Self.isNoise(event.command) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.commandHistory.insert(event, at: 0)
            if self.commandHistory.count > 50 {
                self.commandHistory = Array(self.commandHistory.prefix(50))
            }

            // 按三档策略处理展示
            let dur = event.duration
            if dur < 0.15 {
                // <150ms → 只计入 burst，不单独显示
                self.recordBurstTick()
            } else if dur < 1.0 {
                // 150ms~1s → 闪现或累加 burst
                self.handleShortCommand(event)
            }
            // >1s 的命令之前已经在 active 里展示过了，完成后自然移除
        }
    }

    // MARK: - 短命令展示策略

    // burst 计时器记录
    private func recordBurstTick() {
        let now = Date()
        recentCommandTimes.append(now)
        recentCommandTimes = recentCommandTimes.filter { now.timeIntervalSince($0) < 1.5 }

        if recentCommandTimes.count >= 3 {
            burstCount = recentCommandTimes.count
            flashCommand = nil
            resetDismissTimer(for: .burst)
        }
        // <3 个 tick 时不做任何展示
    }

    private func handleShortCommand(_ event: CommandEvent) {
        let now = Date()
        recentCommandTimes.append(now)
        recentCommandTimes = recentCommandTimes.filter { now.timeIntervalSince($0) < 1.5 }

        if recentCommandTimes.count >= 3 {
            // 连续命令模式
            burstCount = recentCommandTimes.count
            flashCommand = nil
            resetDismissTimer(for: .burst)
        } else {
            // 单个短命令闪现
            burstCount = 0
            flashCommand = event
            resetDismissTimer(for: .flash)
        }
    }

    private enum DismissType { case flash, burst }
    private func resetDismissTimer(for type: DismissType) {
        flashDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            switch type {
            case .flash: self.flashCommand = nil
            case .burst: self.burstCount = 0
            }
        }
        let delay: TimeInterval = type == .flash ? 1.2 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        flashDismissWork = work
    }

    // MARK: - 活跃命令列表

    private func updateActiveCommands() {
        // 只有存活超过 1s 的才算 active（grace period）
        let now = Date()
        let sorted = trackedChildren.values
            // 发布 UI 前再次过滤，保证即使某条注册路径漏掉入口 guard，
            // MCP/内部宿主也不会进入 active count 或展开态。
            .filter { !Self.isNoise($0.command) && now.timeIntervalSince($0.startTime) >= 1.0 }
            .sorted { $0.startTime < $1.startTime }
        let commands = sorted.map { event in
            CommandInfo(
                pid: event.pid,
                command: event.command,
                category: event.category,
                displayName: event.displayName,
                compactName: event.compactName
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeCommands = commands
            self.isRunningCommand = !commands.isEmpty
            self.currentCommand = commands.last  // 优先显示最新命令（如 agent-browser 优先于长驻 Chrome）
        }
    }

    // MARK: - Codex 宿主发现（5s 轮询，零 fork）

    private func startDiscoveryTimer() {
        discoveryTimer = DispatchSource.makeTimerSource(queue: monitorQueue)
        currentDiscoveryInterval = 5.0
        discoveryTimer?.schedule(deadline: .now(), repeating: currentDiscoveryInterval)
        discoveryTimer?.setEventHandler { [weak self] in
            self?.discoverZshSessions()
        }
        discoveryTimer?.resume()
    }

    private func discoverZshSessions() {
        discoverCodexHosts()
    }

    private func discoverCodexHosts() {
        let hostPIDs = ProcessSnapshotter.findCodexHostPIDs()
        for pid in hostPIDs {
            watchZsh(pid)
        }

        for hostPID in hostPIDs {
            let children = ProcessSnapshotter.childPIDs(of: hostPID)
            for childPID in children {
                if childPID == selfPID { continue }
                if trackedChildren[childPID] != nil { continue }
                if monitoredZshPIDs.contains(childPID) { continue }

                guard let cmdString = commandStringForDisplay(pid: childPID) else { continue }
                if Self.isNoise(cmdString) { continue }

                let event = CommandEvent(
                    pid: childPID,
                    command: cmdString,
                    category: Self.categorizeCommand(cmdString),
                    displayName: makeDisplayName(cmdString),
                    compactName: makeCompactName(cmdString),
                    startTime: Date()
                )
                trackedChildren[childPID] = event
                childToShell[childPID] = hostPID
                watchChildExit(childPID)
                log("📎 Codex 遗漏: PID \(childPID) → \(event.displayName)")
                updateActiveCommands()
            }
        }
    }

    private func isDirectSpawnHost(_ pid: Int32) -> Bool {
        ProcessSnapshotter.codexHostPIDs.contains(pid)
    }

    private func commandStringForDisplay(pid: Int32) -> String? {
        if let path = ProcessSnapshotter.executablePath(of: pid),
           ProcessSnapshotter.isShellExecutablePath(path),
           let argv = ProcessSnapshotter.argv(of: pid),
           let command = extractCommandFromShellArgv(argv) {
            return command
        }

        return ProcessSnapshotter.commandString(of: pid)
    }

    // MARK: - 新架构辅助：从临时 shell 的 argv 提取实际命令
    // 例如 argv = ["/bin/zsh", "-c", "swift build 2>&1"] → "swift build 2>&1"
    // 或 argv = ["/bin/bash", "-c", "git status"] → "git status"
    private func extractCommandFromShellArgv(_ argv: [String]) -> String? {
        guard argv.count >= 2 else { return nil }

        // 查找 -c 标志后面的内容
        if let cIndex = argv.firstIndex(of: "-c"), cIndex + 1 < argv.count {
            // -c 后面的所有参数合并为命令字符串
            let cmdParts = argv[(cIndex + 1)...]
            let cmd = cmdParts.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return cmd.isEmpty ? nil : cmd
        }

        // sh -lc / zsh -ilc 这类组合 flag
        for (index, arg) in argv.enumerated() where index + 1 < argv.count {
            guard arg.hasPrefix("-"), arg.dropFirst().contains("c") else { continue }
            let cmdParts = argv[(index + 1)...]
            let cmd = cmdParts.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return cmd.isEmpty ? nil : cmd
        }

        // 没有 -c → 可能是 zsh -il 或其他形式
        // 尝试取最后一个非 flag 参数
        if let last = argv.last,
           !last.hasPrefix("-"),
           !last.hasSuffix("/zsh"),
           !last.hasSuffix("/sh"),
           !last.hasSuffix("/bash"),
           !last.hasSuffix("/fish") {
            return last
        }

        return nil
    }

    // MARK: - 噪音过滤

    static func isNoise(_ command: String) -> Bool {
        let normalized = normalizedForNoiseMatching(command)

        // CodexIsland 自身
        if normalized.contains("codexisland") { return true }
        // 其他 hook / 通知桥内部命令。它们是状态同步副作用，不应占用完成态。
        if normalized.contains("clawd on desk.app") || normalized.contains("codex-hook.js") { return true }
        if normalized.hasPrefix("agently-cli message ") || normalized.contains(" agently-cli message ") { return true }
        // shell 载体（包括子 shell）
        if normalized == "zsh" || normalized == "-zsh" || normalized == "sh" || normalized == "bash" || normalized == "fish" { return true }
        if normalized.hasSuffix("/zsh") || normalized.hasSuffix("/sh") || normalized.hasSuffix("/bash") || normalized.hasSuffix("/fish") { return true }
        if normalized.hasPrefix("zsh -") || normalized.hasPrefix("sh -") || normalized.hasPrefix("bash -") || normalized.hasPrefix("fish -") { return true }
        // Codex Desktop / 插件运行时进程，不是用户命令。
        // `codex-code-mode-host` 是新版 Code Mode 的长生命周期执行宿主；
        // 它存在不代表有一条用户命令仍在运行。
        if isCodexAppServerLaunch(normalized) || normalized.contains("codex-code-mode-host") || normalized.contains("codex helper") { return true }
        if normalized.contains("node_repl") || normalized.contains("skycomputeruseclient") { return true }
        if normalized.contains("playwright-mcp") || normalized.contains("xcodebuildmcp") { return true }
        if normalized.contains("extension-host") || normalized.contains("bare-modifier-monitor") || normalized.contains("chrome_crashpad_handler") { return true }
        // MCP 相关进程（由 language_server 管理，不是用户命令）
        if normalized.contains("mcp-server") || normalized.contains("mcp-remote") { return true }
        if normalized.contains("@modelcontextprotocol/") { return true }
        // shadcn MCP 的 argv 在不同启动层可能表现为 npm/npx/node，且前面可能
        // 带 env/arch 包装。按 token 识别，避免依赖单一字符串前缀。
        if isShadcnMCPLaunch(normalized) { return true }
        // MCP 运行时子进程（node cli.js run-driver 等）
        if normalized.contains("run-driver") || normalized.contains("cli.js run") { return true }
        // 裸 npm/npx/node（AG 启动时 MCP 进程 argv 读取不完整，只返回 "npm"）
        if normalized == "npm" || normalized == "npx" || normalized == "node" { return true }
        // Node.js/npm/npx MCP 子进程
        if normalized.hasPrefix("npm exec ") && (normalized.contains("mcp") || normalized.contains("@stripe") || normalized.contains("@supabase") || normalized.contains("chrome-devtools")) { return true }
        if normalized.hasPrefix("npx ") && (normalized.contains("mcp") || normalized.contains("@stripe") || normalized.contains("@supabase") || normalized.contains("chrome-devtools")) { return true }
        // node cli.js --version（AG 启动时内部检查）
        if normalized.hasPrefix("node ") && normalized.contains("cli.js") { return true }
        // node npx -y <mcp-package>（AG 固定用这种形式启动所有 MCP 服务器，全部过滤）
        // 例：node npx -y chrome-devtools-mcp@latest --...
        if normalized.hasPrefix("node npx") { return true }
        // node + 其他已知 MCP 包名关键词（防止形式变化）
        if normalized.hasPrefix("node ") && (normalized.contains("mcp") || normalized.contains("chrome-devtools") || normalized.contains("brave-search") || normalized.contains("sequential-thinking")) { return true }
        // uv（Python MCP server runner）
        if normalized.hasPrefix("uv ") && normalized.contains("run") { return true }
        // Playwright（AG 内置浏览器自动化）
        if normalized.contains("ms-playwright") { return true }
        // macOS 系统噪音
        if normalized.contains("log stream") { return true }
        // conda shell 初始化噪音
        if normalized.contains("conda shell") || normalized.contains("conda activate") { return true }
        // git ls-remote：fetch 远程引用列表，非用户操作
        if normalized.hasPrefix("git ls-remote") || normalized.contains(" git ls-remote") { return true }
        // zsh dotdir init 噪音
        if normalized.contains("$zdotdir") { return true }
        return false
    }

    private static func normalizedForNoiseMatching(_ command: String) -> String {
        var tokens = command
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        // CommandDisplayFormatter 会隐藏这些包装器；过滤器必须在同一语义层匹配，
        // 否则原始的 `env node ...` 会漏网，界面却显示成 `node ...`。
        while let first = tokens.first {
            let executable = executableTokenName(first)
            if executable == "env" || executable == "command" {
                tokens.removeFirst()
                while let next = tokens.first, next.contains("=") && !next.hasPrefix("-") {
                    tokens.removeFirst()
                }
                continue
            }
            if executable == "arch" {
                tokens.removeFirst()
                while let next = tokens.first, next.hasPrefix("-") {
                    tokens.removeFirst()
                }
                continue
            }
            break
        }

        if !tokens.isEmpty {
            tokens[0] = executableTokenName(tokens[0])
        }
        return tokens.joined(separator: " ")
    }

    private static func isShadcnMCPLaunch(_ command: String) -> Bool {
        let tokens = command
            .split(whereSeparator: { $0.isWhitespace })
            .map { executableTokenName(String($0)) }

        guard let shadcnIndex = tokens.firstIndex(where: { $0 == "shadcn" || $0.hasPrefix("shadcn@") }),
              shadcnIndex + 1 < tokens.count,
              tokens[shadcnIndex + 1] == "mcp" else { return false }

        let allowedPrefixTokens: Set<String> = ["node", "npm", "npx", "exec", "env", "command", "arch", "--"]
        return tokens[..<shadcnIndex].allSatisfy { token in
            allowedPrefixTokens.contains(token) || token.hasPrefix("-") || token.contains("=")
        }
    }

    private static func isCodexAppServerLaunch(_ command: String) -> Bool {
        let tokens = command
            .split(whereSeparator: { $0.isWhitespace })
            .map { executableTokenName(String($0)) }

        guard tokens.first == "codex" else { return false }
        return tokens.dropFirst().contains("app-server")
    }

    private static func executableTokenName(_ token: String) -> String {
        let unquoted = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;"))
        return (unquoted as NSString).lastPathComponent
    }

    // MARK: - 命令分类

    static func categorizeCommand(_ command: String) -> CommandCategory {
        let lower = command.lowercased()

        // ACPX 小组会（优先匹配）
        if lower.contains("acpx") || lower.contains("acp ") {
            return .collaboration
        }
        // 浏览器自动化（方案A: CDP Chrome + agent-browser）
        if lower.contains("agent-browser") || lower.contains("--cdp") ||
           (lower.contains("google chrome") && lower.contains("--remote-debug")) ||
           lower.contains("chrome-cdp-profile") {
            return .browsing
        }
        if lower.contains("swift build") || lower.contains("swift-build") ||
           lower.contains("xcodebuild") ||
           lower.contains("make") || lower.contains("cargo build") ||
           lower.contains("npm run build") ||
           lower.contains("gcc") || lower.contains("g++") {
            return .building
        }
        if lower.contains("swift test") || lower.contains("swift-test") ||
           lower.contains("npm test") ||
           lower.contains("pytest") || lower.contains("jest") ||
           lower.contains("xctest") {
            return .testing
        }
        if lower.contains("npm run dev") || lower.contains("npm start") ||
           lower.contains("npx") || lower.contains("python -m http") ||
           lower.contains("flask run") || lower.contains("node ") {
            return .serving
        }
        if lower.contains("git ") || lower.hasPrefix("git") ||
           lower.contains("gh ") || lower.hasPrefix("gh ") {
            return .gitOp
        }
        if lower.contains("grep") || lower.contains("find ") ||
           lower.contains("rg ") || lower.contains("ag ") ||
           lower.contains("ack") {
            return .searching
        }
        if lower.contains("brew ") || lower.contains("brew.sh") || lower.contains("npm install") ||
           lower.contains("pip install") || lower.contains("apt ") ||
           lower.contains("cargo install") {
            return .installing
        }
        if lower.contains("pkill") || lower.contains("kill ") ||
           lower.contains("killall") {
            return .managing
        }
        // 网络请求
        if lower.contains("curl ") || lower.contains("wget ") ||
           lower.contains("http ") || lower.contains("httpie") {
            return .networking
        }
        // 远程连接
        if lower.hasPrefix("ssh ") || lower.contains("ssh ") ||
           lower.contains("scp ") || lower.contains("sftp ") ||
           lower.contains("autossh") {
            return .remote
        }
        if lower.hasPrefix("cat ") || lower.hasPrefix("head ") ||
           lower.hasPrefix("tail ") || lower.hasPrefix("ls") ||
           lower.hasPrefix("sed ") || lower.hasPrefix("awk ") ||
           lower.hasPrefix("wc ") || lower.hasPrefix("file ") {
            return .reading
        }
        if (lower.contains("echo ") && lower.contains(">")) ||
           lower.hasPrefix("mkdir ") || lower.hasPrefix("touch ") ||
           lower.hasPrefix("cp ") || lower.hasPrefix("mv ") {
            return .writing
        }

        return .executing
    }

    // MARK: - 显示名称

    // 完整名（expanded 面板用）
    private func makeDisplayName(_ command: String) -> String {
        CommandDisplayFormatter.displayName(command)
    }

    // 短名（compact 灵动岛用，保留命令 + 第一个参数）
    private func makeCompactName(_ command: String) -> String {
        CommandDisplayFormatter.compactName(command)
    }
}
