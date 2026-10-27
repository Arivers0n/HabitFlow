import SwiftUI

// MARK: - Кнопки входа

struct GoogleG: View {
    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width, g.size.height)
            let lw = w * 0.2
            ZStack {
                seg(0, 0.125, Color(red: 0.26, green: 0.52, blue: 0.96), lw)
                seg(0.125, 0.375, Color(red: 0.20, green: 0.66, blue: 0.33), lw)
                seg(0.375, 0.556, Color(red: 0.98, green: 0.74, blue: 0.02), lw)
                seg(0.556, 0.875, Color(red: 0.92, green: 0.26, blue: 0.21), lw)
                Rectangle().fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: (w - lw) / 2, height: lw)
                    .offset(x: (w - lw) / 4)
            }
            .padding(lw / 2)
            .frame(width: w, height: w)
        }
    }

    private func seg(_ a: CGFloat, _ b: CGFloat, _ c: Color, _ lw: CGFloat) -> some View {
        Circle().trim(from: a, to: b).stroke(c, style: StrokeStyle(lineWidth: lw))
    }
}

/// «Войти через …» в фирменном стиле сервиса.
struct OAuthButton: View {
    let provider: String
    let busy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(fg) } else { logo }
                Text(title).font(.body.weight(.semibold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(provider == "google" ? 0.14 : 0)))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .disabled(busy)
    }

    private var title: String {
        switch provider {
        case "apple": "Войти через Apple"
        case "yandex": "Войти с Яндекс ID"
        default: "Войти через Google"
        }
    }

    private var bg: Color {
        switch provider {
        case "apple": scheme == .dark ? .white : .black
        case "yandex": Color(red: 0.99, green: 0.24, blue: 0.13)
        default: scheme == .dark ? Color(white: 0.14) : .white
        }
    }

    private var fg: Color {
        switch provider {
        case "apple": scheme == .dark ? .black : .white
        case "yandex": .white
        default: .primary
        }
    }

    @ViewBuilder private var logo: some View {
        switch provider {
        case "apple":
            Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
        case "yandex":
            Text("Я").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.99, green: 0.24, blue: 0.13))
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
        default:
            GoogleG().frame(width: 20, height: 20)
        }
    }
}

// MARK: - Панель входа (общая для приветствия и настроек)

struct LoginPanel: View {
    var onDone: () -> Void

    @State private var providers: [String] = []
    @State private var loadingProviders = true
    @State private var busy: String?
    @State private var error: String?
    @State private var showEmail = false
    @State private var register = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showServer = false
    @State private var serverText = SyncEngine.shared.server
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, server }

    private var sync: SyncEngine { .shared }

    var body: some View {
        VStack(spacing: 12) {
            if loadingProviders {
                ProgressView().frame(height: 52)
            }
            ForEach(providers, id: \.self) { p in
                OAuthButton(provider: p, busy: busy == p) { oauth(p) }
            }

            if showEmail {
                emailForm.transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(Motion.smooth) { showEmail = true }
                    focus = .email
                } label: {
                    Label("Почта и пароль", systemImage: "envelope.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .card(radius: 16)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .foregroundStyle(.primary)
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            DisclosureGroup(isExpanded: $showServer) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://сервер", text: $serverText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focus, equals: .server)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .card(radius: 14)
                        .onSubmit { reloadProviders() }
                    Text("Тот же сервер, что у Копилки, — аккаунт общий. Менять адрес нужно, только если у вас свой сервер.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Проверить сервер") { reloadProviders() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.top, 6)
            } label: {
                Text("Сервер").font(.footnote).foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
        .animation(Motion.smooth, value: error)
        .task { await loadProviders() }
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            Picker("", selection: $register.animation(Motion.smooth)) {
                Text("Вход").tag(false)
                Text("Регистрация").tag(true)
            }
            .pickerStyle(.segmented)

            if register {
                field("Имя", text: $name, field: .name, content: .name)
            }
            field("Почта", text: $email, field: .email, content: .emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            SecureField(register ? "Пароль (от 8 символов)" : "Пароль", text: $password)
                .textContentType(register ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .card(radius: 14)

            Button(action: submit) {
                HStack {
                    if busy == "email" { ProgressView().tint(.white) }
                    Text(register ? "Создать аккаунт" : "Войти")
                }
            }
            .buttonStyle(PrimaryButtonStyle(color: Appearance.shared.accent))
            .disabled(busy != nil || email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
        }
    }

    private func field(_ title: String, text: Binding<String>, field: Field, content: UITextContentType) -> some View {
        TextField(title, text: text)
            .textContentType(content)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(.next)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .card(radius: 14)
    }

    private func reloadProviders() {
        focus = nil
        Task { await loadProviders() }
    }

    private func loadProviders() async {
        loadingProviders = true
        let base = SyncEngine.normalize(serverText)
        let found = await sync.oauthProviders(base)
        let order = ["apple", "google", "yandex"]
        withAnimation(Motion.smooth) {
            providers = order.filter { found[$0] != nil }
            loadingProviders = false
        }
        if found.isEmpty, !(await sync.ping(base)) {
            error = "Сервер не отвечает. Проверьте интернет или адрес сервера."
        } else {
            error = nil
        }
    }

    private func oauth(_ p: String) {
        busy = p
        error = nil
        Task {
            do {
                try await sync.loginWithOAuth(p, server: serverText)
                Haptics.success()
                onDone()
            } catch let e as SyncEngine.APIError where e.status == -1 {
                // отменили — ничего не говорим
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
            busy = nil
        }
    }

    private func submit() {
        guard busy == nil, !email.isEmpty, !password.isEmpty else { return }
        if register && password.count < 8 {
            error = "Пароль — минимум 8 символов"
            return
        }
        busy = "email"
        error = nil
        focus = nil
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            do {
                if register {
                    try await sync.register(server: serverText, name: name.trimmingCharacters(in: .whitespaces),
                                            email: mail, password: password)
                } else {
                    try await sync.login(server: serverText, email: mail, password: password)
                }
                Haptics.success()
                onDone()
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
            busy = nil
        }
    }
}

// MARK: - Приветствие при первом запуске

struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 30)
                    AppMark()
                        .frame(width: 120, height: 120)
                        .scaleEffect(appear ? 1 : 0.7)
                        .opacity(appear ? 1 : 0)
                    VStack(spacing: 8) {
                        Text("HabitFlow")
                            .font(.largeTitle.weight(.bold))
                        Text("Полезные привычки, свобода от вредных и напарник, который растёт вместе с тобой.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                    VStack(alignment: .leading, spacing: 10) {
                        perk("arrow.triangle.2.circlepath", "Синхронизация iPhone и iPad")
                        perk("sparkles", "ИИ-напарник: советы, разбор срывов, привычки из текста")
                        perk("person.2.fill", "Круги с друзьями и семьёй")
                    }
                    .padding(16)
                    .card(radius: 22)
                    .opacity(appear ? 1 : 0)

                    LoginPanel(onDone: onFinish)

                    Button("Продолжить без аккаунта", action: onFinish)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                    Text("Аккаунт общий с Копилкой. Без входа всё работает на этом устройстве, войти можно позже в настройках.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { withAnimation(Motion.bouncy ?? .default) { appear = true } }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Appearance.shared.accent)
                .frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}

/// Анимированный знак приложения: кольцо с галочкой.
struct AppMark: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !Motion.enabled)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "5B6CFF").opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: 70))
                    .scaleEffect(1 + 0.05 * sin(t * 1.4))
                Circle()
                    .trim(from: 0.04, to: 0.88)
                    .stroke(AngularGradient(colors: [Color(hex: "4C8DFF"), Color(hex: "B65CFF"), Color(hex: "4C8DFF")],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-60 + 8 * sin(t * 0.9)))
                    .padding(18)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
        }
    }
}

