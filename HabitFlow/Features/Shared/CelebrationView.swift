import SwiftUI

/// Поздравление с наградой: медаль, конфетти, двойная вибрация.
struct CelebrationView: View {
    let celebration: HabitStore.Celebration
    var onClose: () -> Void

    @State private var appear = false

    var body: some View {
        let color = Color(hex: celebration.colorHex)
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            if Motion.enabled {
                Confetti(colors: [color, .white, Color(hex: "FFD60A"), Appearance.shared.accent])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.35))
                        .frame(width: 150, height: 150)
                        .blur(radius: 30)
                    Circle()
                        .fill(color.gradient)
                        .frame(width: 110, height: 110)
                        .shadow(color: color.opacity(0.6), radius: 20)
                    Image(systemName: celebration.milestone.symbol)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: appear)
                }
                .scaleEffect(appear ? 1 : 0.4)
                .rotationEffect(.degrees(appear ? 0 : -25))

                VStack(spacing: 6) {
                    Text("Награда «\(celebration.milestone.title)»")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Отлично", action: onClose)
                    .buttonStyle(PrimaryButtonStyle(color: color))
            }
            .padding(24)
            .frame(maxWidth: 340)
            .card(radius: 32, tint: color)
            .padding(24)
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(Motion.bouncy ?? .default) { appear = true }
        }
    }

    private var subtitle: String {
        let days = pluralDays(celebration.milestone.days)
        return celebration.kind == .quit
            ? "«\(celebration.habitName)»: \(days) без срыва."
            : "«\(celebration.habitName)»: серия \(days)."
    }
}

/// Лёгкое конфетти на Canvas: частицы вылетают снизу-вверх и падают под гравитацией.
struct Confetti: View {
    let colors: [Color]
    @State private var start = Date.now
    @State private var particles: [Particle] = (0..<70).map { _ in Particle.random() }

    struct Particle {
        var x: Double, vx: Double, vy: Double, spin: Double, size: Double, colorIndex: Int, delay: Double
        static func random() -> Particle {
            Particle(x: .random(in: 0.2...0.8), vx: .random(in: -0.35...0.35), vy: .random(in: -1.35 ... -0.85),
                     spin: .random(in: -8...8), size: .random(in: 6...11), colorIndex: .random(in: 0...3),
                     delay: .random(in: 0...0.25))
        }
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in particles {
                    let tt = t - p.delay
                    guard tt > 0, tt < 3.2 else { continue }
                    let x = (p.x + p.vx * tt) * size.width
                    let y = size.height * (1.0 + p.vy * tt + 0.55 * tt * tt)
                    let alpha = max(0, 1 - tt / 3.2)
                    var ctx2 = g
                    ctx2.translateBy(x: x, y: y)
                    ctx2.rotate(by: .radians(p.spin * tt))
                    ctx2.opacity = alpha
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    ctx2.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[p.colorIndex % colors.count]))
                }
            }
        }
    }
}
