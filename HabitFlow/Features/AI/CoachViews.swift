import SwiftUI
import SwiftData

// MARK: - Чат с напарником

struct CompanionChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var habits: [Habit]
    @State private var text = ""
    @FocusState private var focused: Bool

    private var chat: CoachChat { .shared }

    private let quick = [
        "Как у меня дела?",
        "Дай совет на сегодня",
        "Мне тяжело держаться",
        "Почему я срываюсь?",
        "Похвали меня",
    ]

    var body: some View {
        let mgr = CompanionManager.shared
        let tint = Color(hex: mgr.character?.tintHex ?? Appearance.shared.s.accentHex)
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            header(mgr: mgr, tint: tint)
                            if !AI.available { unavailableCard }
                            ForEach(chat.messages) { m in
                                Bubble(message: m, tint: tint).id(m.id)
                            }
                            if chat.thinking {
                                TypingBubble(tint: tint).id("typing")
                            }
                            if let error = chat.error {
                                VStack(spacing: 8) {
                                    Text(error).font(.footnote).foregroundStyle(Palette.danger).multilineTextAlignment(.center)
                                    Button("Повторить") { Task { await chat.retry(habits: habits) } }
                                        .font(.footnote.weight(.semibold))
                                }
                                .padding(.vertical, 6)
                                .id("error")
                            }
                            Color.clear.frame(height: 4).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.messages.count) { _, _ in scrollDown(proxy) }
                    .onChange(of: chat.thinking) { _, _ in scrollDown(proxy) }
                    .onAppear { scrollDown(proxy, animated: false) }
                }

                if chat.messages.isEmpty && AI.available {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quick, id: \.self) { q in
                                Button { send(q) } label: { Chip(title: q, selected: false, color: tint) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                }

                inputBar(tint: tint)
            }
            .background(AppBackground())
            .navigationTitle(mgr.hasCompanion ? mgr.displayName : "Напарник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { addIdea() } label: { Label("Идея от напарника", systemImage: "lightbulb") }
                        Button { Task { await addWatchSample() } } label: {
                            Label("Ответ как на часах", systemImage: "applewatch")
                        }
                        Button(role: .destructive) { chat.clear() } label: { Label("Очистить переписку", systemImage: "trash") }
                            .disabled(chat.messages.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task {
                if let p = chat.pending {
                    chat.pending = nil
                    await chat.send(p, habits: habits)
                }
            }
        }
    }

    private func header(mgr: CompanionManager, tint: Color) -> some View {
        VStack(spacing: 6) {
            if let s = mgr.status(habits) {
                CompanionScene(config: .from(s), size: 150, interactive: true)
            }
            Text(chat.thinking ? "Думаю…" : "Спроси о привычках, срывах или попроси совет")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(Motion.smooth, value: chat.thinking)
        }
        .padding(.bottom, 6)
    }

    private var unavailableCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(.secondary)
            Text("ИИ пока не подключён").font(.headline)
            Text("Войдите в аккаунт (Настройки → Аккаунт) — ИИ работает через сервер без своего ключа. Или добавьте свой ключ в «Умные функции».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card(radius: 22)
    }

    private func inputBar(tint: Color) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .card(radius: 22)
                .submitLabel(.send)
                .onSubmit { send(text) }
            Button { send(text) } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.gradient))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || chat.thinking || !AI.available)
            .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty || !AI.available ? 0.5 : 1)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Идея для мозгового штурма: берётся из банка идей, поэтому работает и без ИИ.
    private func addIdea() {
        guard let next = AICoach.nextIdea() else { return }
        chat.messages.append(AI.Message(role: "assistant", text: next.message))
        Haptics.soft()
    }

    /// Так напарник ответит на часах: одно-два коротких предложения.
    private func addWatchSample() async {
        let reply = await AICoach.watchReply(to: "Как у меня дела?", habits: habits)
        chat.messages.append(AI.Message(role: "assistant", text: "⌚ " + reply))
        Haptics.soft()
    }

    private func send(_ t: String) {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, AI.available else { return }
        text = ""
        Haptics.tap()
        Task { await chat.send(s, habits: habits) }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(Motion.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct Bubble: View {
    let message: AI.Message
    let tint: Color
    @State private var appear = false

    var body: some View {
        let mine = message.role == "user"
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if mine {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tint.gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.08))
                    }
                }
            if !mine { Spacer(minLength: 40) }
        }
        .scaleEffect(appear ? 1 : 0.92, anchor: mine ? .bottomTrailing : .bottomLeading)
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(Motion.bouncy ?? .default) { appear = true } }
    }
}

