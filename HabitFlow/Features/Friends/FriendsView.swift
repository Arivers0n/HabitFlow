import SwiftUI
import SwiftData

// MARK: - Данные кругов

struct FriendHabit: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let colorHex: String
    let kind: HabitKind
    let streak: Int
    let best: Int
    let today: Bool
}

struct FriendMember: Identifiable, Hashable {
    let id: String
    let name: String
    let me: Bool
    let companion: String
    let companionName: String
    let level: Int
    let stage: Int
    let mood: String
    let habits: [FriendHabit]
    let updated: Date?
    let cheersToday: Int
    let cheeredByMe: Bool
}

struct FriendCircle: Identifiable, Hashable {
    let id: String
    let name: String
    let code: String
    let owner: String
    let members: [FriendMember]
}

@MainActor
@Observable
final class FriendsStore {
    static let shared = FriendsStore()

    var circles: [FriendCircle] = []
    var loading = false
    var error: String?

    private var sync: SyncEngine { .shared }

    private var dayStart: Double { Calendar.habitFlow.startOfDay(for: .now).timeIntervalSince1970 * 1000 }

    func load() async {
        guard sync.loggedIn, sync.moduleAvailable else { return }
        loading = true
        defer { loading = false }
        do {
            await sync.sync()
            let obj = try await sync.call("/api/hf/circles", ["dayStart": dayStart])
            circles = (obj["circles"] as? [[String: Any]] ?? []).map(parseCircle)
            sync.handleCheers(obj["cheers"])
            error = nil
            await joinPending()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func create(_ name: String) async throws {
        let obj = try await sync.call("/api/hf/circle/create", ["name": name, "dayStart": dayStart])
        if let c = obj["circle"] as? [String: Any] { circles.append(parseCircle(c)) }
    }

    func join(_ code: String) async throws {
        let obj = try await sync.call("/api/hf/circle/join", ["code": code, "dayStart": dayStart])
        if let c = obj["circle"] as? [String: Any] {
            let circle = parseCircle(c)
            circles.removeAll { $0.id == circle.id }
            circles.append(circle)
        }
    }

    func leave(_ c: FriendCircle) async throws {
        try await sync.call("/api/hf/circle/leave", ["circle": c.id])
        circles.removeAll { $0.id == c.id }
    }

    func newCode(_ c: FriendCircle) async throws {
        let obj = try await sync.call("/api/hf/circle/update", ["circle": c.id, "newCode": true, "dayStart": dayStart])
        if let raw = obj["circle"] as? [String: Any] { replace(parseCircle(raw)) }
    }

    func kick(_ m: FriendMember, from c: FriendCircle) async throws {
        let obj = try await sync.call("/api/hf/circle/update", ["circle": c.id, "kick": m.id, "dayStart": dayStart])
        if let raw = obj["circle"] as? [String: Any] { replace(parseCircle(raw)) }
    }

    func cheer(_ m: FriendMember, in c: FriendCircle, emoji: String) async throws {
        try await sync.call("/api/hf/cheer", ["circle": c.id, "to": m.id, "emoji": emoji])
        await load()
    }

    func inviteLink(_ c: FriendCircle) -> URL? {
        URL(string: "\(sync.server)/api/hf/invite?code=\(c.code)")
    }

    /// Вступить по коду из ссылки-приглашения, когда пользователь вошёл.
    func joinPending() async {
        guard let code = UserDefaults.standard.string(forKey: "hf.pendingJoin"), !code.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "hf.pendingJoin")
        guard !circles.contains(where: { $0.code == code }) else { return }
        do {
            try await join(code)
            AppRouter.shared.say("Ты в круге «\(circles.last?.name ?? "Друзья")»")
            Haptics.success()
        } catch {
            AppRouter.shared.say("Не удалось вступить: \(error.localizedDescription)")
        }
    }

    private func replace(_ c: FriendCircle) {
        if let i = circles.firstIndex(where: { $0.id == c.id }) { circles[i] = c }
    }

    private func parseCircle(_ c: [String: Any]) -> FriendCircle {
        let members = (c["members"] as? [[String: Any]] ?? []).map { m -> FriendMember in
            let p = m["profile"] as? [String: Any] ?? [:]
            let habits = (p["habits"] as? [[String: Any]] ?? []).enumerated().map { i, h in
                FriendHabit(id: "\(i)-\(jStr(h["name"]))", name: jStr(h["name"]), symbol: jStr(h["symbol"]).isEmpty ? "star.fill" : jStr(h["symbol"]),
                            colorHex: jStr(h["color"]).isEmpty ? "4C8DFF" : jStr(h["color"]),
                            kind: jStr(h["kind"]) == "quit" ? .quit : .build,
                            streak: jInt(h["streak"]), best: jInt(h["best"]), today: jBool(h["today"]))
            }
            let name = jStr(p["name"]).isEmpty ? jStr(m["name"]) : jStr(p["name"])
            return FriendMember(id: jStr(m["id"]), name: name.isEmpty ? "Без имени" : name, me: jBool(m["me"]),
                                companion: jStr(p["companion"]), companionName: jStr(p["companionName"]),
                                level: jInt(p["level"]), stage: jInt(p["stage"]), mood: jStr(p["mood"]),
                                habits: habits, updated: jDate(p["updated"]),
                                cheersToday: jInt(m["cheersToday"]), cheeredByMe: jBool(m["cheeredByMe"]))
        }
        return FriendCircle(id: jStr(c["id"]), name: jStr(c["name"]), code: jStr(c["code"]), owner: jStr(c["owner"]),
                       members: members.sorted { $0.me && !$1.me })
    }
}

// MARK: - Экран «Друзья»

struct FriendsView: View {
    @State private var creating = false
    @State private var joining = false
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?

