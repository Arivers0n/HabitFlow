import SwiftUI

/// Темы, акцент, фон, карточки, шрифт и схема — с живым превью сверху.
struct AppearanceSettingsView: View {
    @State private var naming = false
    @State private var presetName = ""

    var body: some View {
        @Bindable var ap = Appearance.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreviewCard()

                // Пресеты
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Темы").font(.headline)
                        Spacer()
                        Button { presetName = ""; naming = true } label: {
                            Label("Сохранить текущую", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemePreset.builtIns + ap.customPresets) { p in
                                PresetTile(preset: p, selected: ap.isCurrent(p))
                                    .onTapGesture {
                                        withAnimation(Motion.smooth) { ap.apply(p) }
                                        Haptics.selection()
                                    }
                                    .contextMenu {
                                        if !p.builtIn {
                                            Button(role: .destructive) {
                                                ap.customPresets.removeAll { $0.id == p.id }
                                            } label: { Label("Удалить тему", systemImage: "trash") }
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Акцент
                group("Акцентный цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        ForEach(Palette.accents, id: \.self) { hex in
                            Button {
                                withAnimation(Motion.smooth) { ap.s.accentHex = hex }
                                Haptics.selection()
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex).gradient)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        if ap.s.accentHex == hex {
                                            Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(PressableStyle(scale: 0.9))
                        }
                    }
                }

                // Фон
                group("Фон") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(BackgroundStyle.allCases) { b in
                            Button {
                                withAnimation(Motion.smooth) { ap.s.background = b }
                                Haptics.selection()
                            } label: {
                                VStack(spacing: 6) {
                                    BackgroundSwatch(style: b)
                                        .frame(height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(ap.s.background == b ? ap.accent : Color.primary.opacity(0.1),
                                                              lineWidth: ap.s.background == b ? 2.5 : 1)
                                        )
                                    Text(b.title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }

                group("Карточки") {
                    Picker("Карточки", selection: $ap.s.cardStyle.animation(Motion.smooth)) {
                        ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                group("Схема") {
                    Picker("Схема", selection: $ap.s.scheme) {
                        ForEach(SchemeChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                group("Шрифт") {
                    VStack(spacing: 8) {
                        ForEach(FontChoice.allCases) { f in
                            Button {
                                withAnimation(Motion.smooth) { ap.s.font = f }
                                Haptics.selection()
                            } label: {
                                HStack {
                                    Text(f.title).font(.body.weight(.medium))
                                    Spacer()
                                    Text("128 дней").font(.system(.headline, design: f.design)).foregroundStyle(.secondary)
                                    Image(systemName: ap.s.font == f ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ap.s.font == f ? ap.accent : Color.secondary)
                                        .font(.title3)
                                }
                                .fontDesign(f.design)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 50)
                                .card(radius: 16)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Темы и цвета")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Название темы", isPresented: $naming) {
            TextField("Моя тема", text: $presetName)
            Button("Сохранить") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                Appearance.shared.saveCurrent(as: name.isEmpty ? "Моя тема" : name)
                Haptics.success()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// Пример карточки, чтобы сразу видеть результат настроек.
private struct PreviewCard: View {
    var body: some View {
        let accent = Appearance.shared.accent
        HStack(spacing: 14) {
            HabitIcon(symbol: "drop.fill", color: Color(hex: "5AC8FA"), size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text("Вода").font(.headline)
                HStack(spacing: 8) {
                    Label("12", systemImage: "flame.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: "5AC8FA"))
                    Text("1 500 / 2 000 мл").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            ZStack {
                ProgressRing(progress: 0.75, color: Color(hex: "5AC8FA"), lineWidth: 5)
                Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: "5AC8FA"))
            }
            .frame(width: 56, height: 56)
        }
        .padding(16)
        .card()
        .background(
            AppBackground()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(-12)
        )
        .padding(12)
        .overlay(alignment: .topTrailing) {
            Circle().fill(accent).frame(width: 12, height: 12).padding(4)
        }
    }
}

private struct PresetTile: View {
    let preset: ThemePreset
    let selected: Bool

    var body: some View {
        let s = preset.settings
        let accent = Color(hex: s.accentHex)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                BackgroundSwatch(style: s.background, accentHex: s.accentHex, light: s.scheme == .light)
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(s.scheme == .light ? 0.9 : 0.2)).frame(width: 34, height: 10)
                }
                .padding(10)
            }
            .frame(width: 104, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
            )
            Text(preset.name).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(width: 104)
        .contentShape(Rectangle())
    }
}

/// Миниатюра фона для выбора.
struct BackgroundSwatch: View {
    let style: BackgroundStyle
    var accentHex: String? = nil
    var light: Bool? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = Color(hex: accentHex ?? Appearance.shared.s.accentHex)
        let isLight = light ?? (scheme == .light)
        ZStack {
            if isLight {
                style == .oled ? Color.white : Color(hex: "EEF1F7")
            } else {
                switch style {
                case .deep: Color(hex: "090B12")
                case .midnight: Color(hex: "0A1030")
                case .aurora: Color(hex: "06070D")
                case .graphite: Color(hex: "1A1B1F")
                case .oled: Color.black
                }
            }
            switch style {
            case .aurora:
                Circle().fill(accent).frame(width: 60).offset(x: -24, y: -18).blur(radius: 18).opacity(0.7)
                Circle().fill(Color(hex: "2ECFC4")).frame(width: 50).offset(x: 26, y: 10).blur(radius: 18).opacity(0.6)
            case .oled:
                EmptyView()
            default:
                Circle().fill(accent).frame(width: 70).offset(x: -30, y: -30).blur(radius: 22).opacity(0.45)
            }
        }
    }
}

// MARK: - Оформление: вкладки «Тема / Иконки / Экран»

struct LookSettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case theme, icons, screen
        var id: String { rawValue }
        var title: String {
            switch self {
            case .theme: "Тема"
            case .icons: "Иконки"
            case .screen: "Экран"
            }
        }
    }

    @State var tab: Tab

    var body: some View {
        Group {
            switch tab {
            case .theme: AppearanceSettingsView()
            case .icons: IconPickerView()
            case .screen: HomeSettingsView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Раздел", selection: $tab.animation(Motion.smooth)) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .onChange(of: tab) { _, _ in Haptics.selection() }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}
