import AppKit
import SwiftUI

// MARK: - 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var statusItem: NSStatusItem?
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

        // 创建菜单栏图标
        setupMenuBar()

        print("[Codex Island] 应用启动完成")
        print("[Codex Island] 刘海尺寸: \(window.notchWidth) × \(window.notchHeight)")
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // 优先使用 island.fill 图标，不可用时降级
            if let img = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Codex Island") {
                button.image = img
            }
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Codex Island v0.1", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "显示/隐藏灵动岛", action: #selector(toggleNotch), keyEquivalent: "d")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Codex Island", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleNotch() {
        if notchWindow?.isVisible == true {
            notchWindow?.orderOut(nil)
        } else {
            notchWindow?.orderFrontRegardless()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
