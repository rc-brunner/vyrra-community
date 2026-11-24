import XCTest
@testable import Vyrra

final class ModelCacheStoreTests: XCTestCase {
    func testRoundedStorageLabelUsesHumanScale() {
        XCTAssertEqual(ModelCacheStore.roundedStorageLabel(bytes: 3_819_780_000_000), "3.8 TB")
        XCTAssertEqual(ModelCacheStore.roundedStorageLabel(bytes: 128_400_000_000), "128 GB")
        XCTAssertEqual(ModelCacheStore.roundedStorageLabel(bytes: 8_450_000_000), "8.5 GB")
        XCTAssertEqual(ModelCacheStore.roundedStorageLabel(bytes: 734_000_000), "734 MB")
    }

    func testSaveMarksModelFolderExcludedFromBackup() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-backup-\(UUID().uuidString)"
        let directory = try makeUsableModelDirectory(fileManager: fileManager)

        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: directory)
        }

        ModelCacheStore.save(folder: directory, for: modelName)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testDeleteCachedModelsRemovesMultipleFoldersAndMetadata() throws {
        let fileManager = FileManager.default
        let firstModelName = "test-model-a-\(UUID().uuidString)"
        let secondModelName = "test-model-b-\(UUID().uuidString)"
        let firstDirectory = try makeUsableModelDirectory(fileManager: fileManager)
        let secondDirectory = try makeUsableModelDirectory(fileManager: fileManager)

        defer {
            ModelCacheStore.clearMetadata(for: firstModelName)
            ModelCacheStore.clearMetadata(for: secondModelName)
            try? fileManager.removeItem(at: firstDirectory)
            try? fileManager.removeItem(at: secondDirectory)
        }

        ModelCacheStore.save(folder: firstDirectory, for: firstModelName)
        ModelCacheStore.save(folder: secondDirectory, for: secondModelName)

        XCTAssertTrue(ModelCacheStore.summary(for: firstModelName).isUsable)
        XCTAssertTrue(ModelCacheStore.summary(for: secondModelName).isUsable)

        let deletedCount = ModelCacheStore.deleteCachedModels(for: [firstModelName, secondModelName])

        XCTAssertEqual(deletedCount, 2)
        XCTAssertFalse(fileManager.fileExists(atPath: firstDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: secondDirectory.path))
        XCTAssertFalse(ModelCacheStore.summary(for: firstModelName).isUsable)
        XCTAssertFalse(ModelCacheStore.summary(for: secondModelName).isUsable)
    }

    func testDeleteCachedModelKeepsMetadataWhenFolderIsNotManaged() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-unmanaged-\(UUID().uuidString)"
        let directory = try makeUsableModelDirectory(
            fileManager: fileManager,
            parent: try unmanagedModelParent(fileManager: fileManager)
        )

        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: directory)
        }

        ModelCacheStore.save(folder: directory, for: modelName)

        XCTAssertTrue(ModelCacheStore.summary(for: modelName).isUsable)
        XCTAssertFalse(ModelCacheStore.deleteCachedModel(for: modelName))
        XCTAssertTrue(fileManager.fileExists(atPath: directory.path))
        XCTAssertTrue(ModelCacheStore.summary(for: modelName).isUsable)
    }

    func testDeleteCachedModelsReportsOnlySuccessfulDeletes() throws {
        let fileManager = FileManager.default
        let managedModelName = "test-model-managed-\(UUID().uuidString)"
        let unmanagedModelName = "test-model-unmanaged-\(UUID().uuidString)"
        let managedDirectory = try makeUsableModelDirectory(fileManager: fileManager)
        let unmanagedDirectory = try makeUsableModelDirectory(
            fileManager: fileManager,
            parent: try unmanagedModelParent(fileManager: fileManager)
        )

        defer {
            ModelCacheStore.clearMetadata(for: managedModelName)
            ModelCacheStore.clearMetadata(for: unmanagedModelName)
            try? fileManager.removeItem(at: managedDirectory)
            try? fileManager.removeItem(at: unmanagedDirectory)
        }

        ModelCacheStore.save(folder: managedDirectory, for: managedModelName)
        ModelCacheStore.save(folder: unmanagedDirectory, for: unmanagedModelName)

        let deletedCount = ModelCacheStore.deleteCachedModels(for: [
            managedModelName,
            unmanagedModelName
        ])

        XCTAssertEqual(deletedCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: managedDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unmanagedDirectory.path))
        XCTAssertFalse(ModelCacheStore.summary(for: managedModelName).isUsable)
        XCTAssertTrue(ModelCacheStore.summary(for: unmanagedModelName).isUsable)
    }

    func testTemporaryCacheUnavailabilityDoesNotEraseMetadata() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-protected-\(UUID().uuidString)"
        let directory = try makeUsableModelDirectory(fileManager: fileManager)

        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: directory)
        }

        ModelCacheStore.save(folder: directory, for: modelName)
        try fileManager.removeItem(at: directory)

        XCTAssertFalse(ModelCacheStore.summary(for: modelName).isUsable)

        try makeUsableModelDirectory(fileManager: fileManager, at: directory)
        XCTAssertTrue(ModelCacheStore.summary(for: modelName).isUsable)
    }

    func testRecoversDownloadedModelWhenMetadataIsMissing() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-recovery-\(UUID().uuidString)"
        let downloadBase = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraRecovery-\(UUID().uuidString)", isDirectory: true)
        let recoveredDirectory = downloadBase
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(modelName)", isDirectory: true)
        try makeUsableModelDirectory(fileManager: fileManager, at: recoveredDirectory)

        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: downloadBase)
        }

        ModelCacheStore.clearMetadata(for: modelName)
        let recovered = ModelCacheStore.recoverCachedFolder(
            for: modelName,
            downloadBase: downloadBase,
            fileManager: fileManager
        )

        XCTAssertEqual(recovered?.standardizedFileURL, recoveredDirectory.standardizedFileURL)
        XCTAssertEqual(ModelCacheStore.cachedFolder(for: modelName)?.standardizedFileURL, recoveredDirectory.standardizedFileURL)
    }

    func testTokenizerCacheFolderUsesWhisperTokenizerRepoForModelFamily() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyrraTokenizerBase-\(UUID().uuidString)", isDirectory: true)

        XCTAssertEqual(
            ModelCacheStore.tokenizerCacheFolder(
                for: SpeechModel.recommendedLarge.rawValue,
                downloadBase: base
            ).path,
            base.appendingPathComponent("models/openai/whisper-large-v3", isDirectory: true).path
        )
        XCTAssertEqual(
            ModelCacheStore.tokenizerCacheFolder(for: SpeechModel.liteSmall.rawValue, downloadBase: base).path,
            base.appendingPathComponent("models/openai/whisper-small", isDirectory: true).path
        )
        XCTAssertEqual(
            ModelCacheStore.tokenizerCacheFolder(for: SpeechModel.debugTiny.rawValue, downloadBase: base).path,
            base.appendingPathComponent("models/openai/whisper-tiny", isDirectory: true).path
        )
    }

    func testDeleteTokenizerCacheRemovesOnlyTargetTokenizerFolder() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraTokenizerBase-\(UUID().uuidString)", isDirectory: true)
        let largeTokenizerFolder = ModelCacheStore.tokenizerCacheFolder(
            for: SpeechModel.recommendedLarge.rawValue,
            downloadBase: base
        )
        let tinyTokenizerFolder = ModelCacheStore.tokenizerCacheFolder(
            for: SpeechModel.debugTiny.rawValue,
            downloadBase: base
        )

        defer {
            try? fileManager.removeItem(at: base)
        }

        try fileManager.createDirectory(at: largeTokenizerFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tinyTokenizerFolder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: largeTokenizerFolder.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: tinyTokenizerFolder.appendingPathComponent("tokenizer.json"))

        XCTAssertTrue(ModelCacheStore.deleteTokenizerCache(
            for: SpeechModel.recommendedLarge.rawValue,
            downloadBase: base
        ))

        XCTAssertFalse(fileManager.fileExists(atPath: largeTokenizerFolder.path))
        XCTAssertTrue(fileManager.fileExists(atPath: tinyTokenizerFolder.path))
    }

    private func makeUsableModelDirectory(
        fileManager: FileManager,
        parent: URL? = nil
    ) throws -> URL {
        let directory = (parent ?? fileManager.temporaryDirectory)
            .appendingPathComponent("VyrraModelCache-\(UUID().uuidString)", isDirectory: true)
        try makeUsableModelDirectory(fileManager: fileManager, at: directory)
        return directory
    }

    private func makeUsableModelDirectory(
        fileManager: FileManager,
        at directory: URL
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for artifact in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(artifact, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func unmanagedModelParent(fileManager: FileManager) throws -> URL {
        try XCTUnwrap(fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first)
    }
}
