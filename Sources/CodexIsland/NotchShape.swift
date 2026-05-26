import SwiftUI

// MARK: - 刘海形状
// 模拟 MacBook 刘海的圆角矩形，支持三态动画
struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // 上半部分是直角（连接屏幕顶部），下半部分是圆角
        var path = Path()
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)

        // 从左上角开始（直角）
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // 顶边
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // 右边到底部圆角
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        // 右下圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cr, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // 底边
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        // 左下圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cr),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // 回到左上角
        path.closeSubpath()

        return path
    }
}

// MARK: - 脉冲动画指示器
struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.3 : 0.8)
            .opacity(isPulsing ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - 思考动画（三个跳动的点）
struct ThinkingDotsView: View {
    @State private var dotOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .offset(y: dotOffsets[index])
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotOffsets[i] = -4
            }
        }
    }
}
