import Foundation
import XCTest
@testable import Vyrra

final class PendingRecordingStoreTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUpWithError() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
    }

    func testStageMovesRecordingAndRoundTripsMetadata() throws {
        let sourceURL = rootDirectory.appendingPathComponent("source.caf")
        try Data("audio".utf8).write(to: sourceURL)
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)
        let createdAt = Date(timeIntervalSince1970: 2_000)

        let staged = try PendingRecordingStore.stage(
            RecordingResult(url: sourceURL, duration: 14.5),
            createdAt: createdAt,
            in: pendingDirectory
        )
        let loaded = try XCTUnwrap(
            PendingRecordingStore.load(
                now: Date(timeIntervalSince1970: 2_100),
                in: pendingDirectory
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.result.url.path))
        XCTAssertEqual(loaded.result.url, staged.result.url)
        XCTAssertEqual(loaded.result.duration, 14.5, accuracy: 0.001)
        XCTAssertEqual(loaded.createdAt, createdAt)
    }

    func testRestagingAlreadyProtectedRecordingKeepsAudioAvailable() throws {
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        let protectedAudioURL = pendingDirectory.appendingPathComponent("recording.caf")
        try Data("audio".utf8).write(to: protectedAudioURL)
        let createdAt = Date(timeIntervalSince1970: 2_000)

        let staged = try PendingRecordingStore.stage(
            RecordingResult(url: protectedAudioURL, duration: 8),
            createdAt: createdAt,
            in: pendingDirectory
        )
        let loaded = PendingRecordingStore.load(
            now: createdAt.addingTimeInterval(10),
            in: pendingDirectory
        )

        XCTAssertEqual(staged.result.url, protectedAudioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedAudioURL.path))
        XCTAssertEqual(loaded?.result.duration, 8)
    }

    func testFailedStageRemovesPartialDestination() {
        let missingSourceURL = rootDirectory.appendingPathComponent("missing.caf")
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)

        XCTAssertThrowsError(
            try PendingRecordingStore.stage(
                RecordingResult(url: missingSourceURL, duration: 8),
                in: pendingDirectory
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingDirectory.path))
    }

    func testExpiredRecordingIsRemoved() throws {
        let sourceURL = rootDirectory.appendingPathComponent("source.caf")
        try Data("audio".utf8).write(to: sourceURL)
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)
        let createdAt = Date(timeIntervalSince1970: 2_000)

        _ = try PendingRecordingStore.stage(
            RecordingResult(url: sourceURL, duration: 2),
            createdAt: createdAt,
            in: pendingDirectory
        )
        let loaded = PendingRecordingStore.load(
            now: createdAt.addingTimeInterval(PendingRecordingStore.retentionInterval + 1),
            in: pendingDirectory
        )

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingDirectory.path))
    }

    func testRetentionWindowRejectsExpiredAndImplausiblyFutureMetadata() {
        let createdAt = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(
            PendingRecordingStore.isRetainable(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(PendingRecordingStore.retentionInterval)
            )
        )
        XCTAssertFalse(
            PendingRecordingStore.isRetainable(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(PendingRecordingStore.retentionInterval + 1)
            )
        )
        XCTAssertFalse(
            PendingRecordingStore.isRetainable(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(-5 * 60 - 1)
            )
        )
    }

    func testMissingAudioInvalidatesMetadata() throws {
        let sourceURL = rootDirectory.appendingPathComponent("source.caf")
        try Data("audio".utf8).write(to: sourceURL)
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)

        let staged = try PendingRecordingStore.stage(
            RecordingResult(url: sourceURL, duration: 2),
            in: pendingDirectory
        )
        try FileManager.default.removeItem(at: staged.result.url)

        XCTAssertNil(PendingRecordingStore.load(in: pendingDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingDirectory.path))
    }

    func testDiscardRemovesOnlyPendingDirectory() throws {
        let pendingDirectory = rootDirectory.appendingPathComponent("pending", isDirectory: true)
        let unrelatedURL = rootDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelatedURL)

        try PendingRecordingStore.discard(in: pendingDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }
}
