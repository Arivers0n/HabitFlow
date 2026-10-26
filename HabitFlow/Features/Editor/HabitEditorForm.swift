import SwiftUI

/// Создание и редактирование привычки.
struct HabitEditorForm: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: HabitDraft
    let habit: Habit?
    var onDone: () -> Void

    @State private var showAllSymbols = false

    private var isNew: Bool { habit == nil }
    private var color: Color { Color(hex: draft.colorHex) }

    var body: some View {
        Form {
            // Живое превью
            Section {
                HStack(spacing: 14) {
                    HabitIcon(symbol: draft.symbol, color: color, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name.isEmpty ? "Название" : draft.name)
                            .font(.headline)
                            .foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
                        Text(draft.kind == .build ? "Формирую" : "Отказываюсь")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .animation(Motion.smooth, value: draft.colorHex)

                TextField("Название", text: $draft.name)
                    .font(.body.weight(.medium))
                    .submitLabel(.done)

                if isNew {
                    Picker("Тип", selection: $draft.kind) {
                        Text("Формирую").tag(HabitKind.build)
                        Text("Отказываюсь").tag(HabitKind.quit)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: draft.kind) { _, k in
                        draft.colorHex = Palette.colors(for: k)[0]
                        draft.symbol = (SymbolCatalog.symbols(for: k).first) ?? "star.fill"
                    }
                }
            }

            // Значок и цвет
            Section("Значок") {
                let symbols = SymbolCatalog.symbols(for: draft.kind)
                let shown = showAllSymbols ? symbols : Array(symbols.prefix(12))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(shown, id: \.self) { s in
                        Button {
                            draft.symbol = s
                            Haptics.selection()
                        } label: {
                            Image(systemName: s)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(draft.symbol == s ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(draft.symbol == s ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
                                )
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
                Button(showAllSymbols ? "Свернуть" : "Все значки") {
                    withAnimation(Motion.smooth) { showAllSymbols.toggle() }
                }
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 12) {
                    ForEach(Palette.colors(for: draft.kind), id: \.self) { hex in
                        Button {
                            draft.colorHex = hex
                            Haptics.selection()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex).gradient)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if draft.colorHex == hex {
                                        Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().strokeBorder(Color.primary.opacity(draft.colorHex == hex ? 0.5 : 0), lineWidth: 2).padding(-4))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Цвет")
            } footer: {
                Text(draft.kind == .build ? "Мягкие цвета для того, что строишь." : "Для вредных привычек — строгая красно-оранжевая гамма.")
            }

            if draft.kind == .build { buildSections } else { quitSections }

            Section {
                Toggle("Напоминание", isOn: $draft.reminderOn.animation(Motion.smooth))
                if draft.reminderOn {
                    DatePicker("Время", selection: $draft.reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                if draft.reminderOn && draft.scheduleType == "weekdays" && draft.kind == .build {
                    Text("Напомню только в выбранные дни.")
                }
            }

            Section {
                Picker("Видят друзья", selection: $draft.shareMode) {
                    Text(draft.kind == .build ? "Авто (да)" : "Авто (нет)").tag(0)
                    Text("Да").tag(1)
                    Text("Нет").tag(2)
                }
            } footer: {
                Text("В кругах друзей видно название и серию. Вредные привычки по умолчанию скрыты.")
            }

            Section("Заметка") {
                TextField("Зачем мне это", text: $draft.note, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "Новая привычка" : "Изменить")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onDone() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Создать" : "Сохранить") { save() }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid)
            }
        }
    }

    // MARK: - Полезная

    @ViewBuilder
    private var buildSections: some View {
        Section("Расписание") {
            Picker("Как часто", selection: $draft.scheduleType.animation(Motion.smooth)) {
                Text("Каждый день").tag("daily")
                Text("N в неделю").tag("perWeek")
                Text("По дням").tag("weekdays")
            }
            .pickerStyle(.segmented)

            if draft.scheduleType == "perWeek" {
                Stepper("\(draft.timesPerWeek) \(plural(draft.timesPerWeek, "раз", "раза", "раз")) в неделю",
                        value: $draft.timesPerWeek, in: 1...7)
            }
            if draft.scheduleType == "weekdays" {
                HStack(spacing: 6) {
                    ForEach(WeekdayNames.mondayFirst, id: \.self) { wd in
                        let on = draft.weekdays.contains(wd)
                        Button {
                            if on { draft.weekdays.remove(wd) } else { draft.weekdays.insert(wd) }
                            Haptics.selection()
                        } label: {
                            Text(WeekdayNames.short[wd])
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
                                )
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            DatePicker("Отслеживать с", selection: $draft.startDate, in: ...Date.now, displayedComponents: .date)
        }

        Section {
            Toggle("Считать количество", isOn: $draft.isVolume.animation(Motion.smooth))
            if draft.isVolume {
                numberRow("Цель в день", value: $draft.goalTarget)
                HStack {
                    Text("Единица")
                    Spacer()
                    TextField("мл", text: $draft.goalUnit)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["мл", "мин", "стр", "раз", "км", "шагов", "ч"], id: \.self) { u in
                            Button { draft.goalUnit = u; Haptics.selection() } label: {
                                Chip(title: u, selected: draft.goalUnit == u, color: color)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                numberRow("Шаг кнопки «+»", value: $draft.goalStep)
            }
        } header: {
            Text("Цель")
        } footer: {
            Text(draft.isVolume
                 ? "Каждое касание добавляет шаг. Удержание кнопки — ввести своё число."
                 : "Одно касание — отметка «сделано».")
        }
    }

    // MARK: - Отказ

    @ViewBuilder
    private var quitSections: some View {
        Section {
            DatePicker("Не употребляю с", selection: $draft.startDate, in: ...Date.now,
                       displayedComponents: [.date, .hourAndMinute])
        } footer: {
            Text("Если бросил раньше — укажи дату, счётчик продолжит с неё.")
        }

        Section {
            HStack {
                Text("Единица")
                Spacer()
                TextField("сигарет", text: $draft.unitName)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["сигарет", "порций", "бокалов", "раз", "мин", "затяжек"], id: \.self) { u in
                        Button { draft.unitName = u; Haptics.selection() } label: {
                            Chip(title: u, selected: draft.unitName == u, color: color)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            numberRow("Обычно в день", value: $draft.baselinePerDay)
            numberRow("Цена единицы, ₽", value: $draft.costPerUnit)
        } header: {
            Text("Учёт")
        } footer: {
            Text("Обычная норма и цена нужны, чтобы считать, сколько ты не употребил и сколько сэкономил. Можно оставить 0.")
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private func save() {
        guard draft.isValid else { return }
        draft.colorHex = Palette.sanitized(draft.colorHex, kind: draft.kind)
        if let habit {
            store.update(habit, with: draft)
        } else {
            store.create(draft)
        }
        Haptics.success()
        onDone()
    }
}

/// Подборки значков SF Symbols под тип привычки.
enum SymbolCatalog {
    static let build = [
        "drop.fill", "figure.run", "dumbbell.fill", "brain.head.profile", "book.fill", "moon.stars.fill",
        "figure.walk", "bicycle", "figure.yoga", "figure.flexibility", "leaf.fill", "carrot.fill",
        "bed.double.fill", "sun.max.fill", "pencil.and.outline", "guitars.fill", "paintpalette.fill", "music.note",
        "character.book.closed.fill", "graduationcap.fill", "laptopcomputer", "heart.fill", "pills.fill", "cup.and.saucer.fill",
        "shoeprints.fill", "figure.pool.swim", "tennis.racket", "camera.fill", "house.fill", "dog.fill",
        "checklist", "star.fill", "flame.fill", "sparkles", "hands.sparkles.fill", "face.smiling",
    ]

    static let quit = [
        "nosign", "smoke.fill", "wineglass.fill", "birthday.cake.fill", "iphone", "takeoutbag.and.cup.and.straw.fill",
        "cloud.fill", "gamecontroller.fill", "cart.fill", "cup.and.saucer.fill", "mug.fill", "tv.fill",
        "bag.fill", "creditcard.fill", "bubble.left.and.exclamationmark.bubble.right.fill", "hand.raised.fill", "bolt.fill", "flame.fill",
        "fork.knife", "popcorn.fill", "dice.fill", "moon.zzz.fill", "exclamationmark.triangle.fill", "xmark.octagon.fill",
    ]

    static func symbols(for kind: HabitKind) -> [String] { kind == .build ? build : quit }
}
