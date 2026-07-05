import SwiftUI
import WatchKit

// Токены дизайн-направления 1e «Радиальный / арка» (дизайн-хэндофф).
// px из спеки даны для дисплея Ultra 2 (410×502 @2x) — в коде pt (÷2),
// диаметры кругов — долей ширины экрана, чтобы держать пропорции
// на других корпусах.
enum Theme {
    static let work = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)        // #30D158
    static let rest = Color(red: 255 / 255, green: 138 / 255, blue: 26 / 255)       // #FF8A1A
    static let ringTrack = Color.white.opacity(0.08)
    static let dialInactive = Color.white.opacity(0.22)
    static let bgSetup = Color(red: 8 / 255, green: 8 / 255, blue: 10 / 255)        // #08080a
    static let bgWorkInner = Color(red: 15 / 255, green: 47 / 255, blue: 26 / 255)  // #0f2f1a
    static let bgWorkOuter = Color(red: 5 / 255, green: 8 / 255, blue: 6 / 255)     // #050806
    static let bgRestInner = Color(red: 46 / 255, green: 23 / 255, blue: 3 / 255)   // #2e1703
    static let bgRestOuter = Color(red: 5 / 255, green: 4 / 255, blue: 3 / 255)     // #050403

    static var screenWidth: CGFloat { WKInterfaceDevice.current().screenBounds.width }

    // Геометрия колец из эталона (SVG viewBox 200, r=88, растянут до 330/340px):
    // фактический диаметр окружности = 0.88 × размер SVG, толщина стенки
    // масштабируется вместе с ним (10 и 12 в координатах viewBox)
    static var workRingSide: CGFloat { screenWidth * (330.0 * 0.88 / 410.0) }   // 290px на Ultra 2
    static var restRingSide: CGFloat { screenWidth * (340.0 * 0.88 / 410.0) }   // 299px
    static var workRingWidth: CGFloat { screenWidth * (16.5 / 410.0) }          // 10/200 × 330
    static var restRingWidth: CGFloat { screenWidth * (20.4 / 410.0) }          // 12/200 × 340
    static var setupDialSide: CGFloat { screenWidth * (134.0 / 410.0) }
}

// Кольцо направления: старт сверху (12 часов), скруглённые концы,
// под цветной дугой всегда серая дорожка на весь круг
struct PhaseRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    var glow = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Эталон: drop-shadow blur 6px ≈ sigma 3px = 1.5pt
                .shadow(color: glow ? color.opacity(0.6) : .clear, radius: glow ? 1.5 : 0)
        }
    }
}

// Радиальный фон фазы: центр чуть выше середины (50% 45%), гаснет в AOD.
// Радиус подобран под css-эталон radial-gradient(90% 80% ... 80%)
struct RadialPhaseBackground: View {
    let inner: Color
    let outer: Color
    let dimmed: Bool

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [dimmed ? .black : inner, dimmed ? .black : outer],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: geo.size.height * 0.62
            )
        }
        .ignoresSafeArea()
    }
}
