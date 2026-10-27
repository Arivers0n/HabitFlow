import SwiftUI

/// Небольшая плашка внизу экрана: «Включить тихий дождь?» после привычки на сон или концентрацию.
struct RelaxOfferBanner: View {
    let offer: RelaxOffer
    var onAccept: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        let accent = Appearance.shared.accent
        HStack(spacing: 12) {
            Image(systemName: offer.scene.symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 36)
            Text(offer.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onAccept) {
                Text("Включить")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(accent.gradient))
            }
            .buttonStyle(PressableStyle())
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("Не сейчас")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .card(radius: 22, tint: accent)
        .padding(.horizontal, 16)
    }
}

/// Окно релакс-музыки: сцены, таймер сна, громкость.
struct RelaxSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RelaxPanel()
                } footer: {
                    Text("Музыка играет вместе с другими приложениями и мягко затихает по таймеру.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Релакс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Разбор недели в отдельном окне — открывается из уведомления.
struct WeeklyReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let habits: [Habit]

    var body: some View {
        NavigationStack {
            ScrollView {
                WeeklyReviewCard(habits: habits)
                    .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Итоги")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
