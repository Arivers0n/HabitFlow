import SwiftUI
import SwiftData
import UserNotifications

/// Одна база на всё приложение — её же используют команды Siri.
@MainActor
final class AppData {
    static let shared = AppData()

    let container: ModelContainer
    let store: HabitStore

    private init() {
        let schema = Schema([Habit.self, CheckIn.self, Relapse.self, Resist.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Если база повреждена — не падаем, а открываем пустую в памяти.
            print("Не удалось открыть базу: \(error)")
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        store = HabitStore(context: container.mainContext)
        SyncEngine.shared.attach(container.mainContext)
    }
}

// MARK: - Быстрые действия на иконке и уведомления

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "new", localizedTitle: "Новая привычка", localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "plus.circle")),
            UIApplicationShortcutItem(type: "ai", localizedTitle: "Привычки с ИИ", localizedSubtitle: "Опиши словами",
                                      icon: UIApplicationShortcutIcon(systemImageName: "sparkles")),
            UIApplicationShortcutItem(type: "chat", localizedTitle: "Поговорить с напарником", localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right")),
            UIApplicationShortcutItem(type: "companion", localizedTitle: "Напарник", localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "pawprint")),
        ]
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            let type = item.type
            MainActor.assumeIsolated { SceneDelegate.pending = type }
        }
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    @MainActor static var pending: String?

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        MainActor.assumeIsolated { SceneDelegate.open(type) }
        completionHandler(true)
    }

    @MainActor static func open(_ type: String) {
        if let url = URL(string: "habitflow://\(type)") { AppRouter.shared.handle(url: url) }
    }
}

// MARK: - Приложение

@main
struct HabitFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var testMode = TestMode.shared

    var body: some Scene {
        WindowGroup {
            if let test = testMode.data {
                RootView()
                    .environment(test.store)
                    .modelContainer(test.container)
                    .id("test")
                    .safeAreaInset(edge: .top, spacing: 0) { TestModeBanner() }
            } else {
                RootView()
                    .environment(AppData.shared.store)
                    .modelContainer(AppData.shared.container)
                    .id("real")
                    .onOpenURL { AppRouter.shared.handle(url: $0) }
            }
        }
    }
}

// MARK: - Корневой экран

struct RootView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var allHabits: [Habit]
    @State private var welcomeDone = UserDefaults.standard.bool(forKey: "hf.welcomeDone")

    private var companion: CompanionManager { .shared }
    private var router: AppRouter { .shared }
    private var sync: SyncEngine { .shared }
    private var isTest: Bool { store.isTest }

    var body: some View {
        let ap = Appearance.shared
        let status = companion.status(allHabits)
        TabView(selection: Binding(get: { router.tab }, set: { router.tab = $0 })) {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "checkmark.circle.fill") }
                .tag(AppRouter.Tab.today)
            CompanionScreen()
                .tabItem { Label("Напарник", systemImage: "pawprint.fill") }
                .tag(AppRouter.Tab.companion)
            ProgressScreen()
                .tabItem { Label("Прогресс", systemImage: "chart.bar.xaxis") }
                .tag(AppRouter.Tab.progress)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .environment(\.openCompanionTab, { withAnimation(Motion.smooth) { router.tab = .companion } })
        .onChange(of: router.tab) { _, _ in Haptics.selection() }
        .tint(ap.accent)
        .fontDesign(ap.s.font.design)
        .preferredColorScheme(ap.s.scheme.colorScheme)
        .background { KeyboardShortcuts() }
        .overlay { overlays(status) }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if !sync.newCheers.isEmpty {
                    CheersToast(cheers: sync.newCheers) { withAnimation(Motion.smooth) { sync.markCheersSeen() } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let t = router.toast {
                    Text(t)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .card(radius: 18)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { router.toast = nil }
                }
            }
            .padding(.top, 6)
            .animation(Motion.bouncy, value: sync.newCheers)
            .animation(Motion.bouncy, value: router.toast)
        }
        .sheet(isPresented: Binding(get: { router.showChat }, set: { router.showChat = $0 })) {
            CompanionChatView()
        }
        .fullScreenCover(isPresented: Binding(get: { !isTest && (!welcomeDone || !companion.state.onboardingDone) },
                                              set: { _ in })) {
            OnboardingFlow(welcomeDone: $welcomeDone)
        }
        .onChange(of: status?.level) { _, level in
            if let level, !isTest { companion.checkLevel(level) }
        }
        .onAppear {
            guard !isTest else { return }
            companion.registerOpen()
            if let level = status?.level { companion.checkLevel(level) }
            if let p = SceneDelegate.pending { SceneDelegate.pending = nil; SceneDelegate.open(p) }
            HabitFlowShortcuts.updateAppShortcutParameters()
            Task { await startupSync() }
        }
        .onChange(of: phase) { _, p in
            guard p == .active, !isTest else { return }
            companion.registerOpen()
            store.checkAllMilestones(habits)
            HabitFlowShortcuts.updateAppShortcutParameters()
            Task { await sync.sync() }
        }
    }

    @ViewBuilder
    private func overlays(_ status: CompanionStatus?) -> some View {
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

    private func startupSync() async {
        guard sync.loggedIn else { return }
        await sync.checkModule()
        await sync.refreshAIStatus()
        await sync.sync()
        await FriendsStore.shared.joinPending()
    }
}

/// Приветствие и вход, затем выбор напарника.
private struct OnboardingFlow: View {
    @Binding var welcomeDone: Bool

    var body: some View {
        ZStack {
            if !welcomeDone {
                WelcomeView {
                    UserDefaults.standard.set(true, forKey: "hf.welcomeDone")
                    withAnimation(Motion.smooth) { welcomeDone = true }
                }
                .transition(.opacity)
            } else {
                CompanionPicker(isOnboarding: true)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environment(AppData.shared.store)
        .modelContainer(AppData.shared.container)
    }
}

/// Сочетания клавиш на iPad с клавиатурой.
private struct KeyboardShortcuts: View {
    var body: some View {
        let r = AppRouter.shared
        ZStack {
            Button("") { r.tab = .today; r.showNewHabit = true }.keyboardShortcut("n", modifiers: .command)
            Button("") { r.tab = .today; r.showAIComposer = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("") { r.chat(about: nil) }.keyboardShortcut("k", modifiers: .command)
            Button("") { r.tab = .today }.keyboardShortcut("1", modifiers: .command)
            Button("") { r.tab = .companion }.keyboardShortcut("2", modifiers: .command)
            Button("") { r.tab = .progress }.keyboardShortcut("3", modifiers: .command)
            Button("") { r.tab = .settings }.keyboardShortcut("4", modifiers: .command)
            Button("") { Task { await SyncEngine.shared.sync() } }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
