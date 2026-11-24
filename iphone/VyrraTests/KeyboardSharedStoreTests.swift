import Foundation
import Testing
@testable import Vyrra

struct KeyboardSharedStoreTests {
    @Test func keyboardInterruptionResumeRespectsTheSelectedTimeout() {
        let start = Date(timeIntervalSince1970: 10_000)
        #expect(!KeyboardInactivityTimeout.immediately.permitsResume(after: start, now: start))
        #expect(KeyboardInactivityTimeout.fiveMinutes.permitsResume(after: start, now: start.addingTimeInterval(299)))
        #expect(!KeyboardInactivityTimeout.fiveMinutes.permitsResume(after: start, now: start.addingTimeInterval(300)))
        #expect(KeyboardInactivityTimeout.never.permitsResume(after: start, now: start.addingTimeInterval(86_400)))
        #expect(!KeyboardInactivityTimeout.never.permitsResume(after: start, now: start.addingTimeInterval(-1)))
    }

    @Test func keyboardHapticPreferenceIsBackwardCompatibleAndPersists() throws {
        let legacy = Data(#"{"size":"large","textSize":"small"}"#.utf8)
        var preferences = try JSONDecoder().decode(KeyboardAppearancePreferences.self, from: legacy)
        #expect(preferences.hapticsEnabled != false)
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        preferences.hapticsEnabled = false
        try KeyboardSharedStore.writeAppearance(preferences, to: containerURL)
        #expect(try KeyboardSharedStore.readAppearance(from: containerURL).hapticsEnabled == false)
        #expect(try KeyboardSharedStore.readAppearance(from: containerURL).size == .large)
    }

    @Test func inactivityCountdownStartsOnlyAfterBothAppAndKeyboardAreInactive() {
        let start = Date(timeIntervalSince1970: 10_000)
        var tracker = KeyboardInactivityTracker()
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: true, keyboardIsVisible: false, phraseIsBusy: false, now: start) == nil)
        let later = start.addingTimeInterval(1_800)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: true, phraseIsBusy: false, now: later) == nil)
        let deadline = later.addingTimeInterval(300)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: later) == deadline)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: later.addingTimeInterval(299)) == deadline)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: true, phraseIsBusy: false, now: deadline) == nil)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: deadline) == deadline.addingTimeInterval(300))
    }

    @Test func recordingAndProcessingCancelTheIdleCountdown() {
        let start = Date(timeIntervalSince1970: 10_000)
        var tracker = KeyboardInactivityTracker()
        _ = tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: true, now: start.addingTimeInterval(299)) == nil)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: true, now: start.addingTimeInterval(900)) == nil)
        #expect(tracker.deadline(timeout: .fiveMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start.addingTimeInterval(901)) == start.addingTimeInterval(1_201))
    }

    @Test func inactivityOptionsApplyToTheCurrentIdlePeriod() {
        let start = Date(timeIntervalSince1970: 10_000)
        var tracker = KeyboardInactivityTracker()
        #expect(tracker.deadline(timeout: .never, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start) == nil)
        #expect(tracker.deadline(timeout: .oneHour, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start.addingTimeInterval(100)) == start.addingTimeInterval(3_600))
        #expect(tracker.deadline(timeout: .fifteenMinutes, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start.addingTimeInterval(100)) == start.addingTimeInterval(900))
        #expect(tracker.deadline(timeout: .immediately, appIsActive: false, keyboardIsVisible: false, phraseIsBusy: false, now: start.addingTimeInterval(100)) == start)
    }

    @Test func activationWithoutATimeoutStillRequiresALiveAppHeartbeat() {
        let now = Date(timeIntervalSince1970: 10_000)
        let activation = KeyboardActivationPayload(id: "live-session", expiresAt: nil, updatedAt: now)
        #expect(activation.isCurrent(now: now.addingTimeInterval(7)))
        #expect(!activation.isCurrent(now: now.addingTimeInterval(9)))
    }

    @Test func aDisappearingKeyboardCannotHideItsReplacement() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        try KeyboardSharedStore.writePresence(KeyboardPresencePayload(id: "new", isVisible: true, updatedAt: now), to: containerURL)
        try KeyboardSharedStore.writePresence(KeyboardPresencePayload(id: "old", isVisible: false, updatedAt: now), to: containerURL)
        let presence = try #require(try KeyboardSharedStore.readPresence(from: containerURL))
        #expect(presence.id == "new")
        #expect(presence.isCurrent(now: now))
        #expect(!presence.isCurrent(now: now.addingTimeInterval(9)))
        try KeyboardSharedStore.writePresence(KeyboardPresencePayload(id: "new", isVisible: false, updatedAt: now), to: containerURL)
        #expect(try KeyboardSharedStore.readPresence(from: containerURL)?.isCurrent(now: now) == false)
    }

    @Test func keyboardAppearanceSurvivesRelaunchAndKeepsRowsAligned() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let appearance = KeyboardAppearancePreferences(size: .large, textSize: .small)
        try KeyboardSharedStore.writeAppearance(appearance, to: containerURL)
        #expect(try KeyboardSharedStore.readAppearance(from: containerURL) == appearance)
        for size in KeyboardSize.allCases {
            let letters = size.rowHeight(KeyboardGeometry.letterKeyHeight) * 3 + size.rowHeight(KeyboardGeometry.keyHeight)
            let symbols = size.rowHeight(KeyboardGeometry.compactKeyHeight) * 2 + size.rowHeight(KeyboardGeometry.keyHeight) * 2
            #expect(letters == symbols)
            #expect(size.rowHeight(44) >= 44)
            #expect(size.keyRowsHeight == letters + size.rowGap * 3)
        }
        #expect(KeyboardSize.compact.contentHeight < KeyboardSize.standard.contentHeight)
        #expect(KeyboardSize.standard.contentHeight < KeyboardSize.large.contentHeight)
    }

    @Test func weeklyWordsUseOriginalDictationAndCalendarWeekBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        func date(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
        }
        func record(_ day: Int, _ words: String) -> TranscriptionRecord {
            TranscriptionRecord(createdAt: date(day), rawText: words, polishedText: "Edited text with many extra words here.", duration: 5, modelName: "test", polishingMode: .cleanUp)
        }
        let records = [record(27, "one two three"), record(28, "one two"), record(30, "one two three four")]
        let current = ProfileActivitySnapshot(records: records, calendar: calendar, now: date(30))
        #expect(current.wordCount == 9)
        #expect(current.weeklyWordCount == 6)
        #expect(current.weeklyDays.map(\.value).reduce(0, +) == 6)
        let previous = ProfileActivitySnapshot(records: records, calendar: calendar, now: date(30), weekOffset: -1)
        #expect(previous.weeklyWordCount == 3)
        #expect(previous.wordCount == 9)
    }

    @Test func automaticInsertionSeparatesPhrasesWithoutChangingSelectionsOrNonLatinText() {
        func inserted(_ text: String, after context: String?, selected: String? = nil) -> String {
            KeyboardSessionContinuity.automaticInsertionText(text, contextBeforeInput: context, selectedText: selected)
        }
        #expect(inserted("Second phrase.", after: "First phrase.") == " Second phrase.")
        #expect(inserted("world", after: "Hello") == " world")
        #expect(inserted("Second phrase.", after: "First phrase. ") == "Second phrase.")
        #expect(inserted("Next paragraph.", after: "First.\n") == "Next paragraph.")
        #expect(inserted("Start.", after: nil) == "Start.")
        #expect(inserted("inside", after: "(") == "inside")
        #expect(inserted("replacement", after: "word", selected: "selection") == "replacement")
        #expect(inserted("你好", after: "早上好。") == "你好")
    }

    @Test func staleAppWriteCannotUndoAnInsertionAcknowledgement() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        func payload(_ state: KeyboardSessionState, id: String = "phrase-1") -> KeyboardSharedPayload {
            KeyboardSharedPayload(
                latestDraft: "Insert once.", shortcuts: [],
                session: KeyboardSessionPayload(
                    state: state, startedAt: now, resultText: "Insert once.",
                    errorText: nil, updatedAt: now, sessionID: id,
                    automaticInsertionRequestedAt: state == .insertReady ? now : nil
                ),
                updatedAt: now
            )
        }
        let staleAppSnapshot = payload(.insertReady)
        try KeyboardSharedStore.write(staleAppSnapshot, to: containerURL)
        try KeyboardSharedStore.write(payload(.inserted), to: containerURL)
        try KeyboardSharedStore.write(staleAppSnapshot, to: containerURL)
        let result = try #require(try KeyboardSharedStore.read(from: containerURL))
        #expect(result.session?.state == .inserted)
        #expect(result.session?.automaticInsertionRequestedAt == nil)
        try KeyboardSharedStore.write(payload(.insertReady, id: "phrase-2"), to: containerURL)
        #expect(try KeyboardSharedStore.read(from: containerURL)?.session?.state == .insertReady)
    }

    @Test func insertionClaimUsesCurrentMetadataAndCannotBeRepeated() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let session = KeyboardSessionPayload(
            state: .insertReady, startedAt: now, resultText: "Insert once.",
            errorText: nil, updatedAt: now, sessionID: "phrase-1",
            automaticInsertionRequestedAt: now
        )
        let current = KeyboardSharedPayload(
            latestDraft: "A newer saved draft.",
            shortcuts: [KeyboardShortcutPayload(trigger: "updated", body: "Keep this shortcut.")],
            session: session,
            polishingMode: KeyboardPolishingModePayload(rawValue: "cleanUp", title: "Clean Up"),
            activation: KeyboardActivationPayload(id: "current-activation", expiresAt: nil, updatedAt: now),
            updatedAt: now
        )
        try KeyboardSharedStore.write(current, to: containerURL)
        let claimed = try #require(try KeyboardSharedStore.claimInsertion(for: session, in: containerURL, now: now))
        #expect(claimed.session?.state == .inserted)
        #expect(claimed.session?.automaticInsertionRequestedAt == nil)
        #expect(claimed.latestDraft == current.latestDraft)
        #expect(claimed.shortcuts == current.shortcuts)
        #expect(claimed.polishingMode == current.polishingMode)
        #expect(claimed.activation == current.activation)
        #expect(try KeyboardSharedStore.claimInsertion(for: session, in: containerURL, now: now) == nil)
        // A delayed app heartbeat must not make the result claimable again.
        try KeyboardSharedStore.write(current, to: containerURL)
        #expect(try KeyboardSharedStore.claimInsertion(for: session, in: containerURL, now: now) == nil)
    }

    @Test func insertionClaimRejectsStaleOrReplacedResults() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        func session(id: String = "phrase-1", text: String = "Expected result.") -> KeyboardSessionPayload {
            KeyboardSessionPayload(
                state: .insertReady, startedAt: now, resultText: text,
                errorText: nil, updatedAt: now, sessionID: id
            )
        }
        let current = KeyboardSharedPayload(latestDraft: "Expected result.", shortcuts: [], session: session(), updatedAt: now)
        try KeyboardSharedStore.write(current, to: containerURL)
        for stale in [session(id: "phrase-0"), session(text: "Older result."), session(id: " "), session(text: " ")] {
            #expect(try KeyboardSharedStore.claimInsertion(for: stale, in: containerURL, now: now) == nil)
            #expect(try KeyboardSharedStore.read(from: containerURL) == current)
        }
        #expect(try KeyboardSharedStore.claimInsertion(
            for: session(), in: containerURL,
            now: now.addingTimeInterval(VyrraSessionPolicy.insertReadyStaleInterval + 1)
        ) == nil)
        #expect(try KeyboardSharedStore.read(from: containerURL) == current)
    }

    @Test func concurrentKeyboardInstancesCanClaimOnlyOneInsertion() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let session = KeyboardSessionPayload(
            state: .insertReady, startedAt: now, resultText: "Insert once.",
            errorText: nil, updatedAt: now, sessionID: "phrase-1"
        )
        try KeyboardSharedStore.write(
            KeyboardSharedPayload(latestDraft: session.resultText, shortcuts: [], session: session, updatedAt: now),
            to: containerURL
        )
        let lock = NSLock()
        var successes = 0
        var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do {
                let claimed = try KeyboardSharedStore.claimInsertion(for: session, in: containerURL, now: now)
                lock.withLock { if claimed != nil { successes += 1 } }
            } catch {
                lock.withLock { errors.append(error.localizedDescription) }
            }
        }
        #expect(errors.isEmpty)
        #expect(successes == 1)
        #expect(try KeyboardSharedStore.read(from: containerURL)?.session?.state == .inserted)
    }

    @Test func keyboardStartRequiresAnUnexpiredLiveActivation() {
        let now = Date(timeIntervalSince1970: 10_000)
        let activation = KeyboardActivationPayload(id: "enabled-session", expiresAt: now.addingTimeInterval(300), updatedAt: now)
        let ready = KeyboardSessionPayload.ready(updatedAt: now)
        #expect(KeyboardPrimaryActionResolver.action(for: ready, activation: activation, now: now) == .start)
        #expect(KeyboardPrimaryActionResolver.action(for: ready, activation: activation, now: now.addingTimeInterval(9)) == .quickStart)
        #expect(KeyboardPrimaryActionResolver.action(for: ready, now: now) == .quickStart)
        let expired = KeyboardActivationPayload(id: activation.id, expiresAt: now, updatedAt: now)
        #expect(KeyboardPrimaryActionResolver.action(for: ready, activation: expired, now: now) == .quickStart)
    }

    @Test func keyboardActivationCannotStealAnActiveOrCompletedPhrase() {
        let now = Date(timeIntervalSince1970: 10_000)
        let activation = KeyboardActivationPayload(id: "enabled-session", expiresAt: now.addingTimeInterval(300), updatedAt: now)
        func session(_ state: KeyboardSessionState, text: String? = nil) -> KeyboardSessionPayload {
            KeyboardSessionPayload(state: state, startedAt: now, resultText: text, errorText: nil, updatedAt: now, sessionID: "phrase-1")
        }
        #expect(KeyboardPrimaryActionResolver.action(for: session(.listening), activation: activation, now: now) == .finish)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.processing), activation: activation, now: now) == .wait)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.insertReady, text: "First phrase."), activation: activation, now: now) == .insertResult)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.inserted), activation: activation, now: now) == .start)
    }

    @Test func keyboardActivationCommandsRequireExactIdentityAndFreshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        let activation = KeyboardActivationPayload(id: "enabled-session", expiresAt: now.addingTimeInterval(300), updatedAt: now)
        func matches(_ type: KeyboardSessionCommandType, id: String?, age: TimeInterval = 0) -> Bool {
            KeyboardSessionContinuity.commandTargetsKeyboardActivation(
                KeyboardSessionCommand(type: type, requestedAt: now.addingTimeInterval(-age), sessionID: id),
                activation: activation, now: now
            )
        }
        #expect(matches(.start, id: activation.id))
        #expect(matches(.endKeyboardSession, id: activation.id))
        #expect(!matches(.start, id: nil))
        #expect(!matches(.start, id: "old-session"))
        #expect(!matches(.start, id: activation.id, age: 31))
        #expect(!matches(.start, id: activation.id, age: -3))
        #expect(!matches(.finish, id: activation.id))
    }

    @Test func writesLatestDraftAndEnabledShortcutsOnlyPayload() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let payload = KeyboardSharedPayload(
            latestDraft: "Ship the private draft.",
            shortcuts: [
                KeyboardShortcutPayload(trigger: "addr", body: "123 Local Street"),
                KeyboardShortcutPayload(trigger: "sig", body: "Sent from Vyrra")
            ],
            session: KeyboardSessionPayload(
                state: .insertReady,
                startedAt: nil,
                resultText: "Ship the private draft.",
                errorText: nil,
                updatedAt: Date(timeIntervalSince1970: 1_777_778),
                voiceReadiness: KeyboardVoiceReadinessPayload(
                    state: .ready,
                    detail: "Ready",
                    updatedAt: Date(timeIntervalSince1970: 1_777_778)
                )
            ),
            polishingMode: KeyboardPolishingModePayload(rawValue: "cleanUp", title: "Clean"),
            updatedAt: Date(timeIntervalSince1970: 1_777_777)
        )

        try KeyboardSharedStore.write(payload, to: containerURL)

        let roundTrip = try #require(try KeyboardSharedStore.read(from: containerURL))
        #expect(roundTrip == payload)
        #expect(roundTrip.polishingMode?.title == "Clean")

        let data = try Data(contentsOf: KeyboardSharedStore.payloadURL(in: containerURL))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("rawText"))
        #expect(!json.contains("audio"))
        #expect(!json.contains("modelName"))
        #expect(!json.contains("diagnostics"))
        #expect(!json.contains("elapsed"))
        #expect(!json.contains("microphone"))
    }

    @Test func bootstrapsPrivacyMinimalReadyPayloadOnlyOnce() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let bootstrapDate = Date(timeIntervalSince1970: 1_777_700)

        let initialPayload = try KeyboardSharedStore.bootstrapIfNeeded(
            in: containerURL,
            updatedAt: bootstrapDate
        )

        #expect(initialPayload.latestDraft == nil)
        #expect(initialPayload.shortcuts.isEmpty)
        #expect(initialPayload.session?.state == .ready)
        #expect(initialPayload.session?.updatedAt == bootstrapDate)

        let personalizedPayload = KeyboardSharedPayload(
            latestDraft: "Keep this draft.",
            shortcuts: [],
            session: .ready(updatedAt: bootstrapDate.addingTimeInterval(1)),
            updatedAt: bootstrapDate.addingTimeInterval(1)
        )
        try KeyboardSharedStore.write(personalizedPayload, to: containerURL)

        let existingPayload = try KeyboardSharedStore.bootstrapIfNeeded(
            in: containerURL,
            updatedAt: bootstrapDate.addingTimeInterval(2)
        )
        #expect(existingPayload == personalizedPayload)
    }

    @Test func decodesKeyboardPayloadWhenReadinessIsMissing() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let json = """
        {
          "latestDraft": null,
          "shortcuts": [],
          "session": {
            "state": "ready",
            "startedAt": null,
            "resultText": null,
            "errorText": null,
            "updatedAt": "2026-01-01T00:00:00Z"
          },
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        try FileManager.default.createDirectory(
            at: KeyboardSharedStore.storageDirectoryURL(in: containerURL),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: KeyboardSharedStore.payloadURL(in: containerURL))

        let payload = try #require(try KeyboardSharedStore.read(from: containerURL))
        #expect(payload.session?.voiceReadiness == nil)
        #expect(payload.session?.state == .ready)
        #expect(payload.session?.sessionID == nil)
        #expect(payload.session?.automaticInsertionRequestedAt == nil)
        #expect(payload.polishingMode == nil)
    }

    @Test func staleActiveSessionCollapsesToReadyWithoutLeakingContent() {
        let staleSession = KeyboardSessionPayload(
            state: .listening,
            startedAt: Date(timeIntervalSince1970: 1_000),
            resultText: nil,
            errorText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            voiceReadiness: KeyboardVoiceReadinessPayload(
                state: .ready,
                detail: "Ready",
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let collapsed = staleSession.collapsedIfStale(
            now: Date(timeIntervalSince1970: 1_180),
            staleInterval: 150
        )

        #expect(collapsed.state == .ready)
        #expect(collapsed.startedAt == nil)
        #expect(collapsed.resultText == nil)
        #expect(collapsed.errorText == nil)
        #expect(collapsed.voiceReadiness == staleSession.voiceReadiness)
    }

    @Test func staleOpeningSessionCollapsesQuicklyWithoutLeakingContent() {
        let staleSession = KeyboardSessionPayload(
            state: .opening,
            startedAt: Date(timeIntervalSince1970: 1_000),
            resultText: nil,
            errorText: "Tap Open Vyrra",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            voiceReadiness: KeyboardVoiceReadinessPayload(
                state: .ready,
                detail: "Ready",
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let collapsed = staleSession.collapsedIfStale(
            now: Date(timeIntervalSince1970: 1_009)
        )

        #expect(collapsed.state == .ready)
        #expect(collapsed.startedAt == nil)
        #expect(collapsed.resultText == nil)
        #expect(collapsed.errorText == nil)
        #expect(collapsed.voiceReadiness == staleSession.voiceReadiness)
    }

    @Test func freshActiveSessionDoesNotCollapse() {
        let freshSession = KeyboardSessionPayload(
            state: .processing,
            startedAt: Date(timeIntervalSince1970: 1_000),
            resultText: nil,
            errorText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            voiceReadiness: nil
        )

        let effective = freshSession.collapsedIfStale(
            now: Date(timeIntervalSince1970: 1_030),
            staleInterval: 150
        )

        #expect(effective == freshSession)
    }

    @Test func listeningAndWarmupDoNotExpireDuringSupportedWork() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let listening = KeyboardSessionPayload(
            state: .listening,
            startedAt: updatedAt,
            resultText: nil,
            errorText: nil,
            updatedAt: updatedAt,
            sessionID: "session-listening"
        )
        let warming = KeyboardSessionPayload(
            state: .warming,
            startedAt: updatedAt,
            resultText: nil,
            errorText: nil,
            updatedAt: updatedAt,
            sessionID: "session-warming"
        )

        #expect(
            listening.collapsedIfStale(
                now: updatedAt.addingTimeInterval(VyrraSessionPolicy.maximumRecordingDuration + 30)
            ) == listening
        )
        #expect(
            listening.collapsedIfStale(
                now: updatedAt.addingTimeInterval(VyrraSessionPolicy.listeningStaleInterval + 1)
            ).state == .ready
        )
        #expect(
            warming.collapsedIfStale(now: updatedAt.addingTimeInterval(2 * 60)) == warming
        )
    }

    @Test func completedResultExpiresToAnExplicitLastDraftOnlyPath() {
        let completedSession = KeyboardSessionPayload(
            state: .insertReady,
            startedAt: Date(timeIntervalSince1970: 1_000),
            resultText: "Insert this once.",
            errorText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            voiceReadiness: nil
        )

        let fresh = completedSession.collapsedIfStale(now: Date(timeIntervalSince1970: 1_299))
        let expired = completedSession.collapsedIfStale(now: Date(timeIntervalSince1970: 1_301))

        #expect(fresh == completedSession)
        #expect(expired.state == .ready)
        #expect(expired.resultText == nil)
        #expect(KeyboardPrimaryActionResolver.action(for: expired) == .quickStart)
    }

    @Test func clearsSharedKeyboardPayload() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        try KeyboardSharedStore.write(
            KeyboardSharedPayload(latestDraft: "Draft", shortcuts: [], session: .ready(), updatedAt: Date()),
            to: containerURL
        )
        try KeyboardSharedStore.clear(from: containerURL)

        #expect(try KeyboardSharedStore.read(from: containerURL) == nil)
    }

    @Test func writesAndClearsKeyboardSessionCommand() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let command = KeyboardSessionCommand(
            id: "command-1",
            type: .finish,
            requestedAt: Date(timeIntervalSince1970: 1_777_779),
            expiresAt: Date(timeIntervalSince1970: 1_777_782)
        )

        try KeyboardSharedStore.writeCommand(command, to: containerURL)

        #expect(try KeyboardSharedStore.readCommand(from: containerURL) == command)

        let data = try Data(contentsOf: KeyboardSharedStore.commandURL(in: containerURL))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("rawText"))
        #expect(!json.contains("audio"))
        #expect(!json.contains("modelName"))
        #expect(!json.contains("diagnostics"))

        try KeyboardSharedStore.clearCommand(from: containerURL)
        #expect(try KeyboardSharedStore.readCommand(from: containerURL) == nil)
    }

    @Test func rapidCancelAndRestartCommandsRemainOrderedAndAreConsumedOnce() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let cancel = KeyboardSessionCommand(type: .cancel, requestedAt: now, sessionID: "phrase-1")
        let restart = KeyboardSessionCommand(type: .start, requestedAt: now, sessionID: "activation-1")
        try KeyboardSharedStore.writeCommand(cancel, to: containerURL)
        try KeyboardSharedStore.writeCommand(restart, to: containerURL)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == cancel)
        // A command arriving after consumption must survive the next poll too.
        let stop = KeyboardSessionCommand(type: .endKeyboardSession, requestedAt: now, sessionID: "activation-1")
        try KeyboardSharedStore.writeCommand(stop, to: containerURL)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == restart)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == stop)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == nil)
    }

    @Test(arguments: [false, true])
    func pendingCommandsSurviveAnUpgradeFromEitherLegacyLocation(atContainerRoot: Bool) throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let oldCommand = KeyboardSessionCommand(type: .cancel, requestedAt: now, sessionID: "phrase-1")
        let newCommand = KeyboardSessionCommand(type: .start, requestedAt: now, sessionID: "activation-1")
        let legacyURL = atContainerRoot
            ? containerURL.appendingPathComponent(KeyboardSharedStore.commandFileName)
            : KeyboardSharedStore.commandURL(in: containerURL)
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(oldCommand).write(to: legacyURL)
        try KeyboardSharedStore.writeCommand(newCommand, to: containerURL)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == oldCommand)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == newCommand)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func concurrentCommandWritersAndConsumersDoNotLoseOrDuplicateIntents() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let commands = (0..<40).map {
            KeyboardSessionCommand(id: "command-\($0)", type: .cancel, sessionID: "phrase-\($0)")
        }
        let lock = NSLock()
        var errors: [String] = []
        var consumed: [String] = []
        DispatchQueue.concurrentPerform(iterations: commands.count) { index in
            do {
                try KeyboardSharedStore.writeCommand(commands[index], to: containerURL)
                if let command = try KeyboardSharedStore.consumeCommand(from: containerURL) {
                    lock.withLock { consumed.append(command.id) }
                }
            } catch {
                lock.withLock { errors.append(error.localizedDescription) }
            }
        }
        while let command = try KeyboardSharedStore.consumeCommand(from: containerURL) {
            consumed.append(command.id)
        }
        #expect(errors.isEmpty)
        #expect(consumed.count == commands.count)
        #expect(Set(consumed) == Set(commands.map(\.id)))
    }

    @Test func clearingCommandsAlsoRemovesAnUnreadableLegacyFile() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let legacyURL = containerURL.appendingPathComponent(KeyboardSharedStore.commandFileName)
        try Data("malformed command".utf8).write(to: legacyURL)
        try KeyboardSharedStore.clearCommand(from: containerURL)
        #expect(try KeyboardSharedStore.consumeCommand(from: containerURL) == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func writesDiagnosticsWithoutUserContentAndCapsEntries() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        for index in 0..<45 {
            try KeyboardSharedStore.appendDiagnostic(
                KeyboardDiagnosticEntry(
                    id: "diagnostic-\(index)",
                    type: .primaryTapped,
                    detail: "ready",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                ),
                to: containerURL
            )
        }

        let diagnostics = try KeyboardSharedStore.readDiagnostics(from: containerURL)
        #expect(diagnostics.count == 40)
        #expect(diagnostics.first?.id == "diagnostic-5")
        #expect(diagnostics.last?.id == "diagnostic-44")

        let data = try Data(contentsOf: KeyboardSharedStore.diagnosticsURL(in: containerURL))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("rawText"))
        #expect(!json.contains("audio"))
        #expect(!json.contains("modelName"))
        #expect(!json.contains("transcript"))

        try KeyboardSharedStore.clearDiagnostics(from: containerURL)
        #expect(try KeyboardSharedStore.readDiagnostics(from: containerURL).isEmpty)
    }

    @Test func unknownDiagnosticsDoNotPoisonCurrentKeyboardEvidence() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let json = """
        [
          {
            "id": "legacy-unknown",
            "type": "removedLegacyEvent",
            "detail": "unsupported",
            "createdAt": "2026-01-01T00:00:00Z"
          },
          {
            "id": "current-launch",
            "type": "openAppFailed",
            "detail": "start-dictation:denied",
            "createdAt": "2026-01-01T00:00:00Z"
          },
          {
            "id": "current-finish",
            "type": "commandWriteSucceeded",
            "detail": "finish",
            "createdAt": "2026-01-01T00:00:01Z"
          }
        ]
        """
        try FileManager.default.createDirectory(
            at: KeyboardSharedStore.storageDirectoryURL(in: containerURL),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: KeyboardSharedStore.diagnosticsURL(in: containerURL))

        let diagnostics = try KeyboardSharedStore.readDiagnostics(from: containerURL)
        #expect(diagnostics.map(\.id) == ["current-launch", "current-finish"])
        #expect(try KeyboardSharedStore.sanitizeDiagnostics(in: containerURL) == 1)

        let sanitizedData = try Data(contentsOf: KeyboardSharedStore.diagnosticsURL(in: containerURL))
        let sanitizedJSON = String(decoding: sanitizedData, as: UTF8.self)
        #expect(!sanitizedJSON.contains("removedLegacyEvent"))
        #expect(sanitizedJSON.contains("openAppFailed"))
        #expect(try KeyboardSharedStore.readDiagnostics(from: containerURL) == diagnostics)
    }

    @Test func readsLegacyRootPayloadDuringStorageMigration() throws {
        let containerURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let legacyURL = containerURL.appendingPathComponent(
            KeyboardSharedStore.payloadFileName,
            isDirectory: false
        )
        let payload = KeyboardSharedPayload(
            latestDraft: nil,
            shortcuts: [],
            session: .ready(updatedAt: Date(timeIntervalSince1970: 1_777_700)),
            updatedAt: Date(timeIntervalSince1970: 1_777_700)
        )
        try KeyboardSharedStore.write(payload, to: containerURL)
        try FileManager.default.moveItem(
            at: KeyboardSharedStore.payloadURL(in: containerURL),
            to: legacyURL
        )

        #expect(try KeyboardSharedStore.read(from: containerURL) == payload)

        try KeyboardSharedStore.clear(from: containerURL)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func primaryKeyboardActionGuidesQuickStartInsteadOfLaunchingTheApp() {
        let idle = KeyboardSessionPayload(
            state: .ready,
            startedAt: nil,
            resultText: nil,
            errorText: nil,
            updatedAt: Date()
        )

        #expect(KeyboardPrimaryActionResolver.action(for: idle) == .quickStart)
    }

    @Test func completedSessionResultNeverFallsBackToHistoricalContent() {
        #expect(
            KeyboardSessionContinuity.completedSessionResult(
                latestDraft: " Current result ",
                inMemoryResult: "In-memory result"
            ) == "Current result"
        )
        #expect(
            KeyboardSessionContinuity.completedSessionResult(
                latestDraft: " ",
                inMemoryResult: " In-memory result "
            ) == "In-memory result"
        )
        #expect(
            KeyboardSessionContinuity.completedSessionResult(
                latestDraft: nil,
                inMemoryResult: " "
            ) == nil
        )
    }

    @Test func primaryKeyboardActionTracksTheActiveSessionLifecycle() {
        func session(_ state: KeyboardSessionState, result: String? = nil) -> KeyboardSessionPayload {
            KeyboardSessionPayload(
                state: state,
                startedAt: state == .listening ? Date() : nil,
                resultText: result,
                errorText: nil,
                updatedAt: Date()
            )
        }

        #expect(KeyboardPrimaryActionResolver.action(for: session(.opening)) == .wait)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.warming)) == .wait)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.listening)) == .finish)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.processing)) == .wait)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.insertReady, result: "Ready")) == .insertResult)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.insertReady, result: "  ")) == .quickStart)
        #expect(KeyboardPrimaryActionResolver.action(for: session(.error)) == .attention)
    }

    @Test func matchingInsertedSessionCannotBeReinsertedByAnAppRefresh() {
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let existing = KeyboardSessionPayload(
            state: .inserted,
            startedAt: startedAt,
            resultText: "Insert once.",
            errorText: nil,
            updatedAt: startedAt.addingTimeInterval(4),
            sessionID: "session-a"
        )
        let matchingCandidate = KeyboardSessionPayload(
            state: .insertReady,
            startedAt: startedAt,
            resultText: "Insert once.",
            errorText: nil,
            updatedAt: startedAt.addingTimeInterval(5),
            sessionID: "session-a",
            automaticInsertionRequestedAt: startedAt.addingTimeInterval(5)
        )
        let nextSessionCandidate = KeyboardSessionPayload(
            state: .insertReady,
            startedAt: startedAt.addingTimeInterval(10),
            resultText: "Insert once.",
            errorText: nil,
            updatedAt: startedAt.addingTimeInterval(15),
            sessionID: "session-b",
            automaticInsertionRequestedAt: startedAt.addingTimeInterval(15)
        )

        let preserved = KeyboardSessionContinuity.preservingInsertedResult(
            candidate: matchingCandidate,
            existing: existing
        )
        let nextSession = KeyboardSessionContinuity.preservingInsertedResult(
            candidate: nextSessionCandidate,
            existing: existing
        )

        #expect(preserved.state == .inserted)
        #expect(preserved.sessionID == "session-a")
        #expect(preserved.automaticInsertionRequestedAt == nil)
        #expect(nextSession == nextSessionCandidate)
    }

    @Test func automaticInsertionIsShortLivedAndSessionScoped() {
        let readyAt = Date(timeIntervalSince1970: 3_000)
        let session = KeyboardSessionPayload(
            state: .insertReady,
            startedAt: readyAt.addingTimeInterval(-5),
            resultText: "Ready now.",
            errorText: nil,
            updatedAt: readyAt,
            sessionID: "session-a",
            automaticInsertionRequestedAt: readyAt
        )
        let missingIdentity = KeyboardSessionPayload(
            state: .insertReady,
            startedAt: nil,
            resultText: "Ready now.",
            errorText: nil,
            updatedAt: readyAt,
            automaticInsertionRequestedAt: readyAt
        )

        #expect(
            KeyboardSessionContinuity.shouldAutomaticallyInsert(
                session,
                now: readyAt.addingTimeInterval(VyrraSessionPolicy.automaticInsertionWindow - 1)
            )
        )
        #expect(
            !KeyboardSessionContinuity.shouldAutomaticallyInsert(
                session,
                now: readyAt.addingTimeInterval(VyrraSessionPolicy.automaticInsertionWindow + 1)
            )
        )
        #expect(!KeyboardSessionContinuity.shouldAutomaticallyInsert(missingIdentity, now: readyAt))
    }

    @Test func staleOrMismatchedKeyboardCommandsCannotStopANewerSession() {
        let requestedAt = Date(timeIntervalSince1970: 4_000)
        let current = KeyboardSessionCommand(
            id: "current",
            type: .finish,
            requestedAt: requestedAt,
            sessionID: "session-a"
        )
        let legacy = KeyboardSessionCommand(
            id: "legacy",
            type: .cancel,
            requestedAt: requestedAt
        )
        let expiresQuickly = KeyboardSessionCommand(
            type: .finish,
            requestedAt: requestedAt,
            sessionID: "session-a",
            expiresAt: requestedAt.addingTimeInterval(VyrraSessionPolicy.keyboardTapResponseWindow)
        )

        #expect(
            !KeyboardSessionContinuity.commandTargetsActiveSession(
                expiresQuickly,
                activeSessionID: "session-a",
                now: requestedAt.addingTimeInterval(VyrraSessionPolicy.keyboardTapResponseWindow)
            )
        )

        #expect(
            KeyboardSessionContinuity.commandTargetsActiveSession(
                current,
                activeSessionID: "session-a",
                now: requestedAt.addingTimeInterval(10)
            )
        )
        #expect(
            !KeyboardSessionContinuity.commandTargetsActiveSession(
                current,
                activeSessionID: "session-b",
                now: requestedAt.addingTimeInterval(10)
            )
        )
        #expect(
            !KeyboardSessionContinuity.commandTargetsActiveSession(
                current,
                activeSessionID: "session-a",
                now: requestedAt.addingTimeInterval(VyrraSessionPolicy.commandFreshnessWindow + 1)
            )
        )
        #expect(
            KeyboardSessionContinuity.commandTargetsActiveSession(
                legacy,
                activeSessionID: "session-a",
                now: requestedAt.addingTimeInterval(10)
            )
        )
        #expect(
            !KeyboardSessionContinuity.commandTargetsActiveSession(
                legacy,
                activeSessionID: nil,
                now: requestedAt.addingTimeInterval(10)
            )
        )
    }

    @Test func doubleSpacePeriodRequiresRapidUnchangedTextContext() {
        let firstTapAt = Date(timeIntervalSince1970: 5_000)
        let tap = KeyboardSpaceTap(
            occurredAt: firstTapAt,
            expectedContextBeforeInput: "Hello ",
            expectedContextAfterInput: ""
        )

        #expect(
            KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
                after: tap,
                contextBeforeInput: "Hello ",
                contextAfterInput: "",
                selectedText: nil,
                now: firstTapAt.addingTimeInterval(0.2)
            )
        )
        #expect(
            !KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
                after: tap,
                contextBeforeInput: "Hello ",
                contextAfterInput: "",
                selectedText: nil,
                now: firstTapAt.addingTimeInterval(0.6)
            )
        )
        #expect(
            !KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
                after: tap,
                contextBeforeInput: "Different ",
                contextAfterInput: "",
                selectedText: nil,
                now: firstTapAt.addingTimeInterval(0.2)
            )
        )
        #expect(
            !KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
                after: tap,
                contextBeforeInput: "Hello ",
                contextAfterInput: "",
                selectedText: "Hello",
                now: firstTapAt.addingTimeInterval(0.2)
            )
        )
        #expect(
            !KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
                after: tap,
                contextBeforeInput: "Hello ",
                contextAfterInput: "moved",
                selectedText: nil,
                now: firstTapAt.addingTimeInterval(0.2)
            )
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyrraKeyboardSharedStore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
