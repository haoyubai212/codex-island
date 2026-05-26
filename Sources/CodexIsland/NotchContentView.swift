import AppKit
import SwiftUI

// 状态变化通知名
extension Notification.Name {
    static let notchDisplayStateChanged = Notification.Name("notchDisplayStateChanged")
}

// MARK: - 灵动岛主视图
struct NotchContentView: View {
    @ObservedObject var statusManager: StatusManager
    @State private var displayState: NotchDisplayState = .closed
    @State private var isHovering = false
    @State private var showIslandControls = false
    @State private var isAutoStartEnabled = CodexIslandControls.isAutoStartEnabled()
    @State private var suppressNextContainerTap = false
    // 用于取消延迟自动关闭的 WorkItem
    @State private var pendingAutoClose: DispatchWorkItem?

    // 刘海尺寸（从 NotchWindow 检测的实际值）
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init(statusManager: StatusManager, notchWidth: CGFloat = 179, notchHeight: CGFloat = 32) {
        self.statusManager = statusManager
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    var body: some View {
        VStack {
            // 内容区域贴顶
            ZStack(alignment: .top) {
                // 背景形状（闭合态不显示）
                if displayState != .closed {
                    NotchShape(cornerRadius: currentCornerRadius)
                        .fill(.black)
                        .shadow(color: shadowColor, radius: shadowRadius)
                }

                // 内容（闭合态不显示）
                if displayState != .closed {
                    contentForState
                        .clipped()
                }
            }
            .frame(width: currentWidth, height: currentHeight)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: displayState)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showIslandControls)
            .opacity(displayState == .closed ? 0 : 1)
            .animation(.easeOut(duration: 0.5), value: displayState == .closed)

            Spacer() // 把内容推到顶部
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { hovering in
            isHovering = hovering
            handleHoverChange(hovering)
        }
        .onTapGesture {
            handleTap()
        }
        .onChange(of: statusManager.compactPresentation) { _, newPres in
            handlePresentationChange(newPres)
        }
        .onChange(of: displayState) { _, newState in
            // 通知 NotchWindow 动态调整窗口尺寸
            NotificationCenter.default.post(
                name: .notchDisplayStateChanged,
                object: nil,
                userInfo: ["state": newState]
            )
        }
    }

    // MARK: - 每个状态的内容视图

    @ViewBuilder
    private var contentForState: some View {
        switch displayState {
        case .closed:
            EmptyView() // 闭合态：完全不显示
        case .compact:
            compactContent
        case .expanded:
            expandedContent
        }
    }

