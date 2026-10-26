import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var all: [Habit]

    @State private var exportURL: URL?
    @State private var importing = false
    @State private var confirmWipe = false
    @State private var message: String?
    @State private var versionTaps = 0

    var body: some View {
        @Bindable var ap = Appearance.shared
        NavigationStack {
            Form {
                Section {
                    NavigationLink { AccountSettingsView() } label: {
                        HStack {
                            settingsRow(SyncEngine.shared.loggedIn ? (SyncEngine.shared.userName.isEmpty ? "Аккаунт" : SyncEngine.shared.userName) : "Войти",
                                        "person.crop.circle.fill", Appearance.shared.accent)
                            Spacer()
                            if SyncEngine.shared.loggedIn {
                                Image(systemName: SyncEngine.shared.moduleAvailable ? "checkmark.icloud.fill" : "icloud")
                                    .foregroundStyle(SyncEngine.shared.moduleAvailable ? Palette.success : Color.secondary)
                            }
                        }
                    }
                    NavigationLink { AISettingsView() } label: {
                        HStack {
                            settingsRow("Умные функции", "sparkles", Color(hex: "9B6BFF"))
                            Spacer()
                            Text(AI.statusText).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { FriendsView() } label: {
                        settingsRow("Друзья и семья", "person.2.fill", Color(hex: "FF5FA2"))
                    }
                } header: {
                    Text("Аккаунт")
                } footer: {
                    Text("Аккаунт общий с Копилкой: синхронизация iPhone и iPad, ИИ без своего ключа и круги друзей.")
                }

                Section("Оформление") {
                    NavigationLink { LookSettingsView(tab: .theme) } label: {
                        settingsRow("Темы и цвета", "paintpalette.fill", Appearance.shared.accent)
                    }
                    NavigationLink { LookSettingsView(tab: .icons) } label: {
                        settingsRow("Иконка приложения", "app.badge.fill", Color(hex: "B65CFF"))
                    }
                    NavigationLink { LookSettingsView(tab: .screen) } label: {
                        settingsRow("Главный экран", "rectangle.stack.fill", Color(hex: "2ECFC4"))
                    }
                }

                Section {
                    Toggle(isOn: $ap.s.animationsOn) { settingsRow("Анимации", "sparkles", Color(hex: "6E6BFF")) }
                    Toggle(isOn: $ap.s.hapticsOn) { settingsRow("Вибрация", "iphone.radiowaves.left.and.right", Color(hex: "FF9F0A")) }
                        .onChange(of: ap.s.hapticsOn) { _, on in if on { Haptics.success() } }
                    Picker(selection: $ap.s.tone) {
                        ForEach(Tone.allCases) { Text($0.title).tag($0) }
                    } label: {
                        settingsRow("Тон текстов", "text.bubble.fill", Color(hex: "34C759"))
                    }
                } header: {
                    Text("Поведение")
                } footer: {
                    Text(ap.s.tone == .gentle
                         ? "Мягкий: «Рекорд сохранён: 23 дня. Новая серия уже началась»."
                         : "Строгий: «Серия обнулена. Рекорд — 23 дня»." )
                }

                Section("Привычки") {
                    NavigationLink { TriggersView() } label: {
                        settingsRow("Причины срывов", "exclamationmark.bubble.fill", Palette.danger)
                    }
                    NavigationLink { ArchiveView() } label: {
                        HStack {
                            settingsRow("Архив", "archivebox.fill", .gray)
                            Spacer()
                            let n = all.filter(\.isArchived).count
                            if n > 0 { Text("\(n)").foregroundStyle(.secondary) }
                        }
                    }
                }

                Section {
                    Button {
                        do { exportURL = try BackupService.export(all) } catch { message = "Не получилось: \(error.localizedDescription)" }
                    } label: {
                        settingsRow("Создать резервную копию", "square.and.arrow.up.fill", Color(hex: "4C8DFF"))
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Отправить файл копии", systemImage: "paperplane.fill")
                        }
                    }
                    Button { importing = true } label: {
                        settingsRow("Восстановить из копии", "square.and.arrow.down.fill", Color(hex: "34C759"))
                    }
                    Button(role: .destructive) { confirmWipe = true } label: {
                        settingsRow("Удалить все данные", "trash.fill", .red)
                    }
                } header: {
                    Text("Данные")
                } footer: {
                    Text("Данные хранятся только на этом устройстве. Резервная копия — файл JSON, его можно сохранить в «Файлы» и восстановить на другом iPhone или iPad. Повторное восстановление ничего не дублирует.")
                }

                Section {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 7 {
                            versionTaps = 0
                            TestMode.shared.enter()
                        } else if versionTaps >= 4 {
                            Haptics.selection()
                        }
                    }
                } footer: {
                    if versionTaps >= 4 {
                        Text("Ещё \(7 - versionTaps) — и откроется проверка интерфейса на тестовых данных.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Настройки")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let n = try BackupService.importFile(url, into: context)
                        message = n == 0 ? "Новых привычек в копии не нашлось." : "Восстановлено: \(n) \(plural(n, "привычка", "привычки", "привычек"))."
                        Haptics.success()
                    } catch {
                        message = "Файл не подошёл: \(error.localizedDescription)"
                    }
                case .failure(let e):
                    message = e.localizedDescription
                }
            }
            .confirmationDialog("Удалить все привычки, отметки и срывы?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) { store.deleteAll(); Haptics.warning() }
            } message: {
                Text("Это нельзя отменить. Сначала можно сделать резервную копию.")
            }
            .alert("HabitFlow", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Строка настроек со значком в цветном квадрате, как в системных Настройках.
func settingsRow(_ title: String, _ symbol: String, _ color: Color) -> some View {
    HStack(spacing: 12) {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.gradient))
        Text(title).foregroundStyle(.primary)
    }
}

// MARK: - Главный экран

struct HomeSettingsView: View {
    var body: some View {
        @Bindable var ap = Appearance.shared
        Form {
            Section {
                Toggle("Напарник", isOn: Binding(get: { CompanionManager.shared.state.showOnToday },
                                                 set: { CompanionManager.shared.state.showOnToday = $0 }))
                Toggle("Сводка дня", isOn: $ap.s.showSummary)
                Toggle("Полоска недели", isOn: $ap.s.showWeekStrip)
                Picker("Первым показывать", selection: $ap.s.quitFirst) {
                    Text("Формирую").tag(false)
                    Text("Отказываюсь").tag(true)
                }
            } header: {
                Text("Блоки")
            } footer: {
                Text("Порядок самих привычек меняется кнопкой «Порядок» на экране «Сегодня».")
            }

            Section("Карточки") {
                Picker("Плотность", selection: $ap.s.density) {
                    ForEach(Density.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Секунды в счётчике без срыва", isOn: $ap.s.liveSeconds)
                Toggle("Показывать «избежал и сэкономил»", isOn: $ap.s.showSavings)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Главный экран")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Архив

struct ArchiveView: View {
    @Environment(HabitStore.self) private var store
    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.name) private var archived: [Habit]

    var body: some View {
        List {
            if archived.isEmpty {
                Text("Архив пуст. Свайп влево по привычке на главном экране убирает её сюда с сохранением истории.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(archived) { h in
                HStack(spacing: 12) {
                    HabitIcon(symbol: h.symbol, color: h.color, size: 36)
                    Text(h.name)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.delete(h) } label: { Label("Удалить", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { store.setArchived(h, false); Haptics.success() } label: {
                        Label("Вернуть", systemImage: "arrow.uturn.backward")
                    }
                    .tint(Palette.success)
                }
                .contextMenu {
                    Button { store.setArchived(h, false) } label: { Label("Вернуть", systemImage: "arrow.uturn.backward") }
                    Button(role: .destructive) { store.delete(h) } label: { Label("Удалить", systemImage: "trash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Архив")
        .navigationBarTitleDisplayMode(.inline)
    }
}
