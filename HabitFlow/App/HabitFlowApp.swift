import SwiftUI
import SwiftData

@main
struct HabitFlowApp: App {
    private let container: ModelContainer
    @State private var store: HabitStore

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Habit.self, CheckIn.self, Relapse.self)
        } catch {
            // Если база повреждена — не падаем, а открываем пустую в памяти.
            print("Не удалось открыть базу: \(error)")
            container = try! ModelContainer(for: Habit.self, CheckIn.self, Relapse.self,
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
    @State private var tab = 0

    var body: some View {
        let ap = Appearance.shared
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "checkmark.circle.fill") }
                .tag(0)
            ProgressScreen()
                .tabItem { Label("Прогресс", systemImage: "chart.bar.xaxis") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .onChange(of: tab) { _, _ in Haptics.selection() }
        .tint(ap.accent)
        .fontDesign(ap.s.font.design)
        .preferredColorScheme(ap.s.scheme.colorScheme)
        .overlay {
            if let c = store.celebration {
                CelebrationView(celebration: c) {
                    withAnimation(Motion.smooth) { store.celebration = nil }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(Motion.smooth, value: store.celebration)
        .onChange(of: phase) { _, p in
            if p == .active { store.checkAllMilestones(habits) }
        }
    }
}
