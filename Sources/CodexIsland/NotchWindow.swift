import AppKit
import SwiftUI

// MARK: - 刘海浮窗
// 创建一个透明、无边框、置顶的 NSPanel，覆盖在刘海区域
class NotchWindow: NSPanel {

    // 刘海几何信息
    private(set) var notchRect: NSRect = .zero
    private(set) var notchWidth: CGFloat = 179
    private(set) var notchHeight: CGFloat = 32

    // 当前显示状态，用于动态调整窗口尺寸
    private var currentDisplayState: NotchDisplayState = .closed

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 窗口配置
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // 使用 statusBar 层级，足以在菜单栏上方但不会压住系统 UI
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false

        // 检测刘海
        detectNotch()

        // 设置内容视图
        self.contentView = contentView

        // 定位到刘海区域（闭合态）
        updateWindowFrame(for: .closed)

        // 监听屏幕变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 监听灵动岛状态变化，动态调整窗口 frame
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayStateChanged(_:)),
            name: .notchDisplayStateChanged,
            object: nil
        )
    }

    // MARK: - 检测刘海区域

    private func detectNotch() {
        // 优先查找有刘海的内建屏幕
        let targetScreen = findNotchScreen() ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            // 有刘海的 MacBook
            let x = leftArea.maxX
            let width = rightArea.minX - leftArea.maxX
            let y = screen.frame.maxY - screen.safeAreaInsets.top
            let height = screen.safeAreaInsets.top

            notchRect = NSRect(x: x, y: y, width: width, height: height)
            notchWidth = width
            notchHeight = height
            print("[NotchWindow] 检测到刘海: \(notchRect)")
        } else {
            // 无刘海屏幕：在顶部中央模拟
            let screenFrame = screen.frame
            let width: CGFloat = 179
            let height: CGFloat = 32
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - height

            notchRect = NSRect(x: x, y: y, width: width, height: height)
            notchWidth = width
            notchHeight = height
            print("[NotchWindow] 无刘海屏幕，模拟位置: \(notchRect)")
        }
    }

    // 查找带刘海的屏幕（多显示器支持）
    private func findNotchScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil {
                return screen
            }
        }
        return nil
    }

    // MARK: - 动态调整窗口尺寸（内容尺寸 + hover 余量）

    func updateWindowFrame(for state: NotchDisplayState) {
        // 使用刘海所在屏幕
        let targetScreen = findNotchScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }
        currentDisplayState = state

        let notchCenterX = notchRect.midX

        // 窗口尺寸 = NotchContentView 内容尺寸 + 4px hover 余量
        // 余量确保鼠标靠近边缘时仍能触发 onHover
        let windowWidth: CGFloat
        let windowHeight: CGFloat

        switch state {
        case .closed:
            // 完全透明，仅保留 hover 探测
            windowWidth = notchWidth + 4
            windowHeight = notchHeight + 4
        case .compact:
            // 只左右展开，不向下
            windowWidth = notchWidth + 114
            windowHeight = notchHeight + 4
        case .expanded:
            // 与紧凑态同宽，只向下展开
            windowWidth = notchWidth + 114
            windowHeight = notchHeight + 224
        }

        let windowX = notchCenterX - windowWidth / 2
        let windowY = screen.frame.maxY - windowHeight

        let windowFrame = NSRect(
            x: windowX,
            y: windowY,
            width: windowWidth,
            height: windowHeight
        )

        // 使用动画调整窗口尺寸
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(windowFrame, display: true)
        }
    }

    @objc private func screenConfigChanged() {
        detectNotch()
        updateWindowFrame(for: currentDisplayState)
    }

    @objc private func displayStateChanged(_ notification: Notification) {
        if let state = notification.userInfo?["state"] as? NotchDisplayState {
            updateWindowFrame(for: state)
        }
    }

    // 允许窗口接收鼠标事件（hover 检测需要）
    override var canBecomeKey: Bool { true }

    // 保持窗口可见
    override func resignKey() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
