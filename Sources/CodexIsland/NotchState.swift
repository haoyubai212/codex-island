import SwiftUI

// MARK: - 灵动岛的三个视觉状态
enum NotchDisplayState: Equatable {
    case closed     // 折叠：与刘海融为一体的小药丸
    case compact    // 紧凑展开：左右弹性扩展，显示摘要信息
    case expanded   // 完全展开：向下展开，显示详细面板
}

// MARK: - Codex 的工作状态
enum AGWorkState: Equatable {
    case idle                                          // 💤 空闲
    case thinking                                      // 🧠 思考中（.pb 在变但无终端进程）
    case executing(ProcessMonitor.CommandCategory, String)  // ⚡ 执行命令（类别 + 显示名）
    case searching                                     // 🔍 搜索中（steps/ 有搜索结果）
    case completed                                     // ✅ 完成
    case error(String)                                 // ⚠️ 错误

    var icon: String {
        switch self {
        case .idle: return "moon.zzz.fill"
        case .thinking: return "sparkles"
        case .executing(let category, _): return category.icon
        case .searching: return "magnifyingglass"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .thinking: return "思考中..."
        case .executing(let category, let name):
            return name.isEmpty ? category.label : name
        case .searching: return "搜索中..."
        case .completed: return "完成"
        case .error(let msg): return msg
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .thinking: return Color(red: 0.43, green: 0.48, blue: 1.0)
        case .executing(let category, _): return category.color
        case .searching: return .blue
        case .completed: return .green
        case .error: return .red
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .completed: return false
        default: return true
        }
    }
}

// MARK: - Compact 态统一展示模型
// 优先级：active > burst > recent > ambient
enum CompactPresentation: Equatable {
    case active(ProcessMonitor.CommandCategory, String)   // 前台长命令运行中
    case recent(ProcessMonitor.CommandCategory, String)   // 短命令刚结束，闪现 ~1s
    case burst(Int, ProcessMonitor.CommandCategory)        // 短时间内 ≥3 条命令
    case ambient(AGWorkState)                              // thinking/searching/idle/completed

    var icon: String {
        switch self {
        case .active(let cat, _): return cat.icon
        case .recent(let cat, _): return cat.icon
        case .burst: return "bolt.fill"
        case .ambient(let state): return state.icon
        }
    }

    var color: Color {
        switch self {
        case .active(let cat, _): return cat.color
        case .recent(let cat, _): return cat.color
        case .burst: return .yellow
        case .ambient(let state): return state.color
        }
    }

    var isPulsing: Bool {
        switch self {
        case .active: return true
        case .ambient(let state): return state.isActive
        default: return false
        }
    }

    var isThinking: Bool {
        if case .ambient(.thinking) = self { return true }
        return false
    }
}

// MARK: - Hook 驱动的 compact 命令展示
struct HookCommandPresentation: Equatable {
    enum Phase: Equatable {
        case active
        case recent
        case burst
    }

    let phase: Phase
    let category: ProcessMonitor.CommandCategory
    let name: String
    let count: Int
    let timestamp: Date
}

// MARK: - 工具调用记录
struct ToolCallRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let toolName: String
    let icon: String
    let color: Color
    let status: String
    let output: String?

    init(from command: ProcessMonitor.CommandInfo) {
        self.timestamp = Date()
        self.toolName = command.displayName
        self.icon = command.category.icon
        self.color = command.category.color
        self.status = "completed"
        self.output = nil
    }

    init(timestamp: Date, toolName: String, icon: String = "wrench.fill", color: Color = .purple, status: String, output: String?) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.icon = icon
        self.color = color
        self.status = status
        self.output = output
    }
}
