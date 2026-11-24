import Foundation

struct PendingRecordingSnapshot {
    let result: RecordingResult
    let createdAt: Date
}

enum PendingRecordingStore {
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    private enum StoreError: Error {
        case recordingUnavailable
    }

    private static let directoryName = "PendingDictation"
    private static let audioFileName = "recording.caf"
    private static let metadataFileName = "metadata.json"
    private static let metadataVersion = 1

    private struct Metadata: Codable {
        let version: Int
        let createdAt: Date
        let duration: TimeInterval
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func stage(
        _ result: RecordingResult,
        createdAt: Date = Date(),
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PendingRecordingSnapshot {
        let targetDirectory = try directory ?? defaultDirectoryURL(fileManager: fileManager)
        let targetAudioURL = audioURL(in: targetDirectory)
        let sourceIsTarget = result.url.standardizedFileURL == targetAudioURL.standardizedFileURL

        if !sourceIsTarget {
            try discard(in: targetDirectory, fileManager: fileManager)
        }
        try fileManager.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )

        do {
            if !sourceIsTarget {
                try fileManager.copyItem(at: result.url, to: targetAudioURL)
            }
            guard fileManager.fileExists(atPath: targetAudioURL.path) else {
                throw StoreError.recordingUnavailable
            }

            let metadata = Metadata(
                version: metadataVersion,
                createdAt: createdAt,
                duration: result.duration
            )
            let metadataData = try JSONEncoder.pendingRecording.encode(metadata)
            try metadataData.write(
                to: metadataURL(in: targetDirectory),
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            try protectAndExcludeFromBackup(targetAudioURL, fileManager: fileManager)
            try protectAndExcludeFromBackup(metadataURL(in: targetDirectory), fileManager: fileManager)
        } catch {
            if !sourceIsTarget {
                try? discard(in: targetDirectory, fileManager: fileManager)
            }
            throw error
        }

        if !sourceIsTarget {
            try? fileManager.removeItem(at: result.url)
        }

        return PendingRecordingSnapshot(
            result: RecordingResult(url: targetAudioURL, duration: result.duration),
            createdAt: createdAt
        )
    }

    static func load(
        now: Date = Date(),
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> PendingRecordingSnapshot? {
        guard let targetDirectory = try? directory ?? defaultDirectoryURL(fileManager: fileManager) else {
            return nil
        }

        let targetAudioURL = audioURL(in: targetDirectory)
        let targetMetadataURL = metadataURL(in: targetDirectory)
        guard fileManager.fileExists(atPath: targetAudioURL.path),
              fileManager.fileExists(atPath: targetMetadataURL.path),
              let data = try? Data(contentsOf: targetMetadataURL),
              let metadata = try? JSONDecoder.pendingRecording.decode(Metadata.self, from: data)
        else {
            try? discard(in: targetDirectory, fileManager: fileManager)
            return nil
        }

        guard metadata.version == metadataVersion,
              metadata.duration > 0,
              isRetainable(createdAt: metadata.createdAt, now: now)
        else {
            try? discard(in: targetDirectory, fileManager: fileManager)
            return nil
        }

        return PendingRecordingSnapshot(
            result: RecordingResult(url: targetAudioURL, duration: metadata.duration),
            createdAt: metadata.createdAt
        )
    }

    static func isRetainable(
        createdAt: Date,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= -5 * 60 && age <= retentionInterval
    }

    static func discard(
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let targetDirectory = try directory ?? defaultDirectoryURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: targetDirectory.path) else { return }
        try fileManager.removeItem(at: targetDirectory)
    }

    private static func audioURL(in directory: URL) -> URL {
        directory.appendingPathComponent(audioFileName, isDirectory: false)
    }

    private static func metadataURL(in directory: URL) -> URL {
        directory.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    private static func protectAndExcludeFromBackup(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

private extension JSONEncoder {
    static var pendingRecording: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pendingRecording: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
