import AppKit

// MARK: - 应用入口
// 手动初始化 NSApplication，不使用 @main 以获得完全控制

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 隐藏 Dock 图标
app.setActivationPolicy(.accessory)

// 启动事件循环
app.run()
