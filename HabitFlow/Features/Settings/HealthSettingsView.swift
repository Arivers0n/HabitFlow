import SwiftUI

/// Здоровье: сон, шаги и тренировки для мягких подсказок. Данные не покидают устройство.
struct HealthSettingsView: View {
    @State private var health = HealthService.shared
    @State private var connecting = false
    @State private var manualHours = 7.0
    @State private var hasManual = false

    private func bedtimeBinding() -> Binding<Date> {
        Binding(
            get: {
                let m = health.bedtimeMinutes
                return Calendar.habitFlow.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.habitFlow.dateComponents([.hour, .minute], from: date)
                health.bedtimeMinutes = (c.hour ?? 23) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        Form {
            Section {
                statusRow
                switch health.status {
                case .off:
                    Button {
                        connecting = true
                        Task { await health.connect(); connecting = false }
                    } label: {
                        Label(connecting ? "Подключаем…" : "Подключить Здоровье", systemImage: "heart.fill")
                    }
                    .disabled(connecting)
                case .on:
                    Button("Отключить", role: .destructive) { health.disconnect() }
                case .unavailable:
                    EmptyView()
                }
            } footer: {
                Text(footer)
            }

            if health.status == .unavailable || health.status == .off {
                Section {
                    Toggle("Я сегодня спал(а)", isOn: $hasManual)
                    if hasManual {
                        Stepper(value: $manualHours, in: 1...14, step: 0.5) {
                            Text("\(HealthAdvice.hm(manualHours * 3_600))")
                        }
                    }
                } header: {
                    Text("Ввести сон вручную")
                } footer: {
                    Text("Запасной путь, если Здоровье недоступно. Значение действует только сегодня.")
                }
            }

            Section("Режим сна") {
                DatePicker("Во сколько ложиться", selection: bedtimeBinding(), displayedComponents: .hourAndMinute)
                Stepper(value: Binding(get: { health.sleepNeedMinutes }, set: { health.sleepNeedMinutes = $0 }),
                        in: 360...600, step: 15) {
                    Text("Нужно сна: \(HealthAdvice.hm(Double(health.sleepNeedMinutes) * 60))")
                }
            }

            let tips = health.tips()
            if !tips.isEmpty {
                Section("Сейчас") {
                    ForEach(tips) { tip in
                        Label(tip.text, systemImage: tip.symbol)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Здоровье")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let h = health.manualSleepHours { manualHours = h; hasManual = true }
            await health.refresh()
        }
        .onChange(of: hasManual) { _, on in health.setManualSleep(hours: on ? manualHours : nil) }
        .onChange(of: manualHours) { _, v in if hasManual { health.setManualSleep(hours: v) } }
    }

    private var statusRow: some View {
        HStack {
            Text("Статус")
            Spacer()
            switch health.status {
            case .on: Text("Подключено").foregroundStyle(Palette.success)
            case .off: Text("Не подключено").foregroundStyle(.secondary)
            case .unavailable: Text("Недоступно").foregroundStyle(Palette.danger)
            }
        }
    }

    private var footer: String {
        switch health.status {
        case .unavailable:
            return "В этой установке приложению не выдано право на Здоровье — так бывает при установке через сторонние подписи. Напарник не получит сон и тренировки, но сон можно ввести вручную. Системные будильники и экранное время приложениям недоступны."
        case .on:
            return "Напарник читает сон, шаги, активные калории и тренировки. Ничего не записывается в Здоровье и не отправляется на сервер."
        case .off:
            return "Сон меньше нормы — предложим лечь пораньше. Интенсивная тренировка — напомним про воду."
        }
    }
}
