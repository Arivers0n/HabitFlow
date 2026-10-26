import SwiftUI
import SwiftData

/// Выбор напарника: карусель персонажей на стеклянных подставках.
/// Показывается при первом запуске и по кнопке «Сменить напарника».
struct CompanionPicker: View {
    var isOnboarding: Bool
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Habit]

    @State private var selected: String?
    @State private var userName = CompanionManager.shared.state.userName
    @FocusState private var nameFocused: Bool

    private var current: CompanionCharacter {
        CompanionCatalog.character(selected) ?? CompanionCatalog.all[0]
    }

    var body: some View {
        let tint = Color(hex: current.tintHex)
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(isOnboarding ? "Позже" : "Закрыть") {
                        if isOnboarding { CompanionManager.shared.skipOnboarding() }
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                }

                VStack(spacing: 6) {
                    Text(isOnboarding ? "Выбери напарника" : "Сменить напарника")
                        .font(.largeTitle.weight(.bold))
                    Text(isOnboarding
                         ? "Он будет расти вместе с твоими привычками и поддержит, если что-то пойдёт не так."
                         : "Опыт, уровень и подарки сохранятся — их заработал ты.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(CompanionCatalog.all) { c in
                            PickerCard(character: c, isSelected: c.id == current.id)
                                .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.74, 340) }
                                .scrollTransition(.interactive) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .opacity(phase.isIdentity ? 1 : 0.5)
                                        .rotation3DEffect(.degrees(phase.value * -22), axis: (x: 0, y: 1, z: 0))
                                }
                                .id(c.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 48, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selected)
                .onChange(of: selected) { _, _ in Haptics.selection() }
                .frame(maxHeight: .infinity)

                PageDots(count: CompanionCatalog.all.count,
                         index: CompanionCatalog.all.firstIndex { $0.id == current.id } ?? 0,
                         tint: tint)
                    .padding(.vertical, 10)

                VStack(spacing: 12) {
                    TextField("Как тебя называть? (необязательно)", text: $userName)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .card(radius: 16)

                    Button {
                        let level = LevelProgress(xp: CompanionEngine().xp(all.map(\.snapshot)).total).level
                        CompanionManager.shared.choose(current, userName: userName, currentLevel: level)
                        dismiss()
                    } label: {
                        Text("Выбрать: \(current.name)")
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: tint))
                    .animation(Motion.smooth, value: current.id)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            if selected == nil { selected = CompanionManager.shared.state.characterID ?? CompanionCatalog.all[0].id }
        }
        .onTapGesture { nameFocused = false }
    }
}

private struct PickerCard: View {
    let character: CompanionCharacter
    let isSelected: Bool

    var body: some View {
        let tint = Color(hex: character.tintHex)
        VStack(spacing: 10) {
            CompanionScene(config: SceneConfig(character: character, stage: .adult,
                                               mood: isSelected ? .happy : .calm, decor: []),
                           size: 230)
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(character.name).font(.title2.weight(.bold))
                    if character.original {
                        Text("новый")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(tint.gradient))
                    }
                }
                Text(character.species)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                Text(character.trait)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .card(radius: 30, tint: tint)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? tint : Color.primary.opacity(0.2))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Motion.smooth, value: index)
    }
}
