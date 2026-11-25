import PhotosUI
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vyrraAccentColor) private var accentColor
    @EnvironmentObject private var modelManager: ModelManager
    @Query(sort: \TranscriptionRecord.createdAt, order: .reverse) private var records: [TranscriptionRecord]
    @AppStorage("profileDisplayName") private var displayName = "Vyrra User"
    @AppStorage("profileContactEmail") private var contactEmail = ""
    @AppStorage(VyrraAppearance.storageKey) private var appearanceRawValue = VyrraAppearance.system.rawValue
    @AppStorage(VyrraAccent.storageKey) private var accentRawValue = VyrraAccent.monochrome.rawValue
    @State private var showsEditProfile = false
    @State private var activityWeekOffset = 0
    @State private var profileImageData = VyrraProfileImageStore.loadData()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    profileHeader

                    ProfileSection {
                        ProfileActivityPanel(
                            snapshot: activitySnapshot,
                            canShowNextWeek: activityWeekOffset < 0,
                            previousWeek: { activityWeekOffset -= 1 },
                            nextWeek: { activityWeekOffset = min(0, activityWeekOffset + 1) }
                        )
                    }

                    ProfileSection {
                        DictationSoundPicker()
                            .font(.body.weight(.medium))
                            .padding(.vertical, 6)

                        Divider()

                        Toggle("Haptic Feedback", isOn: $modelManager.hapticsEnabled)
                            .font(.body.weight(.medium))
                            .tint(Color(.systemGreen))
                            .padding(.vertical, 14)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            VyrraWaveformPill(
                                level: 0.42 * modelManager.waveformSensitivity,
                                isActive: true,
                                motion: modelManager.waveformMotion,
                                accessibilityDescription: "Waveform preview"
                            )

                            Picker("Wave Motion", selection: $modelManager.waveformMotion) {
                                ForEach(WaveformMotion.allCases) { motion in
                                    Text(motion.title).tag(motion)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minHeight: 44)

                            HStack {
                                Text("Wave Sensitivity")
                                Spacer()
                                Text(modelManager.waveformSensitivityLabel)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.body.weight(.medium))

                            Slider(value: $modelManager.waveformSensitivity, in: 0.65...1.65, step: 0.05)
                                .tint(accentColor)
                        }
                        .padding(.vertical, 14)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Appearance")
                                .font(.body.weight(.medium))

                            VyrraAppearancePicker(selection: $appearanceRawValue)
                        }
                        .padding(.vertical, 14)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Accent")
                                .font(.body.weight(.medium))

                            VyrraAccentPicker(selection: $accentRawValue)
                        }
                        .padding(.vertical, 14)
                    } title: {
                        Text("Customize")
                    }

                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 48)
            }
            .background(VyrraTheme.pageBackground)
            .preferredColorScheme(VyrraAppearance.colorScheme(for: appearanceRawValue))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsEditProfile = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit profile")
                }
            }
            .onAppear {
                if displayName == "Local Writer" {
                    displayName = "Vyrra User"
                }
            }
            .sheet(isPresented: $showsEditProfile) {
                ProfileEditSheet(
                    displayName: displayName,
                    contactEmail: contactEmail,
                    imageData: profileImageData
                ) { name, email, imageData in
                    displayName = name
                    contactEmail = email
                    profileImageData = imageData
                    VyrraProfileImageStore.save(imageData)
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                showsEditProfile = true
            } label: {
                VyrraProfileAvatar(imageData: profileImageData, initials: initials, size: 54)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 18, height: 18)
                            .background(accentColor, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 1.5)
                            }
                    }
            }
            .buttonStyle(VyrraPressButtonStyle(scale: 0.97, opacity: 0.9))
            .accessibilityLabel("Edit profile")

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if let profileSubtitle {
                    Text(profileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private var profileSubtitle: String? {
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? nil : trimmedEmail
    }

    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }

    private var activitySnapshot: ProfileActivitySnapshot {
        ProfileActivitySnapshot(records: records, weekOffset: activityWeekOffset)
    }
}

struct ProfileActivitySnapshot {
    let wordCount: Int
    let draftCount: Int
    let minutesValue: String
    let activeDayCount: Int
    let weeklyDays: [ProfileActivityDay]
    let weeklyWordCount: Int
    let weekTitle: String
    let weekRange: String
    let summary: String

    init(records: [TranscriptionRecord], calendar: Calendar = .current, now: Date = Date(), weekOffset: Int = 0) {
        let sortedRecords = records.sorted { $0.createdAt > $1.createdAt }
        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weekStart = calendar.date(byAdding: .weekOfYear, value: min(0, weekOffset), to: currentWeekStart) ?? currentWeekStart
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        var wordsByDay: [Date: Int] = [:]
        var activeDays = Set<Date>()
        var totalWords = 0
        var totalDuration: TimeInterval = 0

        for record in records {
            let sourceText = record.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = Self.wordCount(in: sourceText.isEmpty ? record.polishedText : sourceText)
            let day = calendar.startOfDay(for: record.createdAt)
            totalWords += words
            totalDuration += max(record.duration, 0)
            activeDays.insert(day)
            wordsByDay[day, default: 0] += words
        }

        self.wordCount = totalWords
        self.draftCount = records.count
        self.minutesValue = Self.minutesValue(for: totalDuration)
        self.activeDayCount = activeDays.count
        self.weeklyDays = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return ProfileActivityDay(
                id: date,
                label: date.formatted(.dateTime.weekday(.narrow)),
                value: wordsByDay[date, default: 0],
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }
        self.weeklyWordCount = wordsByDay.reduce(0) { result, entry in
            result + (entry.key >= weekStart && entry.key < weekEnd ? entry.value : 0)
        }
        self.weekTitle = weekOffset >= 0 ? "This week" : (weekOffset == -1 ? "Last week" : "Weekly activity")
        let finalDay = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? weekStart
        self.weekRange = "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(finalDay.formatted(.dateTime.month(.abbreviated).day()))"

        if records.isEmpty {
            self.summary = "No activity yet"
        } else if wordsByDay[today, default: 0] > 0 {
            self.summary = "Used today"
        } else if let latest = sortedRecords.first?.createdAt {
            self.summary = "Last active \(latest.formatted(date: .abbreviated, time: .omitted))"
        } else {
            self.summary = "Activity"
        }
    }

