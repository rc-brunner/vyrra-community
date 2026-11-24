import SwiftData
import SwiftUI

struct SnippetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnippetEntry.createdAt, order: .reverse) private var snippets: [SnippetEntry]
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var vocabulary: [VocabularyEntry]
    @State private var searchText = ""
    @State private var editorState: SnippetEditorState?

    let fixture: VisualFixture?

    init(fixture: VisualFixture? = nil) {
        self.fixture = fixture
    }

    var body: some View {
        NavigationStack {
            Group {
                if displaySnippets.isEmpty {
                    emptyState
                } else {
                    snippetsList
                }
            }
            .navigationTitle("Shortcuts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VyrraIconButton(systemName: "plus", label: "Add shortcut") {
                        editorState = .new
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search shortcuts")
            .sheet(item: $editorState) { state in
                SnippetEditSheet(state: state, conflictingTriggers: conflictingTriggers(for: state), save: save)
            }
        }
    }

    private var isFixtureMode: Bool {
        fixture == .snippetsEmpty || fixture == .snippetsPopulated
    }

    private var displaySnippets: [SnippetDisplayEntry] {
        let source: [SnippetDisplayEntry]
        switch fixture {
        case .snippetsEmpty:
            source = []
        case .snippetsPopulated:
            source = VisualFixture.sampleSnippets
        default:
            source = snippets.map(SnippetDisplayEntry.init(entry:))
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SnippetEducationPanel {
                    editorState = .new
                }
            }
            .padding(20)
        }
        .background(VyrraTheme.pageBackground)
    }

    private var snippetsList: some View {
        List {
            Section {
                SnippetEducationPanel {
                    editorState = .new
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(displaySnippets) { snippet in
                    Button {
                        editorState = .edit(snippet)
                    } label: {
                        SnippetRow(snippet: snippet)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editorState = .edit(snippet)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            ClipboardService.copy(snippet.body)
                            HapticManager.completed()
                        } label: {
                            Label("Copy Body", systemImage: "doc.on.doc")
                        }

                        if !isFixtureMode {
                            Button(role: .destructive) {
                                delete(snippet)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } header: {
                // The List header style already applies secondary color.
                Text("Your shortcuts (\(displaySnippets.count))")
                    .font(.caption.weight(.semibold))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VyrraTheme.pageBackground)
    }

    private func save(_ state: SnippetEditorState, trigger: String, body: String, isEnabled: Bool) {
        guard let cleanTrigger = PersonalizationFormatter.normalizedOptional(trigger),
              let cleanBody = PersonalizationFormatter.normalizedOptional(body)
        else {
            HapticManager.warning()
            return
        }

        if let snippetID = state.snippetID, let snippet = snippets.first(where: { $0.id == snippetID }) {
            snippet.trigger = cleanTrigger
            snippet.body = cleanBody
            snippet.isEnabled = isEnabled
            snippet.updatedAt = Date()
        } else {
            modelContext.insert(
                SnippetEntry(
                    trigger: cleanTrigger,
                    body: cleanBody,
                    isEnabled: isEnabled
                )
            )
        }

        try? modelContext.save()
        HapticManager.completed()
    }

    private func delete(_ snippet: SnippetDisplayEntry) {
        guard let managedSnippet = snippets.first(where: { $0.id == snippet.id }) else { return }
        modelContext.delete(managedSnippet)
        try? modelContext.save()
        HapticManager.warning()
    }

    private func conflictingTriggers(for state: SnippetEditorState) -> Set<String> {
        let otherSnippetTriggers = snippets
            .filter { $0.id != state.snippetID }
            .map { PersonalizationFormatter.normalizedSnippetTrigger($0.trigger) }

        let vocabularyTriggers = vocabulary
            .map { PersonalizationFormatter.normalizedSnippetTrigger($0.spokenForm) }

        return Set(otherSnippetTriggers + vocabularyTriggers).filter { !$0.isEmpty }
    }
}

private struct SnippetEducationPanel: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    let add: () -> Void

    var body: some View {
        VyrraPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24, weight: .semibold))

                    Spacer()

                    VyrraStatusPill(title: "Exact", icon: "target", tint: .secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Save What You Repeat")
                        .font(.system(.title2, design: .rounded, weight: .semibold))

                    Text("Save text you say often.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: add) {
                    Label("Add Shortcut", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: SnippetDisplayEntry

    var body: some View {
        VyrraPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: snippet.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(snippet.isEnabled ? VyrraTheme.success : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(snippet.trigger) ->")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(snippet.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(snippet.isEnabled ? "Enabled" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SnippetEditorState: Identifiable {
    let id = UUID()
    let snippetID: UUID?
    let trigger: String
    let body: String
    let isEnabled: Bool

    static var new: SnippetEditorState {
        SnippetEditorState(snippetID: nil, trigger: "", body: "", isEnabled: true)
    }

    static func edit(_ snippet: SnippetDisplayEntry) -> SnippetEditorState {
        SnippetEditorState(
            snippetID: snippet.id,
            trigger: snippet.trigger,
            body: snippet.body,
            isEnabled: snippet.isEnabled
        )
    }
}

private struct SnippetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansionBody: String
    @State private var isEnabled: Bool

    let state: SnippetEditorState
    let conflictingTriggers: Set<String>
    let save: (SnippetEditorState, String, String, Bool) -> Void

    init(
        state: SnippetEditorState,
        conflictingTriggers: Set<String>,
        save: @escaping (SnippetEditorState, String, String, Bool) -> Void
    ) {
        self.state = state
        self.conflictingTriggers = conflictingTriggers
        self.save = save
        _trigger = State(initialValue: state.trigger)
        _expansionBody = State(initialValue: state.body)
        _isEnabled = State(initialValue: state.isEnabled)
    }

    private var normalizedTrigger: String {
        PersonalizationFormatter.normalizedSnippetTrigger(trigger)
    }

    private var hasConflict: Bool {
        conflictingTriggers.contains(normalizedTrigger)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Phrase to say", text: $trigger)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Trigger")
                } footer: {
                    Text(hasConflict ? "This trigger overlaps with another shortcut or term." : "Say this exact phrase to expand the shortcut.")
                }

                Section {
                    TextEditor(text: $expansionBody)
                        .frame(minHeight: 130)
                } header: {
                    Text("Expansion")
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle(state.snippetID == nil ? "Add Shortcut" : "Edit Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(state, trigger, expansionBody, isEnabled)
                        dismiss()
                    }
                    .disabled(
                        PersonalizationFormatter.normalizedOptional(trigger) == nil
                            || PersonalizationFormatter.normalizedOptional(expansionBody) == nil
                            || hasConflict
                    )
                }
            }
        }
    }
}

#Preview {
    SnippetsView(fixture: .snippetsPopulated)
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
