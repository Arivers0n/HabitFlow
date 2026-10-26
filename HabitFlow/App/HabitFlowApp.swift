import SwiftUI
import SwiftData

@main
struct HabitFlowApp: App {
    private let container: ModelContainer
    @State private var store: HabitStore

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Habit.self, CheckIn.self, Relapse.self, Resist.self)
        } catch {
            // Если база повреждена — не падаем, а открываем пустую в памяти.
            print("Не удалось открыть базу: \(error)")
            container = try! ModelContainer(for: Habit.self, CheckIn.self, Relapse.self, Resist.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        _store = State(initialValue: HabitStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .modelContainer(container)
        }
    }
}

struct RootView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var allHabits: [Habit]
    @State private var tab = 0

    private var companion: CompanionManager { .shared }

    var body: some View {
        let ap = Appearance.shared
        let status = companion.status(allHabits)
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "checkmark.circle.fill") }
                .tag(0)
            CompanionScreen()
                .tabItem { Label("Напарник", systemImage: "pawprint.fill") }
                .tag(1)
            ProgressScreen()
                .tabItem { Label("Прогресс", systemImage: "chart.bar.xaxis") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .environment(\.openCompanionTab, { withAnimation(Motion.smooth) { tab = 1 } })
        .onChange(of: tab) { _, _ in Haptics.selection() }
        .tint(ap.accent)
        .fontDesign(ap.s.font.design)
        .preferredColorScheme(ap.s.scheme.colorScheme)
        .overlay {
            ZStack {
                if let c = store.celebration {
                    CelebrationView(celebration: c) {
                        withAnimation(Motion.smooth) { store.celebration = nil }
                    }
                    .transition(.opacity)
                } else if let r = companion.resist {
                    ResistView(event: r, character: companion.character) {
                        withAnimation(Motion.smooth) { companion.resist = nil }
                    }
                    .transition(.opacity)
                } else if let e = companion.levelUp, let status {
                    LevelUpView(event: e, status: status) {
                        withAnimation(Motion.smooth) { companion.levelUp = nil }
                    }
                    .transition(.opacity)
                }
            }
            .animation(Motion.smooth, value: store.celebration)
            .animation(Motion.smooth, value: companion.resist)
            .animation(Motion.smooth, value: companion.levelUp)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            CompanionPicker(isOnboarding: true)
        }
        .onChange(of: status?.level) { _, level in
            if let level { companion.checkLevel(level) }
        }
        .onAppear {
            companion.registerOpen()
            if let level = status?.level { companion.checkLevel(level) }
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                companion.registerOpen()
                store.checkAllMilestones(habits)
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !companion.state.onboardingDone }, set: { _ in })
    }
}