    private static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func minutesValue(for duration: TimeInterval) -> String {
        guard duration > 0 else { return "0" }
        guard duration >= 60 else { return "<1" }
        return "\(Int((duration / 60).rounded(.toNearestOrAwayFromZero)))"
    }
}

struct ProfileActivityDay: Identifiable {
    let id: Date
    let label: String
    let value: Int
    let isToday: Bool
}

private struct ProfileSection<Content: View, Title: View>: View {
    let content: Content
    let title: Title?

    init(@ViewBuilder content: () -> Content) where Title == EmptyView {
        self.content = content()
        self.title = nil
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder title: () -> Title) {
        self.content = content()
        self.title = title()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                title
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .background(VyrraTheme.quietFill, in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .stroke(VyrraTheme.thinLine, lineWidth: 1)
            }
        }
    }
}

private struct ProfileActivityPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.vyrraAccentColor) private var accentColor
    @State private var hasAppeared = false

    let snapshot: ProfileActivitySnapshot
    let canShowNextWeek: Bool
    let previousWeek: () -> Void
    let nextWeek: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ProfileMetricCell(value: "\(snapshot.wordCount)", label: "All-time Words")
                ProfileMetricCell(value: "\(snapshot.draftCount)", label: "Drafts")
                ProfileMetricCell(value: snapshot.minutesValue, label: "Minutes")
                ProfileMetricCell(value: "\(snapshot.activeDayCount)", label: "Active Days")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: previousWeek) {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous week")
                    Spacer(minLength: 4)
                    Text(snapshot.weekTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Button(action: nextWeek) {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Next week")
                    .disabled(!canShowNextWeek)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot.weeklyWordCount.formatted()) words")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Spacer(minLength: 8)
                    Text(snapshot.weekRange).font(.caption).foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(snapshot.weeklyDays.enumerated()), id: \.element.id) { index, day in
                        ProfileActivityBar(
                            day: day,
                            maxValue: weeklyMax,
                            index: index,
                            hasAppeared: hasAppeared,
                            reduceMotion: reduceMotion,
                            accentColor: accentColor
                        )
                    }
                }
                .frame(height: 54)
            }
        }
        .padding(.vertical, 16)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var weeklyMax: Int {
        max(snapshot.weeklyDays.map(\.value).max() ?? 0, 1)
    }
}

private struct ProfileMetricCell: View {
    let value: String
    let label: String

    init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileActivityBar: View {
    let day: ProfileActivityDay
    let maxValue: Int
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool
    let accentColor: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.055))
                    .frame(width: 8, height: 34)

                Capsule()
                    .fill(fillStyle)
                    .frame(width: 8, height: displayedHeight)
                    .animation(
                        reduceMotion
                        ? .linear(duration: 0)
                        : .spring(response: 0.48, dampingFraction: 0.84).delay(Double(index) * 0.025),
                        value: hasAppeared
                    )
            }
            .frame(maxWidth: .infinity)

            Text(day.label)
                .font(.caption2.weight(day.isToday ? .semibold : .medium))
                .foregroundStyle(day.isToday ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(day.label), \(day.value) words")
    }

    private var fillStyle: Color {
        day.value > 0 ? accentColor.opacity(day.isToday ? 0.9 : 0.62) : Color.secondary.opacity(0.18)
    }

    private var targetHeight: CGFloat {
        guard day.value > 0 else { return 5 }
        let ratio = CGFloat(day.value) / CGFloat(max(maxValue, 1))
        return 8 + ratio * 26
    }

    private var displayedHeight: CGFloat {
        hasAppeared || reduceMotion ? targetHeight : 5
    }
}

private struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var contactEmail: String
    @State private var imageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?

    let save: (String, String, Data?) -> Void

    init(displayName: String, contactEmail: String, imageData: Data?, save: @escaping (String, String, Data?) -> Void) {
        _displayName = State(initialValue: displayName)
        _contactEmail = State(initialValue: contactEmail)
        _imageData = State(initialValue: imageData)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()

                        VyrraProfileAvatar(imageData: imageData, initials: initials(for: displayName), size: 88)
                            .padding(.vertical, 8)

                        Spacer()
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(imageData == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                    }

                    if imageData != nil {
                        Button(role: .destructive) {
                            imageData = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Photo")
                }

                Section {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)

                    TextField("Optional email label", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(
                            cleaned(displayName, fallback: "Vyrra User"),
                            contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                            imageData
                        )
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                let normalizedData = await MainActor.run {
                    VyrraProfileImageStore.normalizedJPEGData(from: data)
                }

                await MainActor.run {
                    imageData = normalizedData
                }
            }
        }
    }

    private func cleaned(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)

        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }
}

#Preview {
    ProfileView()
        .environmentObject(TranscriptionEngine())
        .environmentObject(ModelManager())
        .environmentObject(RecordingDiagnostics())
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