    // 紧凑态：只左右展开，内容在刘海两侧探出
    // 模拟 iPhone 灵动岛紧凑模式
    private var compactContent: some View {
        HStack(spacing: 0) {
            // 左侧：图标
            HStack(spacing: 6) {
                compactLeftIcon
            }
            .frame(width: 50, alignment: .center)

            // 中间留空（刘海区域）
            Spacer()
                .frame(width: notchWidth)

            // 右侧：文字/动画
            HStack(spacing: 6) {
                compactRightContent
            }
            .frame(width: 50, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 左侧图标 — 只读 compactPresentation
    @ViewBuilder
    private var compactLeftIcon: some View {
        let pres = statusManager.compactPresentation

        switch pres {
        case .active(let cat, _):
            Image(systemName: cat.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(cat.color)
            PulsingDot(color: cat.color)

        case .recent(let cat, _):
            Image(systemName: cat.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(cat.color)
                .transition(.scale.combined(with: .opacity))

        case .burst:
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.yellow)

        case .ambient(let state):
            switch state {
            case .thinking:
                CodexLogoIcon(size: 14)
                PulsingDot(color: codexAccentColor)
            default:
                Image(systemName: state.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.color)
                if state.isActive {
                    PulsingDot(color: state.color)
                }
            }
        }
    }

    // 右侧内容 — 只读 compactPresentation
    @ViewBuilder
    private var compactRightContent: some View {
        let pres = statusManager.compactPresentation

        switch pres {
        case .active(_, let name):
            Text(String(name.prefix(12)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)

        case .recent(_, let name):
            Text(String(name.prefix(12)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .transition(.opacity)

        case .burst(let count, _):
            Text("×\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.yellow)

        case .ambient(let state):
            if case .thinking = state {
                ThinkingDotsView()
            } else if state.isActive {
                Text(statusManager.elapsedTimeString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Circle()
                    .fill(.gray.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // 完全展开态：详细状态面板
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // 顶部摘要行
            HStack(spacing: 8) {
                expandedHeaderIcon

                Text(statusManager.workState.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                if statusManager.workState.isActive {
                    Text(statusManager.elapsedTimeString)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, notchHeight + 6)

            // 分隔线
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // 工具调用历史
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if statusManager.recentToolCalls.isEmpty {
                        Text("暂无活动记录")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    } else {
                        ForEach(statusManager.recentToolCalls) { record in
                            ToolCallRow(record: record)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            .frame(maxHeight: 140)

            // 底部信息栏
            HStack {
                Circle()
                    .fill(footerDotColor)
                    .frame(width: 6, height: 6)
                Text(footerStatusText)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Spacer()
                CodexBadge {
                    suppressNextContainerTap = true
                    pendingAutoClose?.cancel()
                    pendingAutoClose = nil
                    isAutoStartEnabled = CodexIslandControls.isAutoStartEnabled()
                    showIslandControls.toggle()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .padding(.top, 4)

            if showIslandControls {
                islandControls
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var islandControls: some View {
        HStack(spacing: 10) {
            Button {
                suppressNextContainerTap = true
                CodexIslandControls.quit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .semibold))
                    Text("退出")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.76))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.08)))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Spacer()

            Toggle(isOn: Binding(
                get: { isAutoStartEnabled },
                set: { enabled in
                    suppressNextContainerTap = true
                    isAutoStartEnabled = enabled
                    CodexIslandControls.setAutoStartEnabled(enabled)
                    isAutoStartEnabled = CodexIslandControls.isAutoStartEnabled()
                }
            )) {
                Text("开机自起")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(codexAccentColor)
            .pointingHandCursor()
        }
        .onAppear {
            isAutoStartEnabled = CodexIslandControls.isAutoStartEnabled()
        }
    }

    @ViewBuilder
    private var expandedHeaderIcon: some View {
        if case .thinking = statusManager.workState {
            CodexLogoIcon(size: 16)
        } else {
            Image(systemName: statusManager.workState.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(statusManager.workState.color)
        }
    }

    private var footerDotColor: Color {
        if case .thinking = statusManager.workState {
            return codexAccentColor
        }
        if statusManager.workState.isActive {
            return statusManager.workState.color
        }
        return statusManager.activeCommandCount > 0 ? .green : .gray
    }

    private var footerStatusText: String {
        if statusManager.activeConversationCount > 0 {
            return "\(statusManager.activeConversationCount) 个活跃对话"
        }
        if case .completed = statusManager.workState {
            return "本轮已完成"
        }
        if case .idle = statusManager.workState {
            return "无活跃对话"
        }
        return statusManager.activeCommandCount > 0
            ? "\(statusManager.activeCommandCount) 个运行命令"
            : "监听 Codex 命令"
    }

    private var codexAccentColor: Color {
        Color(red: 0.43, green: 0.48, blue: 1.0)
    }

    // MARK: - 尺寸计算

    private var currentWidth: CGFloat {
        switch displayState {
        case .closed: return notchWidth // 与刘海同宽
        case .compact: return notchWidth + 110 // 左右各探出约55px
        case .expanded: return notchWidth + 110 // 与紧凑态同宽，只向下展开
        }
    }

    private var currentHeight: CGFloat {
        switch displayState {
        case .closed: return notchHeight // 与刘海同高
        case .compact: return notchHeight // 紧凑态不向下展开，与刘海齐平
        case .expanded: return notchHeight + (showIslandControls ? 236 : 220)
        }
    }

    private var currentCornerRadius: CGFloat {
        switch displayState {
        case .closed: return 12
        case .compact: return 16
        case .expanded: return 20
        }
    }

    private var shadowColor: Color {
        if !statusManager.workState.isActive { return .clear }
        // compact 模式减弱光晕，避免溢出
        let opacity: Double = displayState == .expanded ? 0.3 : 0.15
        return workStateDisplayColor.opacity(opacity)
    }

    private var shadowRadius: CGFloat {
        if !statusManager.workState.isActive { return 0 }
        return displayState == .expanded ? 12 : 6
    }

    private var workStateDisplayColor: Color {
        if case .thinking = statusManager.workState {
            return codexAccentColor
        }
        return statusManager.workState.color
    }

    // MARK: - 交互逻辑

    private func handleHoverChange(_ hovering: Bool) {
        if hovering && displayState == .closed {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                displayState = .compact
            }
        } else if !hovering && displayState == .compact {
            // 鼠标移开 compact 时：如果 AI 正在工作则保持显示
            if statusManager.workState.isActive {
                // 工作中 → 不关闭
            } else {
                scheduleAutoClose(after: 0.5)
            }
        } else if !hovering && displayState == .expanded {
            // 鼠标移开展开态 → 先收回到紧凑态
            scheduleAutoCollapse(after: 1.0)
        }
    }

    private func handleTap() {
        if suppressNextContainerTap {
            suppressNextContainerTap = false
            return
        }

        // 用户主动交互 → 取消任何自动关闭/收起
        pendingAutoClose?.cancel()
        pendingAutoClose = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            switch displayState {
            case .closed:
                displayState = .compact
            case .compact:
                displayState = .expanded
            case .expanded:
                // 展开态点击 → 丝滑收回到紧凑态（而非直接关闭）
                displayState = .compact
                showIslandControls = false
            }
        }
    }

    private func handlePresentationChange(_ newPres: CompactPresentation) {
        switch newPres {
        case .active, .burst, .recent:
            // 有活跃内容 → 弹出 compact
            if displayState == .closed {
                pendingAutoClose?.cancel()
                pendingAutoClose = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    displayState = .compact
                }
            }

        case .ambient(let state):
            switch state {
            case .thinking, .searching, .executing:
                // 工作中 → 弹出 compact
                if displayState == .closed {
                    pendingAutoClose?.cancel()
                    pendingAutoClose = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        displayState = .compact
                    }
                }

            case .completed:
                // 完成 → 短暂显示后收回
                if displayState == .closed {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        displayState = .compact
                    }
                }
                scheduleAutoClose(after: 2.0)

            case .idle:
                // 空闲 → compact 且无 hover 时收回
                if displayState == .compact && !isHovering {
                    scheduleAutoClose(after: 1.0)
                }

            case .error:
                // 错误 → 显示
                if displayState == .closed {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        displayState = .compact
                    }
                }
            }
        }
    }

    // 可取消的延迟关闭（compact → closed）
    private func scheduleAutoClose(after seconds: Double) {
        pendingAutoClose?.cancel()

        let closeItem = DispatchWorkItem { [self] in
            // 只在非工作状态、非悬停、compact 时关闭
            if !isHovering && displayState == .compact && !statusManager.workState.isActive {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                    displayState = .closed
                }
            }
        }
        pendingAutoClose = closeItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: closeItem)
    }

    // 可取消的延迟收起（expanded → compact → closed）
    private func scheduleAutoCollapse(after seconds: Double) {
        pendingAutoClose?.cancel()

        let collapseItem = DispatchWorkItem { [self] in
            if !isHovering && displayState == .expanded {
                // 先丝滑收回到紧凑态
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    displayState = .compact
                    showIslandControls = false
                }
                // 再延迟关闭
                scheduleAutoClose(after: 0.8)
            }
        }
        pendingAutoClose = collapseItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: collapseItem)
    }
}

// MARK: - 应用标识
struct CodexBadge: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                CodexLogoIcon(size: 11)
                Text("Codex")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.72))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Codex logo（透明背景）
struct CodexLogoIcon: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            CodexCloudShape()
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.48, blue: 1.0),
                            Color(red: 0.40, green: 0.43, blue: 1.0),
                            Color(red: 0.18, green: 0.28, blue: 1.0),
                            Color(red: 0.38, green: 0.76, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    CodexCloudShape()
                        .stroke(.white.opacity(0.23), lineWidth: max(0.45, size * 0.045))
                        .blur(radius: size * 0.015)
                        .padding(size * 0.025)
                }
                .shadow(color: Color(red: 0.22, green: 0.24, blue: 1.0).opacity(0.35), radius: size * 0.10, x: 0, y: size * 0.05)

            Image(systemName: "chevron.right")
                .font(.system(size: size * 0.48, weight: .heavy))
                .foregroundColor(.white.opacity(0.95))
                .offset(x: -size * 0.18, y: size * 0.01)

            Capsule()
                .fill(.white.opacity(0.95))
                .frame(width: size * 0.24, height: max(1.4, size * 0.075))
                .offset(x: size * 0.22, y: size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

struct CodexCloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y
            )
        }

        var path = Path()
        path.move(to: point(0.48, 0.05))
        path.addCurve(to: point(0.78, 0.18), control1: point(0.59, -0.01), control2: point(0.73, 0.04))
        path.addCurve(to: point(0.97, 0.38), control1: point(0.91, 0.14), control2: point(1.00, 0.25))
        path.addCurve(to: point(0.86, 0.65), control1: point(1.06, 0.49), control2: point(1.00, 0.65))
        path.addCurve(to: point(0.63, 0.94), control1: point(0.87, 0.81), control2: point(0.77, 0.94))
        path.addCurve(to: point(0.39, 0.89), control1: point(0.54, 1.00), control2: point(0.44, 0.98))
        path.addCurve(to: point(0.16, 0.75), control1: point(0.29, 0.93), control2: point(0.17, 0.88))
        path.addCurve(to: point(0.06, 0.48), control1: point(0.03, 0.70), control2: point(-0.01, 0.55))
        path.addCurve(to: point(0.19, 0.23), control1: point(0.02, 0.34), control2: point(0.07, 0.24))
        path.addCurve(to: point(0.48, 0.05), control1: point(0.23, 0.09), control2: point(0.36, 0.03))
        path.closeSubpath()
        return path
    }
}

// MARK: - 工具调用记录行
struct ToolCallRow: View {
    let record: ToolCallRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record.icon)
                .font(.system(size: 8))
                .foregroundColor(record.color)
                .frame(width: 12)

            Text(record.toolName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)

            Spacer()

            Text(timeAgo)
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(record.timestamp)
        if interval < 60 { return "\(Int(interval))s前" }
        return "\(Int(interval / 60))m前"
    }
}
