import SwiftUI
import SwiftData

// MARK: - Переход на вкладку напарника

private struct OpenCompanionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openCompanionTab: () -> Void {
        get { self[OpenCompanionKey.self] }
        set { self[OpenCompanionKey.self] = newValue }
    }
}

// MARK: - Карточка на «Сегодня»

/// Живая карточка напарника вверху главного экрана: сцена, фраза, опыт и просьба-квест.
struct CompanionCard: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openCompanionTab) private var openTab
    @Query private var all: [Habit]

    @State private var tapLine: String?
    @State private var gain: Int?

    var body: some View {
        let mgr = CompanionManager.shared
        if let s = mgr.status(all) {
            let tint = Color(hex: s.character.tintHex)
            HStack(alignment: .center, spacing: 10) {
                CompanionScene(config: .from(s), size: 128, onTap: { react() })
                    .padding(.leading, -6)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(mgr.displayName).font(.headline).lineLimit(1)
                        LevelChip(level: s.level, tint: tint)
                        Spacer(minLength: 0)
                        Button(action: openTab) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Открыть напарника")
                    }
                    SpeechBubble(text: tapLine ?? mgr.phrase(for: s))
                        .onTapGesture {
                            withAnimation(Motion.smooth) { tapLine = nil; mgr.nextPhrase() }
                            Haptics.selection()
                        }
                    XPBar(progress: s.progress, tint: tint, compact: true)
                    if s.mood != .caring, let quest = questHabit(s) {
                        QuestButton(habit: quest, tint: tint)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .padding(.leading, 6)
            .card(radius: 28, tint: tint)
            .overlay(alignment: .topTrailing) {
                if let gain {
                    Text("+\(gain) XP")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(tint.gradient))
                        .shadow(color: tint.opacity(0.5), radius: 6)
                        .padding(10)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .onChange(of: s.xp.total) { old, new in
                if new > old { showGain(new - old) }
            }
        }
    }

    private func questHabit(_ s: CompanionStatus) -> Habit? {
        guard let q = s.quest else { return nil }
        return all.first { !$0.isArchived && $0.kind == .build && $0.name == q.name
            && !store.engine.isDone(store.value(of: $0), goal: $0.goal) }
    }

    private func react() {
        withAnimation(Motion.smooth) { tapLine = CompanionPhrases.tapLine(seed: Int.random(in: 0..<100)) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.smooth) { tapLine = nil }
        }
    }

    private func showGain(_ n: Int) {
        withAnimation(Motion.bouncy) { gain = n }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.smooth) { gain = nil }
        }
    }
}

/// Кнопка «просьбы» напарника: выполнить привычку прямо из карточки.
private struct QuestButton: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    let tint: Color

    var body: some View {
        Button {
            withAnimation(Motion.bouncy) {
                if habit.goal.isBinary { store.toggle(habit) } else { store.add(habit.goal.step, to: habit) }
            }
            Haptics.success()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: habit.goal.isBinary ? "checkmark" : "plus")
                    .font(.caption.weight(.bold))
                Text(habit.goal.isBinary ? habit.name : "\(NumberText.value(habit.goal.step)) \(habit.goal.unit) · \(habit.name)")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule().fill(habit.color.gradient))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Мелкие элементы

struct LevelChip: View {
    let level: Int
    let tint: Color

    var body: some View {
        Text("Ур. \(level)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .contentTransition(.numericText(value: Double(level)))
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(alignment: .topLeading) {
                Circle().fill(Color.primary.opacity(0.07))
                    .frame(width: 8, height: 8)
                    .offset(x: -6, y: 14)
            }
            .id(text)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            .animation(Motion.smooth, value: text)
            .contentShape(Rectangle())
    }
}

struct XPBar: View {
    let progress: LevelProgress
    let tint: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * progress.fraction))
                        .shadow(color: tint.opacity(0.5), radius: 4)
                }
            }
            .frame(height: compact ? 7 : 10)
            .id(progress.level)
            .animation(Motion.bouncy, value: progress.fraction)

            HStack {
                if !compact { Text("Уровень \(progress.level)") }
                Spacer()
                Text(progress.isMax ? "Максимум" : "\(progress.xpInLevel) / \(progress.xpForNext) XP")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}
