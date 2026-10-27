import SwiftUI

/// Звуки интерфейса и питомца, тихий режим и релакс-музыка.
struct SoundSettingsView: View {
    @State private var sound = SoundService.shared

    private func minutesBinding(_ keyPath: WritableKeyPath<SoundSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = sound.settings[keyPath: keyPath]
                return Calendar.habitFlow.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.habitFlow.dateComponents([.hour, .minute], from: date)
                sound.settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Звуки", isOn: $sound.settings.master)
                if sound.settings.master {
                    ForEach(SoundCategory.allCases, id: \.self) { c in
                        Toggle(c.title, isOn: categoryBinding(c))
                    }
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $sound.settings.volume, in: 0...1) { editing in
                            if !editing { SoundService.shared.play(.tap) }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Громкость")
                }
            } footer: {
                Text("Короткие звуки не перебивают музыку и подкасты других приложений.")
            }

            if sound.settings.master {
                Section {
                    Toggle("Тихий режим", isOn: $sound.settings.quietMode)
                    if sound.settings.quietMode {
                        DatePicker("С", selection: minutesBinding(\.quietFromMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("До", selection: minutesBinding(\.quietToMinutes), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("В это время звуки интерфейса и питомца молчат. Релакс-музыку это не касается.")
                }

                Section("Послушать") {
                    ForEach([SoundEvent.done, .petHappy, .levelUp], id: \.self) { e in
                        Button { SoundService.shared.play(e) } label: {
                            Label(title(e), systemImage: "play.circle")
                        }
                    }
                }
            }

            Section("Релакс-музыка") {
                RelaxPanel()
            }
        }
        .navigationTitle("Звуки")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryBinding(_ c: SoundCategory) -> Binding<Bool> {
        Binding(
            get: { sound.settings.isOn(c) },
            set: { on in
                switch c {
                case .interface: sound.settings.interface = on
                case .pet: sound.settings.pet = on
                case .rewards: sound.settings.rewards = on
                }
            })
    }

    private func title(_ e: SoundEvent) -> String {
        switch e {
        case .done: "Отметка"
        case .petHappy: "Радость питомца"
        case .levelUp: "Новый уровень"
        default: e.rawValue
        }
    }
}

/// Выбор сцены, таймер сна и кнопка «играть». Используется в настройках и в окне предложения.
struct RelaxPanel: View {
    @State private var sound = SoundService.shared
    @State private var timer = 30

    private let timers = [0, 15, 30, 60]

    var body: some View {
        let accent = Appearance.shared.accent
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(AmbientScene.allCases) { scene in
                    sceneButton(scene, accent: accent)
                }
            }
            HStack {
                Text("Таймер сна")
                Spacer()
                Picker("Таймер сна", selection: $timer) {
                    ForEach(timers, id: \.self) { t in
                        Text(t == 0 ? "Без таймера" : "\(t) мин").tag(t)
                    }
                }
                .pickerStyle(.menu)
            }
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $sound.relaxVolume, in: 0.05...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Громкость музыки")
            if let end = sound.sleepTimerEnd {
                Text("Затихнет в \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sceneButton(_ scene: AmbientScene, accent: Color) -> some View {
        let playing = sound.relaxScene == scene
        return Button {
            if playing { sound.stopRelax() } else { sound.startRelax(scene, timerMinutes: timer == 0 ? nil : timer) }
            Haptics.selection()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: playing ? "pause.circle.fill" : scene.symbol)
                    .font(.title2)
                Text(scene.title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(playing ? .white : accent)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(playing ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.12)))
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(playing ? "\(scene.title): остановить" : "\(scene.title): включить")
    }
}
