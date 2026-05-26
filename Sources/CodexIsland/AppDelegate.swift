import AppKit
import SwiftUI

// MARK: - 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var statusManager: StatusManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 创建状态管理器
        let manager = StatusManager()
        self.statusManager = manager

        // 先创建窗口获取刘海尺寸
        let tempView = NSView()
        let window = NotchWindow(contentView: tempView)

        // 用实际刘海尺寸创建 SwiftUI 视图
        let contentView = NotchContentView(
            statusManager: manager,
            notchWidth: window.notchWidth,
            notchHeight: window.notchHeight
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        // 替换窗口的内容视图
        window.contentView = hostingView
        window.orderFrontRegardless()
        self.notchWindow = window

        print("[Codex Island] 应用启动完成")
        print("[Codex Island] 刘海尺寸: \(window.notchWidth) × \(window.notchHeight)")
    }
}