    private var store: FriendsStore { .shared }

    var body: some View {
        let sync = SyncEngine.shared
        ScrollView {
            VStack(spacing: 16) {
                if !sync.loggedIn {
                    VStack(spacing: 12) {
                        EmptyStateCard(symbol: "person.2.fill", title: "Привычки вместе — легче",
                                       subtitle: "Войди в аккаунт, создай круг и позови друзей или семью по ссылке. Будете видеть серии и поддерживать друг друга.")
                        LoginPanel { Task { await store.load() } }
                    }
                } else if !sync.moduleAvailable {
                    EmptyStateCard(symbol: "server.rack", title: "Нужен модуль на сервере",
                                   subtitle: "Запусти на VPS: sudo bash install-habitflow.sh — и круги друзей заработают.")
                } else {
                    if store.circles.isEmpty && !store.loading {
                        EmptyStateCard(symbol: "person.3.fill", title: "Пока нет кругов",
                                       subtitle: "Создай круг для семьи или друзей и отправь ссылку. По умолчанию друзья видят только полезные привычки — это меняется в настройках каждой привычки.")
                    }
                    ForEach(store.circles) { c in
                        CircleCard(circle: c, onMessage: { message = $0 })
                    }
                    HStack(spacing: 10) {
                        Button { text = ""; creating = true } label: {
                            Label("Создать круг", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .card(radius: 16)
                        }
                        Button { text = ""; joining = true } label: {
                            Label("Вступить по коду", systemImage: "number")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .card(radius: 16)
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .foregroundStyle(.primary)
                    if let e = store.error {
                        Text(e).font(.footnote).foregroundStyle(Palette.danger)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("Друзья")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .overlay { if store.loading && store.circles.isEmpty { ProgressView() } }
        .task { await store.load() }
        .alert("Новый круг", isPresented: $creating) {
            TextField("Например, Семья", text: $text)
            Button("Создать") { run { try await store.create(text.isEmpty ? "Друзья" : text) } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Код приглашения", isPresented: $joining) {
            TextField("ABC123", text: $text)
                .textInputAutocapitalization(.characters)
            Button("Вступить") { run { try await store.join(text) } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("HabitFlow", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await op(); Haptics.success() } catch { message = error.localizedDescription; Haptics.warning() }
            busy = false
        }
    }
}

private struct CircleCard: View {
    let circle: FriendCircle
    var onMessage: (String) -> Void
    @State private var confirmLeave = false
    @State private var kickTarget: FriendMember?

    private var store: FriendsStore { .shared }
    private var isOwner: Bool { circle.owner == SyncEngine.shared.userID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.name).font(.title3.weight(.bold))
                    Text("\(circle.members.count) \(plural(circle.members.count, "участник", "участника", "участников"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = store.inviteLink(circle) {
                    ShareLink(item: url, message: Text("Присоединяйся к моему кругу «\(circle.name)» в HabitFlow. Код: \(circle.code)")) {
                        Label("Пригласить", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(Appearance.shared.accent.opacity(0.16)))
                    }
                }
                Menu {
                    Button { UIPasteboard.general.string = circle.code; Haptics.success() } label: {
                        Label("Скопировать код \(circle.code)", systemImage: "doc.on.doc")
                    }
                    if isOwner {
                        Button { Task { try? await store.newCode(circle) } } label: { Label("Новый код", systemImage: "arrow.clockwise") }
                    }
                    Button(role: .destructive) { confirmLeave = true } label: { Label("Выйти из круга", systemImage: "rectangle.portrait.and.arrow.right") }
                } label: {
                    Image(systemName: "ellipsis").font(.headline).frame(width: 36, height: 36)
                }
            }
            ForEach(circle.members) { m in
                MemberRow(member: m, circle: circle, canKick: isOwner && !m.me, onKick: { kickTarget = m }, onMessage: onMessage)
                if m.id != circle.members.last?.id { Divider() }
            }
        }
        .padding(16)
        .card()
        .confirmationDialog("Выйти из «\(circle.name)»?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { try? await store.leave(circle) } }
        }
        .confirmationDialog("Убрать \(kickTarget?.name ?? "") из круга?", isPresented: Binding(get: { kickTarget != nil }, set: { if !$0 { kickTarget = nil } }), titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                if let m = kickTarget { Task { try? await store.kick(m, from: circle) } }
            }
        }
    }
}

private struct MemberRow: View {
    let member: FriendMember
    let circle: FriendCircle
    let canKick: Bool
    var onKick: () -> Void
    var onMessage: (String) -> Void
    @State private var sent = false
    @State private var bounce = 0

    var body: some View {
        let character = CompanionCatalog.character(member.companion)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: character?.tintHex ?? "4C8DFF").opacity(0.2))
                    if let character, member.stage > 0 {
                        PetArtwork(character: character).padding(5)
                    } else if character != nil {
                        Text("🥚").font(.title2)
                    } else {
                        Text(String(member.name.prefix(1))).font(.headline)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .symbolEffect(.bounce, value: bounce)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.me ? "\(member.name) (ты)" : member.name).font(.headline).lineLimit(1)
                        if member.level > 0 { LevelChip(level: member.level, tint: Color(hex: character?.tintHex ?? "4C8DFF")) }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !member.me {
                    Button { cheer() } label: {
                        Text(member.cheeredByMe || sent ? "👏 Отправлено" : "👏 Поддержать")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(Color.primary.opacity(member.cheeredByMe || sent ? 0.05 : 0.1)))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(member.cheeredByMe || sent)
                    .foregroundStyle(.primary)
                    .contextMenu {
                        ForEach(["🔥", "💪", "❤️", "🎉"], id: \.self) { e in
                            Button(e) { cheer(e) }
                        }
                        if canKick { Button("Убрать из круга", role: .destructive, action: onKick) }
                    }
                } else if member.cheersToday > 0 {
                    Text("👏 × \(member.cheersToday)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if !member.habits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(member.habits) { h in
                            HStack(spacing: 6) {
                                Image(systemName: h.symbol).font(.caption.weight(.bold))
                                    .foregroundStyle(Color(hex: h.colorHex))
                                Text(h.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text(h.kind == .build ? "🔥\(h.streak)" : "\(h.streak) д")
                                    .font(.caption.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(h.today ? Color(hex: h.colorHex) : Color.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background(Capsule().fill(Color(hex: h.colorHex).opacity(h.today ? 0.18 : 0.08)))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !member.companionName.isEmpty { parts.append("с напарником \(member.companionName)") }
        if let u = member.updated {
            parts.append(u.formatted(.relative(presentation: .named).locale(Locale(identifier: "ru_RU"))))
        }
        if member.cheersToday > 0 && !member.me { parts.append("👏 \(member.cheersToday) сегодня") }
        return parts.isEmpty ? "ещё не синхронизировался" : parts.joined(separator: " · ")
    }

    private func cheer(_ emoji: String = "👏") {
        sent = true
        bounce += 1
        Haptics.success()
        Task {
            do { try await FriendsStore.shared.cheer(member, in: circle, emoji: emoji) }
            catch { sent = false; onMessage(error.localizedDescription) }
        }
    }
}

// MARK: - Хлопки от друзей

struct CheersToast: View {
    let cheers: [SyncEngine.Cheer]
    var onClose: () -> Void

    var body: some View {
        let names = Array(Set(cheers.map(\.name))).prefix(3).joined(separator: ", ")
        let emoji = cheers.last?.emoji ?? "👏"
        HStack(spacing: 12) {
            Text(emoji).font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(cheers.count == 1 ? "\(names) поддерживает тебя!" : "Тебя поддержали: \(names)")
                    .font(.subheadline.weight(.semibold))
                Text("Так держать — друзья видят твои серии").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card(radius: 22)
        .padding(.horizontal, 16)
        .onTapGesture(perform: onClose)
        .task {
            try? await Task.sleep(for: .seconds(5))
            onClose()
        }
    }
}
