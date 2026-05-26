import Foundation
import Combine

// MARK: - 状态管理器
// 整合 Codex hook 和进程监控，统一输出 compactPresentation 给 UI。
class StatusManager: ObservableObject {
    @Published var workState: AGWorkState = .idle
    @Published var compactPresentation: CompactPresentation = .ambient(.idle)

    @Published var recentToolCalls: [ToolCallRecord] = []
    @Published var isConversationActive = false
    @Published var taskStartTime: Date?
    @Published var activeCommandCount: Int = 0
    @Published var activeConversationCount: Int = 0

    private let codexHookWatcher: CodexHookWatcher
    let processMonitor: ProcessMonitor
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    var elapsedTimeString: String {
        guard let start = taskStartTime else { return "" }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)s" }
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return "\(minutes)m\(seconds)s"
    }

    init() {
        self.codexHookWatcher = CodexHookWatcher()
        self.processMonitor = ProcessMonitor()
        self.codexHookWatcher.setEnabled(true)
        bindCodexHookWatcher()
        bindProcessMonitor()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.workState.isActive else { return }
            self.objectWillChange.send()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func bindCodexHookWatcher() {
        codexHookWatcher.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                if self.processMonitor.isRunningCommand {
                    if case .completed = newState {
                        self.applyState(newState)
                        self.recomputePresentation()
                    }
                    return
                }
                self.applyState(newState)
                self.recomputePresentation()
            }
            .store(in: &cancellables)

        codexHookWatcher.$recentToolCalls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                guard let self = self else { return }
                for record in records {
                    if !self.recentToolCalls.contains(where: {
                        $0.toolName == record.toolName && abs($0.timestamp.timeIntervalSince(record.timestamp)) < 1
                    }) {
                        self.recentToolCalls.insert(record, at: 0)
                    }
                }
                if self.recentToolCalls.count > 30 {
                    self.recentToolCalls = Array(self.recentToolCalls.prefix(30))
                }
            }
            .store(in: &cancellables)

        codexHookWatcher.$activeTurnCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self else { return }
                self.isConversationActive = count > 0
                self.activeConversationCount = count
            }
            .store(in: &cancellables)
    }

    private func bindProcessMonitor() {
        processMonitor.$activeCommands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] commands in
                guard let self = self else { return }
                self.activeCommandCount = commands.count

                if let cmd = commands.last {
                    self.applyState(.executing(cmd.category, cmd.displayName))
                } else if case .executing = self.workState {
                    self.applyState(.completed)
                }

                self.recomputePresentation()
            }
            .store(in: &cancellables)

        processMonitor.$commandHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] history in
                guard let self = self else { return }
                for event in history.prefix(5) {
                    if !self.recentToolCalls.contains(where: {
                        $0.toolName == event.displayName && abs($0.timestamp.timeIntervalSince(event.startTime)) < 1
                    }) {
                        let record = ToolCallRecord(
                            timestamp: event.startTime,
                            toolName: event.displayName,
                            icon: event.category.icon,
                            color: event.category.color,
                            status: event.isFinished ? "completed" : "running",
                            output: nil
                        )
                        self.recentToolCalls.insert(record, at: 0)
                    }
                }
                if self.recentToolCalls.count > 30 {
                    self.recentToolCalls = Array(self.recentToolCalls.prefix(30))
                }
            }
            .store(in: &cancellables)

        processMonitor.$flashCommand
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputePresentation() }
            .store(in: &cancellables)

        processMonitor.$burstCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputePresentation() }
            .store(in: &cancellables)
    }

    private func applyState(_ newState: AGWorkState) {
        let oldState = workState

        if !oldState.isActive && newState.isActive {
            taskStartTime = Date()
        }
        if !newState.isActive {
            taskStartTime = nil
        }

        workState = newState
    }

    private func recomputePresentation() {
        if let cmd = processMonitor.activeCommands.last {
            compactPresentation = .active(cmd.category, cmd.compactName)
            return
        }

        if processMonitor.burstCount >= 3 {
            let dominantCat = processMonitor.flashCommand?.category ?? .executing
            compactPresentation = .burst(processMonitor.burstCount, dominantCat)
            return
        }

        if let flash = processMonitor.flashCommand {
            compactPresentation = .recent(flash.category, flash.compactName)
            return
        }

        compactPresentation = .ambient(workState)
    }
}
