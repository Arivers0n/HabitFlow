import Foundation
import Observation

/// Всё, что нужно экранам о напарнике в текущий момент.
struct CompanionStatus {
    let character: CompanionCharacter
    let xp: XPBreakdown
    let progress: LevelProgress
    let stage: CompanionStage
    let mood: CompanionMood
    let isNight: Bool
    let today: DaySummary
    let quest: HabitSnapshot?
    let bestQuit: (name: String, days: Int)?

    var level: Int { progress.level }
}

struct LevelUpEvent: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let gifts: [Gift]
    let hatched: Bool
    let stageChanged: CompanionStage?
}

struct ResistEvent: Identifiable, Equatable {
    let id = UUID()
    let habitName: String
    let symbol: String
    let colorHex: String
    let xp: Int
}

/// Сохраняемое состояние напарника. Опыт тут не хранится — он считается из истории.
struct CompanionState: Codable, Equatable {
    var characterID: String?
    var nickname = ""
    var userName = ""
    var onboardingDone = false
    var lastSeenLevel = 1
    var headwear: String?
    var aura: String?
    var hiddenDecor: [String] = []
    var lastOpen: Date?
    var gapAtOpen: TimeInterval?
    var showOnToday = true
    /// Угощения: даются за выполненные цели и «Устоял», тратятся на кормление.
    var treats = 0
    var lastFed: Date?
    var timesFed = 0
    var timesPetted = 0

    init() {}

    /// Часть состояния, общая для всех устройств (без «когда открывали на этом телефоне»).
    struct Synced: Codable, Equatable {
        var characterID: String?
        var nickname: String
        var userName: String
        var onboardingDone: Bool
        var lastSeenLevel: Int
        var headwear: String?
        var aura: String?
        var hiddenDecor: [String]
        var showOnToday: Bool
        var treats: Int
        var timesFed: Int
        var timesPetted: Int
    }

    var synced: Synced {
        get {
            Synced(characterID: characterID, nickname: nickname, userName: userName, onboardingDone: onboardingDone,
                   lastSeenLevel: lastSeenLevel, headwear: headwear, aura: aura, hiddenDecor: hiddenDecor,
                   showOnToday: showOnToday, treats: treats, timesFed: timesFed, timesPetted: timesPetted)
        }
        set {
            characterID = newValue.characterID
            nickname = newValue.nickname
            userName = newValue.userName
            onboardingDone = newValue.onboardingDone || onboardingDone
            lastSeenLevel = max(lastSeenLevel, newValue.lastSeenLevel)
            headwear = newValue.headwear
            aura = newValue.aura
            hiddenDecor = newValue.hiddenDecor
            showOnToday = newValue.showOnToday
            treats = newValue.treats
            timesFed = max(timesFed, newValue.timesFed)
            timesPetted = max(timesPetted, newValue.timesPetted)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characterID = try? c.decodeIfPresent(String.self, forKey: .characterID)
        nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? ""
        userName = (try? c.decodeIfPresent(String.self, forKey: .userName)) ?? ""
        onboardingDone = (try? c.decodeIfPresent(Bool.self, forKey: .onboardingDone)) ?? false
        lastSeenLevel = (try? c.decodeIfPresent(Int.self, forKey: .lastSeenLevel)) ?? 1
        headwear = try? c.decodeIfPresent(String.self, forKey: .headwear)
        aura = try? c.decodeIfPresent(String.self, forKey: .aura)
        hiddenDecor = (try? c.decodeIfPresent([String].self, forKey: .hiddenDecor)) ?? []
        lastOpen = try? c.decodeIfPresent(Date.self, forKey: .lastOpen)
        gapAtOpen = try? c.decodeIfPresent(TimeInterval.self, forKey: .gapAtOpen)
        showOnToday = (try? c.decodeIfPresent(Bool.self, forKey: .showOnToday)) ?? true
        treats = (try? c.decodeIfPresent(Int.self, forKey: .treats)) ?? 0
        lastFed = try? c.decodeIfPresent(Date.self, forKey: .lastFed)
        timesFed = (try? c.decodeIfPresent(Int.self, forKey: .timesFed)) ?? 0
        timesPetted = (try? c.decodeIfPresent(Int.self, forKey: .timesPetted)) ?? 0
    }
}

/// Игровой напарник: выбор персонажа, уровень, настроение, фразы, подарки.
@MainActor
@Observable
final class CompanionManager {
    static let shared = CompanionManager()
    private static let key = "companion.v1"

