import SwiftUI

/// Первый шаг создания: шаблоны по типу привычки или «своя».
struct NewHabitGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: HabitKind = .build
    @State private var path: [HabitDraft] = []
    @State private var showAI = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Тип", selection: $kind) {
                        Text("Формирую").tag(HabitKind.build)
                        Text("Отказываюсь").tag(HabitKind.quit)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, _ in Haptics.selection() }

                    Text(kind == .build
                         ? "Отмечай выполнение, копи серию и получай награды."
                         : "Счётчик времени без срыва. Срыв сбросит серию, но рекорд и история останутся.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button { showAI = true; Haptics.tap() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [Color(hex: "4C8DFF"), Color(hex: "B65CFF")],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Описать словами").font(.headline)
                                Text("ИИ сам разложит на привычки и цели").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .card(radius: 22)
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        var d = HabitDraft()
                        d.kind = kind
                        d.colorHex = Palette.colors(for: kind)[0]
                        d.symbol = kind == .build ? "star.fill" : "nosign"
                        path.append(d)
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.pencil")
                                .font(.title3.weight(.semibold))
                                .frame(width: 46, height: 46)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Своя привычка").font(.headline)
                                Text("Название, значок, расписание — всё настроить").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .card(radius: 22)
                    }
                    .buttonStyle(PressableStyle())

                    Text("Шаблоны").font(.headline).padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(kind == .build ? HabitTemplate.build : HabitTemplate.quit) { t in
                            Button {
                                path.append(t.draft)
                                Haptics.tap()
                            } label: {
                                TemplateTile(draft: t.draft)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .animation(Motion.smooth, value: kind)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Новая привычка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .sheet(isPresented: $showAI) { AIHabitComposer(onAdded: { dismiss() }) }
            .navigationDestination(for: HabitDraft.self) { d in
                HabitEditorForm(draft: d, habit: nil) { dismiss() }
            }
        }
    }
}

private struct TemplateTile: View {
    let draft: HabitDraft

    var body: some View {
        let color = Color(hex: draft.colorHex)
        VStack(alignment: .leading, spacing: 12) {
            HabitIcon(symbol: draft.symbol, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(radius: 22, tint: color)
    }

    private var detail: String {
        if draft.kind == .quit { return draft.unitName.isEmpty ? "Счётчик без срыва" : "Учёт в: \(draft.unitName)" }
        if draft.isVolume { return "\(NumberText.value(draft.goalTarget)) \(draft.goalUnit) в день" }
        if draft.scheduleType == "perWeek" { return "\(draft.timesPerWeek) раза в неделю" }
        if draft.scheduleType == "weekdays" { return "По будням" }
        return "Каждый день"
    }
}

extension HabitDraft: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(kind)
        hasher.combine(symbol)
    }
}
