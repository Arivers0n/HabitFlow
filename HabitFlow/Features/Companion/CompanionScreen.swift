import SwiftUI
import SwiftData

/// Вкладка «Напарник»: большая сцена, опыт, гардероб и дорога подарков.
struct CompanionScreen: View {
    @Query private var all: [Habit]
    @State private var picking = false
    @State private var renaming = false
    @State private var naming = false
    @State private var text = ""
    @State private var tapLine: String?
    @State private var feedToken = 0
    @State private var lineTask: Task<Void, Never>?

    var body: some View {
        let mgr = CompanionManager.shared
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let s = mgr.status(all) {
                        hero(s, mgr: mgr)
                        xpCard(s)
                        wardrobe(s, mgr: mgr)
                        rulesCard
                        VStack(spacing: 10) {
                            Button { picking = true } label: {
                                Label("Сменить напарника", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .card(radius: 16)
                            }
                            Button { text = mgr.state.userName; naming = true } label: {
                                Label(mgr.state.userName.isEmpty ? "Как тебя называть" : "Обращение: \(mgr.state.userName)",
                                      systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .card(radius: 16)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .foregroundStyle(.primary)
                    } else {
                        EmptyStateCard(symbol: "pawprint.fill", title: "Заведи напарника",
                                       subtitle: "Он растёт от твоих привычек, радуется победам и поддерживает при срывах.")
                        Button { picking = true } label: { Text("Выбрать напарника") }
                            .buttonStyle(PrimaryButtonStyle(color: Appearance.shared.accent))
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Напарник")
            .sheet(isPresented: $picking) { CompanionPicker(isOnboarding: false) }
            .alert("Имя напарника", isPresented: $renaming) {
                TextField(mgr.character?.name ?? "", text: $text)
                Button("Сохранить") { mgr.state.nickname = text.trimmingCharacters(in: .whitespaces) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Как тебя называть?", isPresented: $naming) {
                TextField("Имя", text: $text)
                Button("Сохранить") { mgr.state.userName = text.trimmingCharacters(in: .whitespaces) }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Напарник будет обращаться к тебе по имени. Можно оставить пустым.")
            }
        }
    }

    // MARK: - Шапка

    private func hero(_ s: CompanionStatus, mgr: CompanionManager) -> some View {
        let tint = Color(hex: s.character.tintHex)
        return VStack(spacing: 12) {
            CompanionScene(config: .from(s), size: 300, mode: .full, feedToken: feedToken,
                           onEvent: { e in react(e, stage: s.stage) })
            if s.stage != .egg {
                playBar(mgr: mgr, tint: tint)
            } else {
                Text("Покрути яйцо пальцем или постучи по нему. Оно вылупится на уровне 2.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 4) {
                Button { text = mgr.displayName; renaming = true } label: {
                    HStack(spacing: 6) {
                        Text(mgr.displayName).font(.title2.weight(.bold))
                        Image(systemName: "pencil").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text("\(s.character.species) · \(s.stage.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoodChip(mood: s.mood)
                }
            }
            SpeechBubble(text: tapLine ?? mgr.phrase(for: s))
                .onTapGesture {
                    withAnimation(Motion.smooth) { tapLine = nil; mgr.nextPhrase() }
                    Haptics.selection()
                }
            XPBar(progress: s.progress, tint: tint)
            Button { AppRouter.shared.chat(about: nil) } label: {
                Label("Поговорить", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.16)))
                    .foregroundStyle(tint)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .card(radius: 32, tint: tint)
    }

    /// Угощения и подсказка, как играть.
    private func playBar(mgr: CompanionManager, tint: Color) -> some View {
        HStack(spacing: 10) {
            Button {
                if mgr.feed() {
                    feedToken += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        say(["Ням-ням! Спасибо!", "Вкуснятина!", "Ммм, моё любимое!"].randomElement() ?? "Ням!")
                    }
                } else {
                    say("Угощения дают за выполненные привычки и «Устоял»")
                    Haptics.warning()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("🍓")
                    Text(mgr.state.treats > 0 ? "Угостить · \(mgr.state.treats)" : "Нет угощений")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText(value: Double(mgr.state.treats)))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(mgr.state.treats > 0 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
                .foregroundStyle(mgr.state.treats > 0 ? Color.white : Color.secondary)
            }
            .buttonStyle(PressableStyle())
            .animation(Motion.smooth, value: mgr.state.treats)

            Spacer(minLength: 0)
            Text("Погладь, пощекочи, подними и брось")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func react(_ e: PetEvent, stage: CompanionStage) {
        let strict = Appearance.shared.s.tone == .strict
        let line: String?
        switch e {
        case .tap: line = CompanionPhrases.tapLine(seed: Int.random(in: 0..<100))
        case .tickle: line = ["Ха-ха-ха, щекотно!", "Хи-хи, хватит!", "Ой-ой, сдаюсь!"].randomElement()
        case .petted: line = ["Мурр…", "Как приятно!", "Ещё, пожалуйста", "Обожаю, когда гладят"].randomElement()
        case .pickedUp: line = ["Ой, я лечу?", "Держи крепче!", "Вжух!"].randomElement()
        case .thrown: line = ["Уиии!", "Лечууу!"].randomElement()
        case .landed: line = strict ? "Приземлился." : ["Ух! Ещё раз!", "Мягкая посадка!"].randomElement()
        case .fed: line = nil
        case .woke: line = ["Ой, я задремал…", "А? Я тут!", "Потягушки!"].randomElement()
        case .sleep: line = "Пойду вздремну… Тапни, если нужен"
        }
        if let line { say(line) }
    }

    private func say(_ line: String) {
        lineTask?.cancel()
        withAnimation(Motion.smooth) { tapLine = line }
        lineTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.smooth) { tapLine = nil }
        }
    }

    // MARK: - Опыт

    private func xpCard(_ s: CompanionStatus) -> some View {
        let tint = Color(hex: s.character.tintHex)
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Опыт").font(.headline)
                Spacer()
                Text("сегодня +\(s.xp.today) XP")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            LazyVGrid(columns: cols, spacing: 12) {
                xpTile("\(s.xp.habits)", "за привычки", "checkmark.circle.fill", Color(hex: "4C8DFF"))
                xpTile("\(s.xp.perfectDays)", "за идеальные дни", "star.circle.fill", Color(hex: "FFB340"))
                xpTile("\(s.xp.cleanDays)", "за дни без срыва", "shield.lefthalf.filled", Palette.success)
                xpTile("\(s.xp.resisted)", "за «Устоял»", "hand.raised.fill", Color(hex: "B65CFF"))
            }
            if let next = GiftCatalog.next(after: s.level) {
                HStack(spacing: 12) {
                    Image(systemName: next.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Следующий подарок: \(next.title)").font(.subheadline.weight(.semibold))
                        Text("на уровне \(next.level) · ещё \(max(0, XPRules.totalXP(forLevel: next.level) - s.xp.total)) XP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .card()
    }

    private func xpTile(_ value: String, _ caption: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline).monospacedDigit()
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Гардероб

    private func wardrobe(_ s: CompanionStatus, mgr: CompanionManager) -> some View {
        let tint = Color(hex: s.character.tintHex)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Подарки").font(.headline)
            if s.stage == .egg {
                Text("Аксессуары можно будет надеть, когда напарник вылупится — на уровне 2.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach([GiftKind.headwear, .aura, .decor], id: \.self) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(GiftCatalog.all.filter { $0.kind == kind }) { g in
                            let open = g.level <= s.level
                            Button {
                                guard open else { Haptics.warning(); return }
                                withAnimation(Motion.smooth) { mgr.toggleEquip(g) }
                            } label: {
                                GiftTile(gift: g, open: open, on: open && mgr.isEquipped(g), tint: tint)
                            }
                            .buttonStyle(PressableStyle(scale: 0.94))
                        }
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как растёт напарник").font(.headline)
            ruleRow("+\(XPRules.habitDone)", "за каждую выполненную привычку")
            ruleRow("+\(XPRules.perfectDay)", "бонус, если закрыты все цели дня")
            ruleRow("+\(XPRules.cleanDay)", "за каждые сутки без срыва")
            ruleRow("+\(XPRules.resisted)", "за «Устоял», до \(XPRules.resistedPerDay) раз в день")
            Text("Опыт считается по истории, поэтому снятая отметка забирает его обратно, а отметка задним числом — добавляет.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func ruleRow(_ xp: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(xp)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(Appearance.shared.accent)
            Text(text).font(.subheadline)
        }
    }
}

private struct GiftTile: View {
    let gift: Gift
    let open: Bool
    let on: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                Image(systemName: open ? gift.symbol : "lock.fill")
                    .font(.system(size: open ? 22 : 15, weight: .semibold))
                    .foregroundStyle(on ? Color.white : (open ? tint : Color.secondary))
            }
            .frame(height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(open && !on ? tint.opacity(0.35) : .clear, lineWidth: 1)
            )
            Text(open ? gift.title : "Ур. \(gift.level)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(open ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct MoodChip: View {
    let mood: CompanionMood

    private var symbol: String {
        switch mood {
        case .happy: "sun.max.fill"
        case .calm: "leaf.fill"
        case .sad: "cloud.rain.fill"
        case .caring: "heart.fill"
        }
    }

    private var color: Color {
        switch mood {
        case .happy: Color(hex: "FFB340")
        case .calm: Color(hex: "3DDC97")
        case .sad: Color(hex: "8EA2C8")
        case .caring: Color(hex: "FF8FB8")
        }
    }

    var body: some View {
        Label(mood.title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