    var state: CompanionState {
        didSet { persist() }
    }

    /// Номер текущей фразы. Меняется при каждом открытии и тапе по облачку.
    var phraseSeed = Int.random(in: 0..<10_000)
    var levelUp: LevelUpEvent?
    var resist: ResistEvent?
    /// Последнее событие приложения: питомец отвечает на него мимикой и подпрыгиванием.
    private(set) var reaction: (event: PetAppEvent, at: Date)?

    private let engine = CompanionEngine()

    private init() {
        state = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(CompanionState.self, from: $0) } ?? CompanionState()
        lastSynced = state.synced
        PrefSync.register("companion", export: { [weak self] in
            guard let self else { return nil }
            return try? JSONEncoder().encode(self.state.synced)
        }, apply: { [weak self] data in
            guard let self, let s = try? JSONDecoder().decode(CompanionState.Synced.self, from: data) else { return }
            self.state.synced = s
        })
    }

    private var lastSynced: CompanionState.Synced?

    // MARK: - Угощения и игры

    static let maxTreats = 9

    private var testing: Bool { TestMode.shared.data != nil }

    func earnTreat() {
        guard hasCompanion, !testing else { return }
        state.treats = min(Self.maxTreats, state.treats + 1)
    }

    /// Покормить. Возвращает false, если угощений нет.
    @discardableResult
    func feed() -> Bool {
        if testing { return true }
        guard state.treats > 0 else { return false }
        state.treats -= 1
        state.lastFed = .now
        state.timesFed += 1
        return true
    }

    func petted() {
        guard !testing else { return }
        state.timesPetted += 1
    }

    /// Недавно покормили — напарник довольный (если только он не утешает после срыва).
    var recentlyFed: Bool {
        guard let f = state.lastFed else { return false }
        return Date().timeIntervalSince(f) < 30 * 60
    }

    var character: CompanionCharacter? { CompanionCatalog.character(state.characterID) }
    var hasCompanion: Bool { character != nil }
    var displayName: String {
        let n = state.nickname.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? (character?.name ?? "") : n
    }

    // MARK: - Расчёт

    func status(_ habits: [Habit], now: Date = .now) -> CompanionStatus? {
        guard let character else { return nil }
        // Снимок каждой привычки строится один раз (раньше — дважды: для активных и для опыта по всем).
        let everything = habits.map(\.snapshot)
        let snaps = everything.filter { !$0.isArchived }
        let xp = engine.xp(everything, now: now)
        let progress = LevelProgress(xp: xp.total)
        let hour = engine.calendar.component(.hour, from: now)
        return CompanionStatus(
            character: character,
            xp: xp,
            progress: progress,
            stage: XPRules.stage(for: progress.level),
            mood: adjustedMood(engine.mood(snaps, gapSinceLastOpen: state.gapAtOpen, now: now)),
            isNight: hour >= 23 || hour < 6,
            today: engine.summary(snaps, on: now),
            quest: engine.questHabit(snaps, now: now),
            bestQuit: engine.bestQuit(snaps, now: now)
        )
    }

    private func adjustedMood(_ m: CompanionMood) -> CompanionMood {
        if m != .caring && recentlyFed { return .happy }
        return m
    }

    func phrase(for s: CompanionStatus) -> String {
        let ctx = PhraseContext(userName: state.userName, mood: s.mood,
                                hour: engine.calendar.component(.hour, from: .now),
                                today: s.today, quest: s.quest?.name, bestQuit: s.bestQuit,
                                level: s.level, stage: s.stage,
                                strict: Appearance.shared.s.tone == .strict)
        return CompanionPhrases.pick(ctx, seed: phraseSeed)
    }

