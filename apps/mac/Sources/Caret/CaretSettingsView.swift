import SwiftUI

struct CaretSettingsView: View {
    @ObservedObject var model: Model
    @State private var tab: SettingsTab = .memories
    @State private var selectedSkillNoteID: String?
    @State private var selectedMemoryNoteID: String?

    private let accentBlue = Color(red: 0.26, green: 0.52, blue: 0.98)

    enum SettingsTab: String, CaseIterable, Identifiable {
        case memories = "Memories"
        case skills = "Skills"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .memories: return "tray.full"
            case .skills: return "wand.and.stars"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Section", selection: $tab) {
                ForEach(SettingsTab.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Group {
                switch tab {
                case .memories:
                    notesSplit(
                        notes: model.memoryNotes,
                        selection: $selectedMemoryNoteID,
                        emptyTitle: "No memory notes",
                        emptyDescription: "Add markdown notes under caret/notes/memories/*.md"
                    )
                case .skills:
                    notesSplit(
                        notes: model.skillNotes,
                        selection: $selectedSkillNoteID,
                        emptyTitle: "No skill notes",
                        emptyDescription: "Add markdown notes under caret/notes/skills/*.md"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 640, height: 480)
        .onAppear {
            model.reloadNotes()
            if selectedSkillNoteID == nil {
                selectedSkillNoteID = model.skillNotes.first?.id
            }
            if selectedMemoryNoteID == nil {
                selectedMemoryNoteID = model.memoryNotes.first?.id
            }
        }
        .onChange(of: model.skillNotes) { _, notes in
            if selectedSkillNoteID == nil || !notes.contains(where: { $0.id == selectedSkillNoteID }) {
                selectedSkillNoteID = notes.first?.id
            }
        }
        .onChange(of: model.memoryNotes) { _, notes in
            if selectedMemoryNoteID == nil || !notes.contains(where: { $0.id == selectedMemoryNoteID }) {
                selectedMemoryNoteID = notes.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accentBlue))
            VStack(alignment: .leading, spacing: 2) {
                Text("Caret")
                    .font(.title2.weight(.semibold))
                Text("Notes that power skills and personal context")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func notesSplit(
        notes: [CaretNote],
        selection: Binding<String?>,
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        if notes.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "doc.text", description: Text(emptyDescription))
        } else {
            NavigationSplitView {
                List(notes, selection: selection) { note in
                    NoteRow(note: note, showApps: tab == .memories)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            } detail: {
                if let id = selection.wrappedValue, let note = notes.first(where: { $0.id == id }) {
                    NoteDetailView(note: note, showApps: tab == .memories, accentBlue: accentBlue)
                } else {
                    ContentUnavailableView("Select a note", systemImage: "doc.text")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Accessibility Settings") {
                model.onOpenAccessibility?()
            }
            Button("Reconnect Accessibility…") {
                model.onReconnectAccessibility?()
            }
            Spacer()
            Text(model.accessibilityConnected ? "Accessibility connected" : "Accessibility not connected")
                .font(.caption)
                .foregroundStyle(model.accessibilityConnected ? .green : .orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }
}

private struct NoteRow: View {
    let note: CaretNote
    let showApps: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: note.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.85)))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showApps, !note.apps.isEmpty {
                    Text(note.apps.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .tag(note.id)
    }
}

private struct NoteDetailView: View {
    let note: CaretNote
    let showApps: Bool
    let accentBlue: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: note.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(accentBlue))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.title2.weight(.semibold))
                        Text("Updated \(note.updatedAt.formatted(date: .complete, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if showApps, !note.apps.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(note.apps, id: \.self) { app in
                            Text(app)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                }

                Divider()

                Text(note.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
    }
}

/// Simple horizontal wrapping row for app chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
