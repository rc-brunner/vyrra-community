import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionRecord.createdAt, order: .reverse) private var records: [TranscriptionRecord]
    @Query(sort: \NoteFolder.createdAt, order: .forward) private var folders: [NoteFolder]
    @State private var copiedRecordID: UUID?
    @State private var showsClearConfirmation = false
    @State private var showsNewFolderSheet = false
    @State private var showsFolderDeleteConfirmation = false
    @State private var renameTarget: HistoryDisplayRecord?
    @State private var editTranscriptTarget: HistoryDisplayRecord?
    @State private var tagTarget: HistoryDisplayRecord?
    @State private var moveTarget: HistoryDisplayRecord?
    @State private var folderRenameTarget: HistoryFolderSummary?
    @State private var folderDeleteTarget: HistoryFolderSummary?
    @State private var selectedFolderName: String?
    @State private var selectedDateFilter = HistoryDateFilter.all
    @State private var detailTarget: HistoryDisplayRecord?
    @State private var sharePayload: HistorySharePayload?
    @State private var searchText = ""

    let fixture: VisualFixture?

    init(fixture: VisualFixture? = nil) {
        self.fixture = fixture
    }

    var body: some View {
        NavigationStack {
            Group {
                if fixture == .historyDetail, let record = displayRecords.first {
                    HistoryDetailView(record: record, copy: copy, edit: { _ in }, tag: { _ in }, share: { _ in })
                } else if displayRecords.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
            .toolbar {
                if !displayRecords.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showsNewFolderSheet = true
                            } label: {
                                Label("New Folder", systemImage: "folder.badge.plus")
                            }

                            Button(role: .destructive) {
                                showsClearConfirmation = true
                            } label: {
                                Label {
                                    Text("Clear All")
                                } icon: {
                                    Image(systemName: "trash")
                                        .symbolRenderingMode(.monochrome)
                                }
                                .foregroundStyle(VyrraTheme.danger)
                            }
                            .tint(VyrraTheme.danger)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .accessibilityLabel("Library actions")
                    }
                }
            }
            .confirmationDialog("Clear all notes?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Clear All", role: .destructive, action: clearAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all notes from Library.")
            }
            .confirmationDialog("Delete folder?", isPresented: $showsFolderDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Folder", role: .destructive) {
                    if let folderDeleteTarget {
                        deleteFolder(folderDeleteTarget)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let folderDeleteTarget {
                    Text("Notes in \(folderDeleteTarget.name) move back to Inbox.")
                }
            }
            .sheet(isPresented: $showsNewFolderSheet) {
                HistoryTextEditSheet(
                    title: "New Folder",
                    fieldTitle: "Folder Name",
                    initialText: "",
                    placeholder: "Projects",
                    saveTitle: "Create"
                ) { value in
                    createFolder(named: value)
                }
            }
            .sheet(item: $renameTarget) { record in
                HistoryTextEditSheet(
                    title: "Rename Transcript",
                    fieldTitle: "Title",
                    initialText: record.title ?? record.displayTitle,
                    placeholder: record.displayTitle,
                    saveTitle: "Rename"
                ) { value in
                    rename(record, title: value)
                }
            }
            .sheet(item: $editTranscriptTarget) { record in
                HistoryTranscriptEditSheet(
                    title: "Edit Transcript",
                    initialText: record.polishedText
                ) { value in
                    editTranscript(record, text: value)
                }
            }
            .sheet(item: $tagTarget) { record in
                HistoryTextEditSheet(
                    title: "Tags",
                    fieldTitle: "Tags",
                    initialText: record.tagsText ?? "",
                    placeholder: "work, follow-up",
                    saveTitle: "Save",
                    fieldAutocapitalization: .never,
                    footer: "Separate tags with commas or spaces."
                ) { value in
                    updateTags(record, tagsText: value)
                }
            }
            .sheet(item: $moveTarget) { record in
                HistoryMoveSheet(
                    record: record,
                    folders: folderSummaries,
                    recommendedFolders: recommendedFolders(for: record),
                    moveToFolder: { folder in
                        move(record, sectionName: folder.isSystemFolder ? "" : folder.name)
                    },
                    createAndMove: { value in
                        move(record, sectionName: value)
                    }
                )
            }
            .sheet(item: $folderRenameTarget) { folder in
                HistoryTextEditSheet(
                    title: "Rename Folder",
                    fieldTitle: "Folder Name",
                    initialText: folder.name,
                    placeholder: folder.name,
                    saveTitle: "Rename"
                ) { value in
                    renameFolder(folder, to: value)
                }
            }
            .sheet(item: $sharePayload) { payload in
                HistoryActivityView(activityItems: payload.items)
            }
            .navigationDestination(item: $detailTarget) { record in
                HistoryDetailView(record: record, copy: copy, edit: { editTranscriptTarget = $0 }, tag: { tagTarget = $0 }, share: share)
            }
        }
    }

    private var isFixtureMode: Bool {
        fixture == .historySingle || fixture == .historyPopulated || fixture == .historyDetail
    }

    private var displayRecords: [HistoryDisplayRecord] {
        switch fixture {
        case .historySingle:
            VisualFixture.sampleSingleHistory
        case .historyPopulated, .historyDetail:
            VisualFixture.sampleHistory
        case .historyEmpty:
            []
        default:
            records.map(HistoryDisplayRecord.init(record:))
        }
    }

    private var displaySections: [(name: String, records: [HistoryDisplayRecord])] {
        let groupedRecords = Dictionary(grouping: filteredDisplayRecords, by: \.displaySectionName)
        return groupedRecords.keys.sorted(by: sectionSort).map { name in
            (name, groupedRecords[name] ?? [])
        }
    }

    private var filteredDisplayRecords: [HistoryDisplayRecord] {
        let folderFilteredRecords = if let selectedFolderName {
            displayRecords.filter { $0.displaySectionName == selectedFolderName }
        } else {
            displayRecords
        }

        let dateFilteredRecords = folderFilteredRecords.filter { selectedDateFilter.includes($0.createdAt) }
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearch.isEmpty else { return dateFilteredRecords }

        return dateFilteredRecords.filter { $0.matchesSearch(normalizedSearch) }
    }

    private var folderSummaries: [HistoryFolderSummary] {
        var names = Set([HistoryRecordFormatter.defaultSectionName])
        for folder in folders {
            if let name = HistoryRecordFormatter.normalizedOptional(folder.name) {
                names.insert(name)
            }
        }
        for record in displayRecords {
            names.insert(record.displaySectionName)
        }

        return names.sorted(by: sectionSort).map { name in
            let folderRecords = displayRecords.filter { $0.displaySectionName == name }
            let latestDate = folderRecords.map(\.createdAt).max()
            return HistoryFolderSummary(
                name: name,
                count: folderRecords.count,
                latestDate: latestDate,
                isSystemFolder: name == HistoryRecordFormatter.defaultSectionName
            )
        }
    }

    private var shouldShowFolderRail: Bool {
        selectedFolderName != nil || folderSummaries.contains { !$0.isSystemFolder }
    }

    private var shouldShowDateFilterRail: Bool {
        displayRecords.count > 1
    }

    private var shouldShowSectionHeaders: Bool {
        selectedFolderName != nil || displaySections.count > 1
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("No Notes Yet")
                    .font(.title2.weight(.semibold))

                Text("Copied dictations appear here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(VyrraTheme.pageBackground)
    }

    private var historyList: some View {
        List {
            if shouldShowDateFilterRail {
                HistoryDateFilterRail(
                    selectedFilter: selectedDateFilter,
                    count: dateFilterCount
                ) { filter in
                    selectedDateFilter = filter
                    // A choice, not an outcome: selection feedback, not success.
                    HapticManager.selected()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }

            if shouldShowFolderRail {
                HistoryFolderRail(
                    folders: folderSummaries,
                    selectedFolderName: selectedFolderName,
                    selectAll: {
                        selectedFolderName = nil
                        HapticManager.selected()
                    },
                    selectFolder: { folder in
                        selectedFolderName = folder.name
                        HapticManager.selected()
                    },
                    renameFolder: { folder in
                        folderRenameTarget = folder
                    },
                    deleteFolder: { folder in
                        folderDeleteTarget = folder
                        showsFolderDeleteConfirmation = true
                    },
                    moveRecordToFolder: moveRecordToFolder
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }

            ForEach(displaySections, id: \.name) { section in
                Section {
                    ForEach(section.records) { record in
                        HistoryRow(
                            record: record,
                            copied: copiedRecordID == record.id,
                            open: { detailTarget = record },
                            copy: { copy(record) }
                        )
                        .contextMenu {
                            historyContextMenu(for: record)
                        }
                        .draggable(record.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            items.reduce(false) { movedAny, item in
                                moveRecordToRecordFolder(item, targetRecord: record) || movedAny
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        guard !isFixtureMode else { return }
                        delete(section.records, at: offsets)
                    }
                } header: {
                    if shouldShowSectionHeaders {
                        // The List header style already applies secondary color.
                        Text(section.name)
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            if filteredDisplayRecords.isEmpty {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No notes in this folder." : "No matching notes.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(VyrraTheme.pageBackground)
    }

    private func dateFilterCount(_ filter: HistoryDateFilter) -> Int {
        let folderFilteredRecords = if let selectedFolderName {
            displayRecords.filter { $0.displaySectionName == selectedFolderName }
        } else {
            displayRecords
        }

        return folderFilteredRecords.filter { filter.includes($0.createdAt) }.count
    }

    @ViewBuilder
    private func historyContextMenu(for record: HistoryDisplayRecord) -> some View {
        Button {
            copy(record)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if !isFixtureMode {
            Button {
                editTranscriptTarget = record
            } label: {
                Label("Edit Transcript", systemImage: "square.and.pencil")
            }

            Button {
                renameTarget = record
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                tagTarget = record
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Button {
                moveTarget = record
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }

            Button {
                share(record)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                delete(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copy(_ record: HistoryDisplayRecord) {
        ClipboardService.copy(record.polishedText)
        copiedRecordID = record.id
        HapticManager.completed()
    }

    private func delete(_ sectionRecords: [HistoryDisplayRecord], at offsets: IndexSet) {
        for index in offsets {
            delete(sectionRecords[index], save: false)
        }
        try? modelContext.save()
        HapticManager.warning()
    }

    private func delete(_ record: HistoryDisplayRecord, save: Bool = true) {
        guard let managedRecord = managedRecord(for: record) else { return }
        modelContext.delete(managedRecord)
        if save {
            try? modelContext.save()
            HapticManager.warning()
        }
    }

    private func rename(_ record: HistoryDisplayRecord, title: String) {
        guard let managedRecord = managedRecord(for: record) else { return }
        managedRecord.title = HistoryRecordFormatter.normalizedOptional(title)
        try? modelContext.save()
    }

    private func editTranscript(_ record: HistoryDisplayRecord, text: String) {
        guard let managedRecord = managedRecord(for: record),
              let normalizedText = HistoryRecordFormatter.normalizedOptional(text)
        else { return }

        managedRecord.polishedText = normalizedText
        try? modelContext.save()
        detailTarget = HistoryDisplayRecord(record: managedRecord)
        HapticManager.completed()
    }

    private func updateTags(_ record: HistoryDisplayRecord, tagsText: String) {
        guard let managedRecord = managedRecord(for: record) else { return }
        managedRecord.tagsText = HistoryTagFormatter.storageText(from: tagsText)
        try? modelContext.save()
        detailTarget = HistoryDisplayRecord(record: managedRecord)
        HapticManager.completed()
    }

    private func share(_ record: HistoryDisplayRecord) {
        do {
            sharePayload = HistorySharePayload(items: try HistoryExportWriter.exportURLs(for: record))
            HapticManager.completed()
        } catch {
            ClipboardService.copy(record.polishedText)
            copiedRecordID = record.id
            HapticManager.warning()
        }
    }

    private func move(_ record: HistoryDisplayRecord, sectionName: String) {
        guard let managedRecord = managedRecord(for: record) else { return }
        let normalizedName = HistoryRecordFormatter.normalizedOptional(sectionName)
        ensureFolderExists(named: normalizedName)
        managedRecord.sectionName = normalizedName
        try? modelContext.save()
    }

    private func moveRecordToFolder(_ recordIDString: String, _ folderName: String) -> Bool {
        guard !isFixtureMode,
              let recordID = UUID(uuidString: recordIDString),
              let record = records.first(where: { $0.id == recordID })
        else { return false }

        let normalizedName = HistoryRecordFormatter.normalizedOptional(folderName)
        ensureFolderExists(named: normalizedName)
        record.sectionName = normalizedName
        try? modelContext.save()
        HapticManager.completed()
        return true
    }

    private func moveRecordToRecordFolder(_ recordIDString: String, targetRecord: HistoryDisplayRecord) -> Bool {
        guard !isFixtureMode,
              let recordID = UUID(uuidString: recordIDString),
              recordID != targetRecord.id,
              let record = records.first(where: { $0.id == recordID })
        else { return false }

        let targetFolderName = targetRecord.displaySectionName == HistoryRecordFormatter.defaultSectionName ? nil : targetRecord.displaySectionName
        let normalizedName = HistoryRecordFormatter.normalizedOptional(targetFolderName)
        ensureFolderExists(named: normalizedName)
        record.sectionName = normalizedName
        try? modelContext.save()
        HapticManager.completed()
        return true
    }

    private func createFolder(named name: String) {
        guard let normalizedName = HistoryRecordFormatter.normalizedOptional(name),
              normalizedName != HistoryRecordFormatter.defaultSectionName
        else { return }

        ensureFolderExists(named: normalizedName)
        selectedFolderName = normalizedName
        try? modelContext.save()
        HapticManager.completed()
    }

    private func renameFolder(_ folder: HistoryFolderSummary, to newName: String) {
        guard !folder.isSystemFolder,
              let normalizedName = HistoryRecordFormatter.normalizedOptional(newName),
              normalizedName != HistoryRecordFormatter.defaultSectionName
        else { return }

        if let managedFolder = folders.first(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) {
            managedFolder.name = normalizedName
            managedFolder.updatedAt = Date()
        } else if !folders.contains(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            modelContext.insert(NoteFolder(name: normalizedName))
        }

        for record in records where HistoryRecordFormatter.displaySectionName(record.sectionName) == folder.name {
            record.sectionName = normalizedName
        }

        selectedFolderName = normalizedName
        try? modelContext.save()
        HapticManager.completed()
    }

    private func deleteFolder(_ folder: HistoryFolderSummary) {
        guard !folder.isSystemFolder else { return }

        for record in records where HistoryRecordFormatter.displaySectionName(record.sectionName) == folder.name {
            record.sectionName = nil
        }

        if let managedFolder = folders.first(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) {
            modelContext.delete(managedFolder)
        }

        if selectedFolderName == folder.name {
            selectedFolderName = nil
        }

        try? modelContext.save()
        HapticManager.warning()
    }

    private func clearAll() {
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        HapticManager.warning()
    }

    private func managedRecord(for displayRecord: HistoryDisplayRecord) -> TranscriptionRecord? {
        records.first { $0.id == displayRecord.id }
    }

    private func sectionSort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == HistoryRecordFormatter.defaultSectionName { return true }
        if rhs == HistoryRecordFormatter.defaultSectionName { return false }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private func ensureFolderExists(named name: String?) {
        guard let name,
              name != HistoryRecordFormatter.defaultSectionName,
              !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return }

        modelContext.insert(NoteFolder(name: name))
    }

    private func recommendedFolders(for record: HistoryDisplayRecord) -> [HistoryFolderSummary] {
        let recommendedNames = HistoryFolderRecommender.recommendedFolderNames(
            title: record.displayTitle,
            text: record.polishedText,
            folders: folderSummaries.map(\.name),
            currentFolder: record.displaySectionName
        )

        var recommendations = recommendedNames.compactMap { name in
            folderSummaries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        let fallbackFolders = folderSummaries
            .filter { folder in
                !folder.isSystemFolder
                    && folder.name.caseInsensitiveCompare(record.displaySectionName) != .orderedSame
                    && !recommendations.contains(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame })
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                switch (lhs.latestDate, rhs.latestDate) {
                case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }

        for folder in fallbackFolders where recommendations.count < 3 {
            recommendations.append(folder)
        }

        return recommendations
    }
}

private struct HistoryFolderSummary: Identifiable, Hashable {
    let name: String
    let count: Int
    let latestDate: Date?
    let isSystemFolder: Bool

    var id: String { name }
}

private enum HistoryDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .today:
            "Today"
        case .last7Days:
            "7 Days"
        case .last30Days:
            "30 Days"
        }
    }

    func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        switch self {
        case .all:
            true
        case .today:
            calendar.isDate(date, inSameDayAs: now)
        case .last7Days:
            isDate(date, withinDays: 7, now: now, calendar: calendar)
        case .last30Days:
            isDate(date, withinDays: 30, now: now, calendar: calendar)
        }
    }

    private func isDate(_ date: Date, withinDays days: Int, now: Date, calendar: Calendar) -> Bool {
        guard let startOfWindow = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return false
        }

        return date >= startOfWindow && date <= now
    }
}

private struct HistoryDateFilterRail: View {
    let selectedFilter: HistoryDateFilter
    let count: (HistoryDateFilter) -> Int
    let select: (HistoryDateFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryDateFilter.allCases) { filter in
                    HistoryDateFilterChip(
                        title: filter.title,
                        count: count(filter),
                        isSelected: selectedFilter == filter,
                        action: { select(filter) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }
}

private struct HistoryDateFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))

                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.primary.opacity(0.28) : VyrraTheme.thinLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "note" : "notes")")
    }
}

private struct HistoryFolderRail: View {
    let folders: [HistoryFolderSummary]
    let selectedFolderName: String?
    let selectAll: () -> Void
    let selectFolder: (HistoryFolderSummary) -> Void
    let renameFolder: (HistoryFolderSummary) -> Void
    let deleteFolder: (HistoryFolderSummary) -> Void
    let moveRecordToFolder: (String, String) -> Bool

    private var totalCount: Int {
        folders.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HistoryFolderChip(
                        title: "All Notes",
                        count: totalCount,
                        systemImage: "tray.full",
                        isSelected: selectedFolderName == nil,
                        action: selectAll
                    )

                    ForEach(folders) { folder in
                        HistoryFolderChip(
                            title: folder.name,
                            count: folder.count,
                            systemImage: folder.isSystemFolder ? "tray" : "folder",
                            isSelected: selectedFolderName == folder.name,
                            action: { selectFolder(folder) }
                        )
                        .contextMenu {
                            if !folder.isSystemFolder {
                                Button {
                                    renameFolder(folder)
                                } label: {
                                    Label("Rename Folder", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deleteFolder(folder)
                                } label: {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            items.reduce(false) { movedAny, item in
                                moveRecordToFolder(item, folder.name) || movedAny
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct HistoryFolderChip: View {
    let title: String
    let count: Int
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)

                    Text("\(count) \(count == 1 ? "note" : "notes")")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minWidth: 104, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.28) : VyrraTheme.thinLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let record: HistoryDisplayRecord
    let copied: Bool
    let open: () -> Void
    let copy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if let previewText {
                        Text(previewText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }

                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VyrraIconButton(
                systemName: copied ? "checkmark.circle.fill" : "doc.on.doc",
                label: "Copy transcript",
                size: 44,
                iconSize: 19,
                action: copy
            )
            .foregroundStyle(copied ? VyrraTheme.success : .primary)
        }
        .padding(.vertical, previewText == nil ? 7 : 9)
        .accessibilityElement(children: .combine)
    }

    private var previewText: String? {
        guard record.title != nil else { return nil }
        let preview = normalized(record.polishedText)
        guard !preview.isEmpty else { return nil }
        guard normalized(record.displayTitle) != preview else { return nil }
        return preview
    }

    private var metadata: String {
        let date = record.createdAt.formatted(date: .abbreviated, time: .shortened)
        let duration = record.duration.formatted(.number.precision(.fractionLength(1)))
        let mode = PolishingMode(rawValue: record.polishingMode)?.title ?? record.polishingMode.capitalized
        let base = "\(date) · \(duration)s · \(mode)"
        guard let tags = HistoryTagFormatter.displayText(from: record.tagsText) else { return base }
        return "\(base) · \(tags)"
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension HistoryDisplayRecord {
    func matchesSearch(_ query: String) -> Bool {
        let haystack = [
            displayTitle,
            polishedText,
            rawText,
            displaySectionName,
            HistoryTagFormatter.displayText(from: tagsText) ?? "",
            PolishingMode(rawValue: polishingMode)?.title ?? polishingMode
        ]
        .joined(separator: " ")
        .lowercased()

        return query
            .lowercased()
            .split(separator: " ")
            .allSatisfy { haystack.contains($0) }
    }
}

private struct HistoryMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newFolderName = ""

    let record: HistoryDisplayRecord
    let folders: [HistoryFolderSummary]
    let recommendedFolders: [HistoryFolderSummary]
    let moveToFolder: (HistoryFolderSummary) -> Void
    let createAndMove: (String) -> Void

    private var normalizedNewFolderName: String? {
        HistoryRecordFormatter.normalizedOptional(newFolderName)
    }

    private var canCreateFolder: Bool {
        guard let normalizedNewFolderName,
              normalizedNewFolderName != HistoryRecordFormatter.defaultSectionName
        else { return false }

        return !folders.contains {
            $0.name.caseInsensitiveCompare(normalizedNewFolderName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.displayTitle)
                            .font(.headline)
                            .lineLimit(2)

                        Text("Current folder: \(record.displaySectionName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if !recommendedFolders.isEmpty {
                        folderGroup(title: "Suggested", folders: recommendedFolders)
                    }

                    folderGroup(title: "Move To", folders: folders)

                    VyrraPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("New Folder")
                                .font(.headline)

                            TextField("Folder name", text: $newFolderName)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit(createFolder)

                            Button(action: createFolder) {
                                Label("Create and Move", systemImage: "folder.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(canCreateFolder ? Color.primary : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                                    .foregroundStyle(canCreateFolder ? Color(.systemBackground) : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canCreateFolder)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(VyrraTheme.pageBackground)
            .navigationTitle("Move Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderGroup(title: String, folders: [HistoryFolderSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(folders) { folder in
                    Button {
                        moveToFolder(folder)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: folder.isSystemFolder ? "tray" : "folder")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Color.primary.opacity(0.07), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.subheadline.weight(.semibold))

                                Text("\(folder.count) \(folder.count == 1 ? "note" : "notes")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if folder.name == record.displaySectionName {
                                Text("Current")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(folder.name == record.displaySectionName)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func createFolder() {
        guard canCreateFolder else { return }
        createAndMove(newFolderName)
        dismiss()
    }
}

private struct HistoryTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    let title: String
    let fieldTitle: String
    let placeholder: String
    let saveTitle: String
    let fieldAutocapitalization: TextInputAutocapitalization
    let footer: String?
    let save: (String) -> Void

    init(
        title: String,
        fieldTitle: String,
        initialText: String,
        placeholder: String,
        saveTitle: String,
        fieldAutocapitalization: TextInputAutocapitalization = .words,
        footer: String? = nil,
        save: @escaping (String) -> Void
    ) {
        self.title = title
        self.fieldTitle = fieldTitle
        self.placeholder = placeholder
        self.saveTitle = saveTitle
        self.fieldAutocapitalization = fieldAutocapitalization
        self.footer = footer
        self.save = save
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(fieldAutocapitalization)
                        .submitLabel(.done)
                } header: {
                    Text(fieldTitle)
                } footer: {
                    if let footer {
                        Text(footer)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        save(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HistoryTranscriptEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    let title: String
    let save: (String) -> Void

    init(title: String, initialText: String, save: @escaping (String) -> Void) {
        self.title = title
        self.save = save
        _text = State(initialValue: initialText)
    }

    private var canSave: Bool {
        HistoryRecordFormatter.normalizedOptional(text) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                            .stroke(VyrraTheme.thinLine, lineWidth: 1)
                    }

                Text("Original text is kept in details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(VyrraTheme.pageBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(text)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct HistorySharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct HistoryActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct HistoryDetailView: View {
    let record: HistoryDisplayRecord
    let copy: (HistoryDisplayRecord) -> Void
    let edit: (HistoryDisplayRecord) -> Void
    let tag: (HistoryDisplayRecord) -> Void
    let share: (HistoryDisplayRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VyrraPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Polished", systemImage: "sparkles")
                                .font(.headline)

                            Spacer()

                            VyrraIconButton(
                                systemName: "doc.on.doc",
                                label: "Copy polished transcript",
                                action: { copy(record) }
                            )

                            VyrraIconButton(
                                systemName: "square.and.pencil",
                                label: "Edit transcript",
                                action: { edit(record) }
                            )
                        }

                        Text(record.polishedText)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VyrraPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Original", systemImage: "waveform")
                            .font(.headline)

                        Text(record.rawText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VyrraPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        MetadataLine(title: "Created", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        MetadataLine(title: "Title", value: record.displayTitle)
                        MetadataLine(title: "Section", value: record.displaySectionName)
                        MetadataLine(title: "Tags", value: HistoryTagFormatter.displayText(from: record.tagsText) ?? "None")
                        MetadataLine(title: "Duration", value: "\(record.duration.formatted(.number.precision(.fractionLength(1))))s")
                        MetadataLine(title: "Model", value: record.modelName)
                        MetadataLine(title: "Mode", value: record.polishingMode)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        tag(record)
                    } label: {
                        Label("Tags", systemImage: "tag")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        share(record)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .background(VyrraTheme.pageBackground)
        .navigationTitle(record.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MetadataLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    HistoryView(fixture: .historyPopulated)
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
