import SwiftUI

// 自定义图标与 SF Symbols 共用入口，供紧凑态、标题和历史记录使用。
struct CommandIcon: View {
    let icon: String
    let color: Color
    let size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            if icon == "clawd" {
                ClawdIcon(color: color, pixelSize: (size + 3) / 16)
            } else {
                Image(systemName: icon)
                    .font(.system(size: size, weight: weight))
                    .foregroundColor(color)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Clawd 像素机器人图标（精确还原 clawd-on-desk 菜单栏图标）
struct ClawdIcon: View {
    var color: Color = .orange
    var pixelSize: CGFloat = 1.0

    // 从 tray-iconTemplate@2x.png 逐像素提取，14×10 有效像素
    private let pixels: [[Int]] = [
        [0,0,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,1,1,0,1,1,1,1,0,1,1,0,0],
        [0,0,1,1,0,1,1,1,1,0,1,1,0,0],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [0,0,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,0,1,0,1,0,0,1,0,1,0,0,0],
        [0,0,0,1,0,1,0,0,1,0,1,0,0,0],
    ]

    var body: some View {
        Canvas { context, size in
            let px = pixelSize
            let cols = 14
            let rows = 10
            let totalW = CGFloat(cols) * px
            let totalH = CGFloat(rows) * px
            let offsetX = (size.width - totalW) / 2
            let offsetY = (size.height - totalH) / 2

            for (row, line) in pixels.enumerated() {
                for (col, value) in line.enumerated() {
                    if value == 1 {
                        let rect = CGRect(
                            x: offsetX + CGFloat(col) * px,
                            y: offsetY + CGFloat(row) * px,
                            width: px,
                            height: px
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: 14 * pixelSize + 2, height: 10 * pixelSize + 2)
    }
}
