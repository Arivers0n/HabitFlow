import SwiftUI

/// Мягкая подсказка по здоровью на экране «Сегодня». Показывается только когда есть данные и есть что сказать.
struct HealthTipCard: View {
    @State private var health = HealthService.shared
    @State private var hidden: Set<String> = HealthTipCard.loadHidden()

    private static var key: String {
        let c = Calendar.habitFlow.dateComponents([.year, .month, .day], from: .now)
        return "hf.tips.hidden.\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private static func loadHidden() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    var body: some View {
        let tips = health.tips().filter { !hidden.contains($0.id) }
        if let tip = tips.first {
            let accent = tint(for: tip)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tip.symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(tip.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if tip.waterBoostML > 0 {
                        Text("Сегодня стоит выпить на \(tip.waterBoostML) мл больше")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(Motion.smooth) { hidden.insert(tip.id) }
                    UserDefaults.standard.set(Array(hidden), forKey: Self.key)
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Скрыть подсказку")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 12)
            .card(radius: 24, tint: accent)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func tint(for tip: HealthTip) -> Color {
        switch tip.kind {
        case .sleepDeficit, .lateBedtime: Color(hex: "7B6BFF")
        case .hydrate: Color(hex: "5AC8FA")
        case .lowActivity: Color(hex: "FF9F0A")
        case .goodSleep: Palette.success
        }
    }
}
