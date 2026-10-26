import SwiftUI

/// Своя библиотека причин срывов.
struct TriggersView: View {
    @State private var editing: TriggerItem?
    @State private var creating = false
    @State private var confirmReset = false

    var body: some View {
        let lib = TriggerLibrary.shared
        List {
            Section {
                ForEach(lib.items) { item in
                    Button { editing = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.danger)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Palette.danger.opacity(0.14)))
                            Text(item.name).foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { lib.items.remove(atOffsets: $0) }
                .onMove { lib.items.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Эти причины предлагаются при записи срыва. Свайп влево — удалить, «Изменить» — поменять порядок. Старые записи о срывах не меняются.")
            }

            Section {
                Button { creating = true } label: { Label("Добавить причину", systemImage: "plus") }
                Button("Вернуть стандартные", role: .destructive) { confirmReset = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Причины срывов")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $editing) { item in
            TriggerEditor(item: item) { updated in
                if let i = lib.items.firstIndex(where: { $0.id == updated.id }) { lib.items[i] = updated }
            }
        }
        .sheet(isPresented: $creating) {
            TriggerEditor(item: TriggerItem(name: "", symbol: "questionmark.circle")) { lib.items.append($0) }
        }
        .confirmationDialog("Вернуть стандартный список?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Вернуть", role: .destructive) { lib.resetToDefaults() }
        }
    }
}

private struct TriggerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: TriggerItem
    var onSave: (TriggerItem) -> Void

    private let symbols = ["bolt.heart.fill", "hourglass", "person.3.fill", "zzz", "party.popper.fill", "cloud.rain.fill",
                           "fork.knife", "flame.fill", "arrow.triangle.2.circlepath", "wineglass.fill", "briefcase.fill", "car.fill",
                           "house.fill", "moon.fill", "sun.max.fill", "iphone", "music.note", "heart.slash.fill",
                           "exclamationmark.triangle.fill", "questionmark.circle", "cup.and.saucer.fill", "gamecontroller.fill", "cart.fill", "bubble.left.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, «Ссора»", text: $item.name)
                }
                Section("Значок") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(symbols, id: \.self) { s in
                            Button { item.symbol = s; Haptics.selection() } label: {
                                Image(systemName: s)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(item.symbol == s ? Color.white : Color.primary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(item.symbol == s ? AnyShapeStyle(Palette.danger.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
                                    )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(item.name.isEmpty ? "Новая причина" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        item.name = item.name.trimmingCharacters(in: .whitespaces)
                        onSave(item)
                        dismiss()
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
