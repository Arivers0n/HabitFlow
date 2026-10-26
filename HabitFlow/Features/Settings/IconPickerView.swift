import SwiftUI
import SwiftData

/// Выбор иконки приложения. Часть иконок открывается за длинные серии.
struct IconPickerView: View {
    @Environment(HabitStore.self) private var store
    @Query private var habits: [Habit]
    @State private var current = AppIcons.currentID
    @State private var error: String?

    var body: some View {
        let best = store.bestDaysOverall(habits)
        let accent = Appearance.shared.accent
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
                    ForEach(AppIcons.all) { icon in
                        let open = best >= icon.requiredDays
                        Button { choose(icon, open: open, best: best) } label: {
                            VStack(spacing: 8) {
                                Image(icon.preview)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .saturation(open ? 1 : 0)
                                    .opacity(open ? 1 : 0.5)
                                    .overlay {
                                        if !open {
                                            VStack(spacing: 4) {
                                                Image(systemName: "lock.fill").font(.title3)
                                                Text("\(icon.requiredDays) д").font(.caption.weight(.bold))
                                            }
                                            .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                                            .strokeBorder(accent, lineWidth: current == icon.id ? 3 : 0)
                                            .padding(-5)
                                    )
                                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                                Text(icon.title)
                                    .font(.footnote.weight(current == icon.id ? .semibold : .regular))
                                    .foregroundStyle(open ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Palette.danger)
                }
                Text("Бронза, Серебро, Золото и Алмаз открываются, когда любая привычка набирает серию 7, 30, 100 и 365 дней. iOS покажет короткое уведомление о смене иконки — это нормально.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(AppBackground())
        .navigationTitle("Иконка приложения")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ icon: AppIconOption, open: Bool, best: Int) {
        guard open else {
            error = "Откроется после серии \(pluralDays(icon.requiredDays)). Сейчас лучшая — \(pluralDays(best))."
            Haptics.warning()
            return
        }
        AppIcons.set(icon) { e in
            if let e { error = "Не получилось сменить иконку: \(e)" }
            else {
                current = icon.id
                error = nil
                Haptics.success()
            }
        }
    }
}
