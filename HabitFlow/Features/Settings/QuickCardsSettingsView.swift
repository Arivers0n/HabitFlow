import SwiftUI
import SwiftData

/// Время и вид уведомления с быстрыми карточками, недельный разбор.
struct QuickCardsSettingsView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @State private var service = QuickCardsService.shared

    private func timeBinding() -> Binding<Date> {
        Binding(
            get: {
                Calendar.habitFlow.date(bySettingHour: service.settings.minutes / 60, minute: service.settings.minutes % 60,
                                        second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.habitFlow.dateComponents([.hour, .minute], from: date)
                service.settings.minutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        let suggestion = service.suggestion(habits)
        Form {
            Section {
                Toggle("Присылать карточки", isOn: $service.settings.enabled)
            } footer: {
                Text("Раз в день придёт уведомление. Откройте его, и напарник задаст несколько быстрых вопросов: сделано ли, сколько, была ли тяга, как настроение.")
            }

            if service.settings.enabled {
                Section("Время") {
                    Toggle("Подобрать по моему режиму", isOn: $service.settings.auto)
                    if service.settings.auto {
                        LabeledContent("Уведомление", value: HealthAdvice.clock(suggestion.minutes))
                    } else {
                        DatePicker("Уведомление", selection: timeBinding(), displayedComponents: .hourAndMinute)
                    }
                    Text(hint(suggestion))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Разбор недели по воскресеньям", isOn: $service.settings.weeklyReviewOn)
            } footer: {
                Text("В воскресенье в 19:00 придёт сводка: что получилось, где просадка и что попробовать на следующей неделе.")
            }

            Section {
                Button {
                    AppRouter.shared.showCards = true
                } label: {
                    Label("Открыть карточки сейчас", systemImage: "rectangle.stack.fill")
                }
            }
        }
        .navigationTitle("Быстрые карточки")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: service.settings) { _, _ in
            Task { await service.reschedule(habits: habits) }
        }
    }

    private func hint(_ s: NotificationTimeSuggestion) -> String {
        if !service.settings.auto { return "Время можно поменять в любой момент." }
        if s.personalized {
            return "Обычно вы заканчиваете отмечать дела около \(HealthAdvice.clock(s.minutes + 30)), поэтому напоминание придёт чуть раньше. Расчёт по \(pluralDays(s.samples))."
        }
        return "Пока мало отметок для расчёта (нужно 5 дней), поэтому берём 20:00. Время уточнится само."
    }
}