private struct TypingBubble: View {
    let tint: Color

    var body: some View {
        HStack {
            TimelineView(.animation(paused: !Motion.enabled)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .offset(y: -4 * max(0, sin(t * 7 - Double(i) * 0.7)))
                            .opacity(0.5 + 0.5 * max(0, sin(t * 7 - Double(i) * 0.7)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.08)))
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
    }
}

// MARK: - Привычки из текста

struct AIHabitComposer: View {
    var onAdded: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(HabitStore.self) private var store
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var results: [AICoach.Suggestion] = []
    @FocusState private var focused: Bool

    private let examples = [
        "Хочу бросить курить, обычно выкуриваю 15 в день по 15 ₽ за штуку",
        "Пить 2 литра воды и читать перед сном",
        "Спорт 3 раза в неделю, меньше сладкого",
        "Медитировать по утрам по будням",
    ]

    var body: some View {
        let accent = Appearance.shared.accent
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Расскажи своими словами").font(.title3.weight(.bold))
                        Text("ИИ сам разложит на привычки: расписание, цели и единицы. Можно надиктовать — нажми микрофон на клавиатуре.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Например: бросить пить колу и гулять 30 минут каждый день", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .padding(14)
                        .card(radius: 20)

                    if results.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(examples, id: \.self) { e in
                                Button { text = e; Haptics.selection() } label: {
                                    Text(e).font(.footnote).multilineTextAlignment(.leading)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                                }
                                .buttonStyle(PressableStyle())
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    if !AI.available {
                        Text("ИИ не подключён: войдите в аккаунт или добавьте ключ в настройках.")
                            .font(.footnote).foregroundStyle(Palette.danger)
                    }

                    Button(action: run) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                            Text(busy ? "Думаю…" : (results.isEmpty ? "Разобрать" : "Разобрать заново"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty || !AI.available)
                    .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty || !AI.available ? 0.6 : 1)

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Palette.danger)
                    }

                    if !results.isEmpty {
                        Text("Что получилось").font(.headline).padding(.top, 4)
                        ForEach($results) { $r in
                            SuggestionRow(s: $r)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, results.isEmpty ? 0 : 90)
                .animation(Motion.smooth, value: results.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) {
                if !results.isEmpty {
                    let n = results.filter(\.selected).count
                    Button(action: add) {
                        Text(n == 0 ? "Выберите привычки" : "Добавить \(n) \(plural(n, "привычку", "привычки", "привычек"))")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .disabled(n == 0)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Привычки с ИИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }

    private func run() {
        focused = false
        busy = true
        error = nil
        Task {
            do {
                let r = try await AICoach.habits(from: text)
                withAnimation(Motion.smooth) { results = r }
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
            busy = false
        }
    }

    private func add() {
        for r in results where r.selected {
            store.create(r.draft)
        }
        Haptics.success()
        dismiss()
        onAdded?()
    }
}

private struct SuggestionRow: View {
    @Binding var s: AICoach.Suggestion

    var body: some View {
        let d = s.draft
        let color = Color(hex: d.colorHex)
        Button {
            s.selected.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                HabitIcon(symbol: d.symbol, color: color, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.name).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    if !s.why.isEmpty {
                        Text(s.why).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: s.selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(s.selected ? color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .card(radius: 20, tint: s.selected ? color : nil)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var detail: String {
        let d = s.draft
        if d.kind == .quit {
            var t = "Отказываюсь"
            if !d.unitName.isEmpty { t += " · в \(d.unitName)" }
            if d.baselinePerDay > 0 { t += " · обычно \(NumberText.value(d.baselinePerDay)) в день" }
            return t
        }
        var sched: String
        switch d.scheduleType {
        case "perWeek": sched = "\(d.timesPerWeek) \(plural(d.timesPerWeek, "раз", "раза", "раз")) в неделю"
        case "weekdays": sched = WeekdayNames.mondayFirst.filter(d.weekdays.contains).map { WeekdayNames.short[$0] }.joined(separator: ", ")
        default: sched = "Каждый день"
        }
        if d.isVolume { sched += " · \(NumberText.value(d.goalTarget)) \(d.goalUnit)" }
        return sched
    }
}

// MARK: - Разбор недели

struct WeeklyReviewCard: View {
    let habits: [Habit]
    @State private var text: String? = AICoach.cachedReview
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let accent = Appearance.shared.accent
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Разбор недели", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
                if text != nil && !busy {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Обновить разбор")
                }
            }
            if busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Напарник смотрит на неделю…").font(.subheadline).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if let text {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                Button { AppRouter.shared.chat(about: "Давай обсудим разбор моей недели: \(text.prefix(300))") } label: {
                    Label("Обсудить с напарником", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.footnote.weight(.semibold))
                }
            } else {
                Text(AI.available ? "Напарник посмотрит на серии и срывы за неделю и подскажет, на чём сосредоточиться."
                                  : "Разбор по вашей истории: сильные стороны, просадки и микро-шаги. С входом в аккаунт он станет живее.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: load) {
                    Text("Сделать разбор")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.15)))
                }
                .buttonStyle(PressableStyle())
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Palette.danger)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(Motion.smooth, value: busy)
    }

    private func load() {
        busy = true
        error = nil
        Task {
            do {
                text = try await AICoach.weeklyReview(habits)
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Настройки ИИ

struct AISettingsView: View {
    @State private var key = AIConfig.apiKey ?? ""
    @State private var base = AIConfig.baseURL
    @State private var model = AIConfig.model
    @State private var checking = false
    @State private var result: String?

    var body: some View {
        let sync = SyncEngine.shared
        Form {
            Section {
                HStack {
                    Text("Сейчас")
                    Spacer()
                    Text(AI.statusText).foregroundStyle(AI.available ? Palette.success : .secondary)
                }
                if !sync.loggedIn {
                    NavigationLink { AccountSettingsView() } label: { Text("Войти в аккаунт") }
                }
            } footer: {
                Text("С аккаунтом ИИ работает через ваш сервер — ключ там же, где у Копилки. Свой ключ ниже нужен, только если хотите платить за ИИ сами или используете свой шлюз.")
            }

            Section("Свой ключ (необязательно)") {
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Base URL шлюза (пусто — Anthropic)", text: $base)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Модель (пусто — по умолчанию)", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    save()
                    check()
                } label: {
                    HStack {
                        Text("Сохранить и проверить")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(checking)
                if let result {
                    Text(result).font(.footnote).foregroundStyle(result.hasPrefix("Работает") ? Palette.success : Palette.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Умные функции")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: save)
    }

    private func save() {
        AIConfig.apiKey = key.isEmpty ? nil : key
        AIConfig.baseURL = base
        AIConfig.model = model
    }

    private func check() {
        checking = true
        result = nil
        Task {
            if SyncEngine.shared.loggedIn { await SyncEngine.shared.refreshAIStatus() }
            do {
                _ = try await AI.ask("Ответь одним словом: привет", maxTokens: 20)
                result = "Работает: \(AI.statusText.lowercased())"
                Haptics.success()
            } catch {
                result = error.localizedDescription
                Haptics.warning()
            }
            checking = false
        }
    }
}
