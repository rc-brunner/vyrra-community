import SwiftData
import SwiftUI

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var entries: [VocabularyEntry]
    @State private var searchText = ""
    @State private var editorState: VocabularyEditorState?

    let fixture: VisualFixture?

    init(fixture: VisualFixture? = nil) {
        self.fixture = fixture
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayEntries.isEmpty {
                    emptyState
                } else {
                    dictionaryList
                }
            }
            .navigationTitle("Terms")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VyrraIconButton(systemName: "plus", label: "Add term") {
                        editorState = .new
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search terms")
            .sheet(item: $editorState) { state in
                VocabularyEditSheet(state: state, save: save)
            }
        }
    }

    private var isFixtureMode: Bool {
        fixture == .dictionaryEmpty || fixture == .dictionaryPopulated
    }

    private var displayEntries: [VocabularyDisplayEntry] {
        let source: [VocabularyDisplayEntry]
        switch fixture {
        case .dictionaryEmpty:
            source = []
        case .dictionaryPopulated:
            source = VisualFixture.sampleVocabulary
        default:
            source = entries.map(VocabularyDisplayEntry.init(entry:))
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.spokenForm.localizedCaseInsensitiveContains(query)
                || $0.preferredText.localizedCaseInsensitiveContains(query)
                || $0.category.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DictionaryEmptyPanel {
                    editorState = .new
                }
            }
            .padding(20)
        }
        .background(VyrraTheme.pageBackground)
    }

    private var dictionaryList: some View {
        List {
            Section {
                ForEach(displayEntries) { entry in
                    Button {
                        editorState = .edit(entry)
                    } label: {
                        VocabularyRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editorState = .edit(entry)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            ClipboardService.copy(entry.preferredText)
                            HapticManager.completed()
                        } label: {
                            Label("Copy Preferred Text", systemImage: "doc.on.doc")
                        }

                        if !isFixtureMode {
                            Button(role: .destructive) {
                                delete(entry)
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
                Text("\(displayEntries.count) \(displayEntries.count == 1 ? "term" : "terms")")
                    .font(.caption.weight(.semibold))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VyrraTheme.pageBackground)
    }

    private func save(_ state: VocabularyEditorState, spokenForm: String, preferredText: String, category: VocabularyCategory, isEnabled: Bool) {
        guard let cleanSpoken = PersonalizationFormatter.normalizedOptional(spokenForm),
              let cleanPreferred = PersonalizationFormatter.normalizedOptional(preferredText)
        else {
            HapticManager.warning()
            return
        }

        if let entryID = state.entryID, let entry = entries.first(where: { $0.id == entryID }) {
            entry.spokenForm = cleanSpoken
            entry.preferredText = cleanPreferred
            entry.category = category
            entry.isEnabled = isEnabled
            entry.updatedAt = Date()
        } else {
            modelContext.insert(
                VocabularyEntry(
                    spokenForm: cleanSpoken,
                    preferredText: cleanPreferred,
                    category: category,
                    isEnabled: isEnabled
                )
            )
        }

        try? modelContext.save()
        HapticManager.completed()
    }

    private func delete(_ entry: VocabularyDisplayEntry) {
        guard let managedEntry = entries.first(where: { $0.id == entry.id }) else { return }
        modelContext.delete(managedEntry)
        try? modelContext.save()
        HapticManager.warning()
    }
}

private struct DictionaryEmptyPanel: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    let add: () -> Void

    var body: some View {
        VyrraPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 24, weight: .semibold))

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("No Terms Yet")
                        .font(.system(.title2, design: .rounded, weight: .semibold))

                    Text("Add names, acronyms, and words that should be spelled your way.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: add) {
                    Label("Add Term", systemImage: "plus")
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

private struct VocabularyRow: View {
    let entry: VocabularyDisplayEntry

    var body: some View {
        VyrraPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(entry.isEnabled ? VyrraTheme.success : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(entry.spokenForm) -> \(entry.preferredText)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(entry.category.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Text(entry.isEnabled ? "Enabled" : "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct VocabularyEditorState: Identifiable {
    let id = UUID()
    let entryID: UUID?
    let spokenForm: String
    let preferredText: String
    let category: VocabularyCategory
    let isEnabled: Bool

    static var new: VocabularyEditorState {
        VocabularyEditorState(
            entryID: nil,
            spokenForm: "",
            preferredText: "",
            category: .custom,
            isEnabled: true
        )
    }

    static func edit(_ entry: VocabularyDisplayEntry) -> VocabularyEditorState {
        VocabularyEditorState(
            entryID: entry.id,
            spokenForm: entry.spokenForm,
            preferredText: entry.preferredText,
            category: entry.category,
            isEnabled: entry.isEnabled
        )
    }
}

private struct VocabularyEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spokenForm: String
    @State private var preferredText: String
    @State private var category: VocabularyCategory
    @State private var isEnabled: Bool

    let state: VocabularyEditorState
    let save: (VocabularyEditorState, String, String, VocabularyCategory, Bool) -> Void

    init(
        state: VocabularyEditorState,
        save: @escaping (VocabularyEditorState, String, String, VocabularyCategory, Bool) -> Void
    ) {
        self.state = state
        self.save = save
        _spokenForm = State(initialValue: state.spokenForm)
        _preferredText = State(initialValue: state.preferredText)
        _category = State(initialValue: state.category)
        _isEnabled = State(initialValue: state.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What you might say", text: $spokenForm)
                        .textInputAutocapitalization(.never)
                    TextField("Preferred text", text: $preferredText)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Word")
                } footer: {
                    Text("Example: say \"runner concepts\" and save \"Runner Concepts\".")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(VocabularyCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Type")
                }
            }
            .navigationTitle(state.entryID == nil ? "Add Word" : "Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(state, spokenForm, preferredText, category, isEnabled)
                        dismiss()
                    }
                    .disabled(PersonalizationFormatter.normalizedOptional(spokenForm) == nil || PersonalizationFormatter.normalizedOptional(preferredText) == nil)
                }
            }
        }
    }
}

#Preview {
    DictionaryView(fixture: .dictionaryPopulated)
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
