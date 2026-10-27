import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(HabitStore.self) private var store
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @State private var selectedDay = Calendar.habitFlow.startOfDay(for: .now)
    @State private var editing: Habit?
    @State private var relapseFor: Habit?
    @State private var opened: Habit?
    @State private var confirmDelete: Habit?
    @State private var toast: String?
    @State private var editMode: EditMode = .inactive
    @State private var undoVisible = false
    @Environment(\.horizontalSizeClass) private var hSize

    private var router: AppRouter { .shared }

    private var build: [Habit] { habits.filter { $0.kind == .build } }
    private var quit: [Habit] { habits.filter { $0.kind == .quit } }
    private var cal: Calendar { .habitFlow }
    private var isToday: Bool { cal.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            Group {
                if hSize == .regular {
                    // iPad: слева напарник и сводка, справа привычки
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            VStack(spacing: 12) { headerBlocks }
                                .padding(16)
                        }
                        .frame(width: 400)
                        habitList(withHeader: false)
                    }
                } else {
                    habitList(withHeader: true)
                }
            }
            .background(AppBackground())
            .navigationTitle(title)
            .toolbar { toolbar }
            .navigationDestination(item: $opened) { HabitDetailView(habit: $0) }
            .sheet(isPresented: Binding(get: { router.showNewHabit }, set: { router.showNewHabit = $0 })) { NewHabitGallery() }
            .sheet(isPresented: Binding(get: { router.showAIComposer }, set: { router.showAIComposer = $0 })) { AIHabitComposer() }
            .sheet(item: $editing) { h in
                NavigationStack { HabitEditorForm(draft: HabitDraft(habit: h), habit: h) { editing = nil } }
            }
            .sheet(item: $relapseFor) { h in
                RelapseSheet(habit: h) { message in showToast(message) }
            }
            .confirmationDialog("Удалить «\(confirmDelete?.name ?? "")»?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Удалить вместе с историей", role: .destructive) {
                    if let h = confirmDelete { delete(h) }
                }
                Button("В архив") { if let h = confirmDelete { store.setArchived(h, true) } }
            } message: {
                Text("Удаление можно отменить в течение нескольких секунд. Архив сохранит всё и уберёт привычку с экрана.")
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if undoVisible, let d = store.lastDeleted {
                        UndoToast(name: d.dto.name) {
                            withAnimation(Motion.bouncy) {
                                store.undoDelete()
                                undoVisible = false
                            }
                            Haptics.success()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ToastView(text: toast)
                }
                .animation(Motion.bouncy, value: undoVisible)
            }
            .onAppear { store.checkAllMilestones(habits) }
            .task { await HealthService.shared.refresh() }
        }
    }

    @ViewBuilder
    private var headerBlocks: some View {
        let ap = Appearance.shared
        if CompanionManager.shared.hasCompanion && CompanionManager.shared.state.showOnToday {
            CompanionCard()
        }
        HealthTipCard()
        if ap.s.showSummary {
            SummaryHeader(build: build, quit: quit, day: selectedDay)
        }
        if ap.s.showWeekStrip && !build.isEmpty {
            WeekStrip(habits: build, selected: $selectedDay)
        }
    }

    private func habitList(withHeader: Bool) -> some View {
        let ap = Appearance.shared
        return List {
            if withHeader {
                Group { headerBlocks }
                    .plainRow(top: 4, bottom: 10)
            }

            if habits.isEmpty {
                emptyState.plainRow()
            } else if ap.s.quitFirst {
                quitSection
                buildSection
            } else {
                buildSection
                quitSection
            }

            Color.clear.frame(height: 24).plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .refreshable {
            if SyncEngine.shared.loggedIn { await SyncEngine.shared.sync() }
            Haptics.soft()
        }
    }

    private func delete(_ h: Habit) {
        withAnimation(Motion.smooth) { store.deleteWithUndo(h) }
        undoVisible = true
        Haptics.warning()
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation(Motion.smooth) { undoVisible = false }
        }
    }

    private var title: String {
        if isToday { return "Сегодня" }
        if cal.isDateInYesterday(selectedDay) { return "Вчера" }
        return selectedDay.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
    }

    // MARK: - Разделы

    @ViewBuilder
    private var buildSection: some View {
        if !build.isEmpty {
            SectionTitle(title: "Формирую", trailing: buildTrailing).plainRow(top: 8, bottom: 2)
            ForEach(build) { h in
                BuildHabitCard(habit: h, day: selectedDay) { opened = h }
                    .habitRow(h, edit: { editing = h }, delete: { confirmDelete = h }, archive: { store.setArchived(h, true) })
            }
            .onMove { store.reorder(build, from: $0, to: $1) }
        }
    }

    @ViewBuilder
    private var quitSection: some View {
        if !quit.isEmpty {
            SectionTitle(title: "Отказываюсь").plainRow(top: 12, bottom: 2)
            ForEach(quit) { h in
                QuitHabitCard(habit: h, onRelapse: { relapseFor = h }) { opened = h }
                    .habitRow(h, edit: { editing = h }, delete: { confirmDelete = h }, archive: { store.setArchived(h, true) })
            }
            .onMove { store.reorder(quit, from: $0, to: $1) }
        }
    }

    private var buildTrailing: String {
        let s = CompanionEngine(calendar: store.engine.calendar).summary(build.map(\.snapshot), on: selectedDay)
        return s.scheduled == 0 ? "" : "\(s.scheduledDone) из \(s.scheduled)"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            EmptyStateCard(symbol: "sparkles",
                           title: "Начни с одной привычки",
                           subtitle: "Выпивать 2 литра воды, читать по 20 страниц или бросить курить — выбери шаблон или создай свою.")
            Button { router.showNewHabit = true } label: {
                Label("Добавить привычку", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(color: Appearance.shared.accent))
            Button { router.showAIComposer = true } label: {
                Label("Описать словами — ИИ разложит", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.top, 12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if habits.count > 1 {
                Button(editMode.isEditing ? "Готово" : "Порядок") {
                    withAnimation(Motion.smooth) { editMode = editMode.isEditing ? .inactive : .active }
                    Haptics.tap()
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { router.showCards = true; Haptics.tap() } label: {
                Image(systemName: "rectangle.stack.fill")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Быстрые карточки")
            Button { router.showAIComposer = true; Haptics.tap() } label: {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Привычки с ИИ")
            Button { router.showNewHabit = true; Haptics.tap() } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Новая привычка")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(Motion.bouncy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(Motion.smooth) { if toast == text { toast = nil } }
        }
    }
}

// MARK: - Оформление строк списка

extension View {
    /// Строка списка без фона и разделителей — карточки рисуют себя сами.
    func plainRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Свайпы и контекстное меню карточки привычки.
    func habitRow(_ h: Habit, edit: @escaping () -> Void, delete: @escaping () -> Void,
                  archive: @escaping () -> Void) -> some View {
        plainRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: delete) { Label("Удалить", systemImage: "trash") }.tint(.red)
                Button(action: archive) { Label("Архив", systemImage: "archivebox") }.tint(.gray)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(action: edit) { Label("Изменить", systemImage: "pencil") }.tint(Appearance.shared.accent)
            }
            .contextMenu {
                Button(action: edit) { Label("Изменить", systemImage: "pencil") }
                Button(action: archive) { Label("В архив", systemImage: "archivebox") }
                Button(role: .destructive, action: delete) { Label("Удалить", systemImage: "trash") }
            }
    }
}

/// Всплывающее сообщение внизу экрана.
struct ToastView: View {
    var text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .card(radius: 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// «Привычка удалена · Отменить».
struct UndoToast: View {
    let name: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill").foregroundStyle(.secondary)
            Text("«\(name)» удалена").font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 8)
            Button("Отменить", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Appearance.shared.accent)
                .frame(minHeight: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .card(radius: 20)
        .padding(.horizontal, 20)
    }
}