// MARK: - Аккаунт в настройках

struct AccountSettingsView: View {
    @State private var confirmLogout = false

    var body: some View {
        let sync = SyncEngine.shared
        Form {
            if sync.loggedIn {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Appearance.shared.accent.gradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sync.userName.isEmpty ? "Аккаунт" : sync.userName).font(.headline)
                            if !sync.userEmail.isEmpty {
                                Text(sync.userEmail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Text("Состояние")
                        Spacer()
                        statusLabel(sync)
                    }
                    if let last = sync.lastSync {
                        HStack {
                            Text("Последняя")
                            Spacer()
                            Text(last.formatted(.relative(presentation: .named).locale(Locale(identifier: "ru_RU"))))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await sync.sync() }
                    } label: {
                        Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(sync.state == .syncing)
                } header: {
                    Text("Синхронизация")
                } footer: {
                    if !sync.moduleAvailable {
                        Text("На сервере пока нет модуля HabitFlow. Вход и ИИ работают, а синхронизация и друзья включатся после команды на сервере: sudo bash install-habitflow.sh (файл в папке server репозитория).")
                    } else {
                        Text("Привычки, отметки, срывы, напарник и оформление синхронизируются между вашими устройствами.")
                    }
                }

                Section {
                    HStack {
                        Text("Сервер")
                        Spacer()
                        Text(URL(string: sync.server)?.host ?? sync.server)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Выйти", role: .destructive) { confirmLogout = true }
                }
            } else {
                Section {
                    VStack(spacing: 12) {
                        Text("Войдите, чтобы синхронизировать iPhone и iPad, пользоваться ИИ без своего ключа и добавлять друзей.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LoginPanel { }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Аккаунт общий с Копилкой: можно войти тем же способом.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Аккаунт")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { sync.logout(); Haptics.tap() }
        } message: {
            Text("Привычки останутся на этом устройстве и снова синхронизируются при входе.")
        }
    }

    @ViewBuilder
    private func statusLabel(_ sync: SyncEngine) -> some View {
        switch sync.state {
        case .syncing:
            HStack(spacing: 6) { ProgressView(); Text("Синхронизация…") }.foregroundStyle(.secondary)
        case .error(let m):
            Text(m).foregroundStyle(Palette.danger).lineLimit(2).multilineTextAlignment(.trailing)
        case .idle:
            Label(sync.moduleAvailable ? "Включена" : "Ждёт сервер", systemImage: sync.moduleAvailable ? "checkmark.icloud.fill" : "icloud.slash")
                .foregroundStyle(sync.moduleAvailable ? Palette.success : .secondary)
        case .off:
            Text("Выключена").foregroundStyle(.secondary)
        }
    }
}