    func caringLine() -> String {
        CompanionPhrases.caringLine(name: state.userName, strict: Appearance.shared.s.tone == .strict, seed: phraseSeed)
    }

    func nextPhrase() { phraseSeed &+= 1 }

    /// Питомец реагирует на событие (выполнил привычку, срыв, новый уровень…).
    func react(_ event: PetAppEvent) {
        guard hasCompanion, !testing else { return }
        reaction = (event, .now)
    }

    // MARK: - События

    /// Вызывается при каждом открытии приложения: запоминает, сколько не заходили.
    func registerOpen(now: Date = .now) {
        if let last = state.lastOpen {
            let gap = now.timeIntervalSince(last)
            // Короткие переключения между приложениями не считаются новым заходом.
            if gap > 15 * 60 { state.gapAtOpen = gap }
        }
        state.lastOpen = now
        phraseSeed = Int.random(in: 0..<10_000)
    }

    /// Проверяет новый уровень. Если опыт уменьшился (сняли отметку), подарки не забираем и не выдаём повторно.
    func checkLevel(_ level: Int) {
        guard hasCompanion, level > state.lastSeenLevel else { return }
        let from = state.lastSeenLevel
        let gifts = GiftCatalog.all.filter { $0.level > from && $0.level <= level }
        let oldStage = XPRules.stage(for: from)
        let newStage = XPRules.stage(for: level)
        state.lastSeenLevel = level
        // Подарки над головой и ауру надеваем сразу — так награда видна.
        if let hw = gifts.last(where: { $0.kind == .headwear }) { state.headwear = hw.id }
        if let au = gifts.last(where: { $0.kind == .aura }) { state.aura = au.id }
        levelUp = LevelUpEvent(level: level, gifts: gifts,
                               hatched: oldStage == .egg && newStage != .egg,
                               stageChanged: newStage != oldStage ? newStage : nil)
        Haptics.celebrate()
        react(.levelUp)
        SoundService.shared.play(oldStage == .egg && newStage != .egg ? .hatch : .levelUp)
    }

    func showResist(_ h: Habit, xp: Int) {
        resist = ResistEvent(habitName: h.name, symbol: h.symbol, colorHex: h.colorHex, xp: xp)
        Haptics.success()
    }

    // MARK: - Выбор и гардероб

    func choose(_ c: CompanionCharacter, userName: String, currentLevel: Int) {
        let switching = state.characterID != nil
        state.characterID = c.id
        state.nickname = c.name
        state.userName = userName.trimmingCharacters(in: .whitespaces)
        state.onboardingDone = true
        // Уже накопленный опыт засчитывается, но без лавины поздравлений при первом выборе.
        if !switching { state.lastSeenLevel = max(state.lastSeenLevel, currentLevel) }
        phraseSeed = Int.random(in: 0..<10_000)
        Haptics.success()
    }

    func skipOnboarding() {
        state.onboardingDone = true
    }

    func toggleEquip(_ g: Gift) {
        switch g.kind {
        case .headwear: state.headwear = state.headwear == g.id ? nil : g.id
        case .aura: state.aura = state.aura == g.id ? nil : g.id
        case .decor:
            if state.hiddenDecor.contains(g.id) { state.hiddenDecor.removeAll { $0 == g.id } }
            else { state.hiddenDecor.append(g.id) }
        }
        Haptics.selection()
    }

    func isEquipped(_ g: Gift) -> Bool {
        switch g.kind {
        case .headwear: state.headwear == g.id
        case .aura: state.aura == g.id
        case .decor: !state.hiddenDecor.contains(g.id)
        }
    }

    /// Украшения островка, которые сейчас видны.
    func visibleDecor(level: Int) -> Set<String> {
        Set(GiftCatalog.unlocked(level: level).filter { $0.kind == .decor && !state.hiddenDecor.contains($0.id) }.map(\.id))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        let now = state.synced
        if now != lastSynced {
            lastSynced = now
            PrefSync.markChanged("companion")
        }
    }
}
