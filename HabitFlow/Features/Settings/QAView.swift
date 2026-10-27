import SwiftUI
import SwiftData

/// Проверка данных на логические нестыковки. Для владельца приложения: показывает, где расчёты расходятся.
struct QAView: View {
    @Environment(\.modelContext) private var context
    @Query private var habits: [Habit]
    @State private var report: QAReport?
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    report = QAService.run(habits: habits, context: context)
                    Haptics.selection()
                } label: {
                    Label("Проверить данные", systemImage: "checkmark.shield")
                }
            } footer: {
                Text("Сверяет серии, опыт, цели дня и резервную копию. Ничего не меняет.")
            }

            if let report {
                Section {
                    HStack {
                        Image(systemName: report.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(report.isClean ? Palette.success : Palette.warning)
                        Text(report.summary).font(.headline)
                    }
                    Text("Проверено привычек: \(report.habitsChecked)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !report.issues.isEmpty {
                    Section("Замечания") {
                        ForEach(report.issues) { issue in
                            issueRow(issue)
                        }
                    }
                    Section {
                        Button {
                            UIPasteboard.general.string = report.json()
                            copied = true
                            Haptics.success()
                        } label: {
                            Label(copied ? "Скопировано" : "Скопировать отчёт (JSON)", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .navigationTitle("Проверка данных")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if report == nil { report = QAService.run(habits: habits, context: context) } }
    }

    private func issueRow(_ i: QAIssue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon(i.severity))
                    .foregroundStyle(color(i.severity))
                Text(i.code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                if let h = i.habit {
                    Text("«\(h)»").font(.caption.weight(.semibold)).lineLimit(1)
                }
            }
            Text(i.message).font(.subheadline)
            Text(i.hint).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func icon(_ s: QASeverity) -> String {
        switch s {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(_ s: QASeverity) -> Color {
        switch s {
        case .error: Palette.danger
        case .warning: Palette.warning
        case .info: .secondary
        }
    }
}
