import SwiftUI
import SwiftData

/// Быстрые карточки: стопка из нескольких вопросов с ответом одним касанием или свайпом.
/// Вправо — главный ответ, влево — «позже». Питомец реагирует сразу после каждого ответа.
struct QuickEntryDeck: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @State private var cards: [QuickCard] = []
    @State private var index = 0
    @State private var loaded = false
    @State private var reaction: String?
    @State private var gained = 0
    @State private var drag: CGSize = .zero
    @State private var relapseFor: Habit?
    @State private var seed = Int.random(in: 0..<1000)

    private let threshold: CGFloat = 90

    private var finished: Bool { loaded && index >= cards.count }

    var body: some View {
        let accent = Appearance.shared.accent
        VStack(spacing: 14) {
            header(accent)
            pet(accent)
            Group {
                if finished {
                    finishedCard(accent)
                } else if index < cards.count {
                    cardView(cards[index], accent: accent)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            if !finished && index < cards.count {
                Text(hint(for: cards[index]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
        .background(AppBackground())
        .onAppear { load() }
        .sheet(item: $relapseFor) { h in
            RelapseSheet(habit: h) { _ in
                relapseFor = nil
                advance(CompanionManager.shared.caringLine())
            }
        }
    }

    // MARK: - Части экрана

    private func header(_ accent: Color) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<cards.count, id: \.self) { i in
                Capsule()
                    .fill(i < index ? accent : accent.opacity(i == index ? 0.55 : 0.18))
                    .frame(height: 5)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Закрыть")
        }
        .padding(.leading, 20)
        .padding(.trailing, 4)
        .animation(Motion.smooth, value: index)
    }

    @ViewBuilder
    private func pet(_ accent: Color) -> some View {
        let mgr = CompanionManager.shared
        if let s = mgr.status(habits) {
            VStack(spacing: 8) {
                CompanionScene(config: .from(s), size: 150)
                SpeechBubble(text: reaction ?? greeting(s))
                    .padding(.horizontal, 24)
            }
        }
    }

    private func greeting(_ s: CompanionStatus) -> String {
        let name = CompanionManager.shared.state.userName
        let strict = Appearance.shared.s.tone == .strict
        if cards.isEmpty && loaded {
            return strict ? "Вопросов нет — всё отмечено." : "Всё отмечено — вопросов нет!"
        }
        return CompanionPhrases.fill(strict ? "Несколько вопросов%N." : "Есть пара вопросов%N — это быстро!", name: name)
    }

    private func hint(for card: QuickCard) -> String {
        card.swipeRightAnswer != nil && card.kind != .mood
            ? "Вправо — главный ответ, влево — позже"
            : "Влево — позже"
    }

    // MARK: - Карточка

    private func cardView(_ card: QuickCard, accent: Color) -> some View {
        let progress = max(-1, min(1, drag.width / threshold))
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(card.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            optionsView(card, accent: accent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card(radius: 28, tint: swipeTint(progress, accent: accent))
        .offset(x: drag.width * 0.6)
        .rotationEffect(.degrees(Double(drag.width) / 24))
        .opacity(1 - abs(Double(progress)) * 0.25)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation }
                .onEnded { end(card, width: $0.translation.width) }
        )
        .id(card.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private func swipeTint(_ progress: CGFloat, accent: Color) -> Color? {
        if progress > 0.3 { return Palette.success }
        if progress < -0.3 { return .gray }
        return nil
    }

    @ViewBuilder
    private func optionsView(_ card: QuickCard, accent: Color) -> some View {
        if card.kind == .mood {
            HStack(spacing: 8) {
                ForEach(card.options) { o in
                    Button { answer(o, card: card) } label: {
                        Text(o.title)
                            .font(.title)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(0.12)))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Настроение \(o.id.replacingOccurrences(of: "mood-", with: "")) из 5")
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(card.options) { o in
                    optionButton(o, card: card, accent: accent)
                }
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ o: QuickOption, card: QuickCard, accent: Color) -> some View {
        switch o.role {
        case .primary:
            Button { answer(o, card: card) } label: { Text(o.title) }
                .buttonStyle(PrimaryButtonStyle(color: accent))
        case .secondary:
            Button { answer(o, card: card) } label: {
                Text(o.title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(0.14)))
            }
            .buttonStyle(PressableStyle())
        case .danger:
            Button { answer(o, card: card) } label: {
                Text(o.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.danger.opacity(0.12)))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func finishedCard(_ accent: Color) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(accent)
            Text(cards.isEmpty ? "Сегодня всё отмечено" : "Готово")
                .font(.title3.weight(.bold))
            if gained > 0 {
                Text("+\(gained) XP")
                    .font(.headline)
                    .foregroundStyle(accent)
            }
            Button { dismiss() } label: { Text("Закрыть") }
                .buttonStyle(PrimaryButtonStyle(color: accent))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card(radius: 28, tint: accent)
    }

    // MARK: - Логика

    private func load() {
        guard !loaded else { return }
        cards = QuickCardsService.shared.deck(habits)
        loaded = true
    }

    private func end(_ card: QuickCard, width: CGFloat) {
        if width > threshold, card.kind != .mood, let primary = card.options.first(where: { $0.role == .primary }) {
            withAnimation(Motion.smooth) { drag = .zero }
            answer(primary, card: card)
        } else if width < -threshold {
            withAnimation(Motion.smooth) { drag = .zero }
            skip(card)
        } else {
            withAnimation(Motion.bouncy) { drag = .zero }
        }
    }

    private func skip(_ card: QuickCard) {
        let out = QuickCardsService.shared.apply(.skipped, to: card, habits: habits, store: store, seed: seed &+ index)
        advance(out.reaction)
    }

    private func answer(_ option: QuickOption, card: QuickCard) {
        if option.answer == .relapse {
            relapseFor = habits.first { $0.id.uuidString == card.habitID }
            return
        }
        let out = QuickCardsService.shared.apply(option.answer, to: card, habits: habits, store: store, seed: seed &+ index)
        gained += out.xp
        Haptics.success()
        advance(out.reaction)
    }

    private func advance(_ line: String) {
        withAnimation(Motion.smooth) {
            reaction = line
            index += 1
            drag = .zero
        }
        if index >= cards.count {
            let name = CompanionManager.shared.state.userName
            let strict = Appearance.shared.s.tone == .strict
            let end = QuickReactions.finished(userName: name, strict: strict, gainedXP: gained, seed: seed)
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(Motion.smooth) { reaction = end }
            }
        }
    }
}
