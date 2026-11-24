import Foundation

struct ModelCacheSummary: Equatable {
    let modelName: String
    let folderPath: String?
    let isUsable: Bool
    let sizeBytes: Int64

    var statusLabel: String {
        isUsable ? "Cached" : "Not Prepared"
    }

    var sizeLabel: String {
        guard isUsable, sizeBytes > 0 else { return "Not Cached" }
        return ModelCacheStore.formattedSize(bytes: sizeBytes)
    }
}

enum ModelCacheStore {
    private static let folderPathsKey = "modelCacheFolderPaths"
    private static let folderSizesKey = "modelCacheFolderSizes"
    private static let preparedAtKey = "modelCachePreparedAt"
    private static let requiredCoreModelNames = [
        "MelSpectrogram",
        "AudioEncoder",
        "TextDecoder"
    ]

    static var hubDownloadBase: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }

    static func cachedFolder(for modelName: String) -> URL? {
        if let path = folderPaths()[modelName] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if folderIsUsable(folder) {
                return folder
            }
        }

        return recoverCachedFolder(for: modelName)
    }

    static func save(folder: URL, for modelName: String) {
        excludeFromBackup(folder)

        var paths = folderPaths()
        paths[modelName] = folder.path
        UserDefaults.standard.set(paths, forKey: folderPathsKey)

        var sizes = folderSizes()
        sizes[modelName] = Double(folderSizeBytes(folder))
        UserDefaults.standard.set(sizes, forKey: folderSizesKey)

        var preparedAt = preparedDates()
        preparedAt[modelName] = Date().timeIntervalSince1970
        UserDefaults.standard.set(preparedAt, forKey: preparedAtKey)
    }

    static func clearMetadata(for modelName: String) {
        var paths = folderPaths()
        paths.removeValue(forKey: modelName)
        UserDefaults.standard.set(paths, forKey: folderPathsKey)

        var sizes = folderSizes()
        sizes.removeValue(forKey: modelName)
        UserDefaults.standard.set(sizes, forKey: folderSizesKey)

        var preparedAt = preparedDates()
        preparedAt.removeValue(forKey: modelName)
        UserDefaults.standard.set(preparedAt, forKey: preparedAtKey)
    }

    @discardableResult
    static func deleteCachedModel(for modelName: String) -> Bool {
        guard let path = folderPaths()[modelName] else { return false }

        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            clearMetadata(for: modelName)
            return true
        }

        guard isManagedCacheFolder(folder) else { return false }

        do {
            try FileManager.default.removeItem(at: folder)
            clearMetadata(for: modelName)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteCachedModels(for modelNames: [String]) -> Int {
        modelNames.reduce(into: 0) { deletedCount, modelName in
            if deleteCachedModel(for: modelName) {
                deletedCount += 1
            }
        }
    }

    @discardableResult
    static func deleteTokenizerCache(for modelName: String) -> Bool {
        deleteTokenizerCache(for: modelName, downloadBase: hubDownloadBase)
    }

    @discardableResult
    static func deleteTokenizerCache(for modelName: String, downloadBase: URL) -> Bool {
        let folder = tokenizerCacheFolder(for: modelName, downloadBase: downloadBase)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }

        do {
            try FileManager.default.removeItem(at: folder)
            return true
        } catch {
            return false
        }
    }

    static func tokenizerCacheFolder(for modelName: String, downloadBase: URL) -> URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(tokenizerRepoPath(for: modelName), isDirectory: true)
    }

    static func summary(for modelName: String) -> ModelCacheSummary {
        let folder = cachedFolder(for: modelName)
        let path = folder?.path
        let isUsable = folder != nil
        let measuredSize = folder.map(folderSizeBytes) ?? 0
        let storedSize = Int64(folderSizes()[modelName] ?? 0)

        return ModelCacheSummary(
            modelName: modelName,
            folderPath: isUsable ? path : nil,
            isUsable: isUsable,
            sizeBytes: max(measuredSize, storedSize)
        )
    }

    static func recoverCachedFolder(
        for modelName: String,
        downloadBase: URL = hubDownloadBase,
        fileManager: FileManager = .default
    ) -> URL? {
        let modelRepository = downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: modelRepository,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let normalizedModelName = modelName.lowercased()
        let recoveredFolder = candidates
            .filter { candidate in
                let name = candidate.lastPathComponent.lowercased()
                let matchesModel = name == normalizedModelName
                    || name.hasSuffix("-\(normalizedModelName)")
                    || name.hasSuffix("_\(normalizedModelName)")
                guard matchesModel,
                      (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { return false }
                return folderIsUsable(candidate)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first

        guard let recoveredFolder else { return nil }
        save(folder: recoveredFolder, for: modelName)
        return recoveredFolder
    }

    static func folderIsUsable(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }

        var foundModelNames = Set<String>()
        for case let url as URL in enumerator {
            let lastPathComponent = url.lastPathComponent
            let nameWithoutExtension = url.deletingPathExtension().lastPathComponent

            for requiredName in requiredCoreModelNames {
                if lastPathComponent == requiredName ||
                    nameWithoutExtension == requiredName ||
                    lastPathComponent.hasPrefix("\(requiredName).") {
                    foundModelNames.insert(requiredName)
                }
            }

            if foundModelNames.count == requiredCoreModelNames.count {
                return true
            }
        }

        return false
    }

    static func folderSizeBytes(_ folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .isDirectoryKey
            ]),
                values.isDirectory != true else {
                continue
            }

            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(size)
        }

        return total
    }

    static func availableStorageBytes() -> Int64? {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }

        return values.volumeAvailableCapacityForImportantUsage
    }

    static func availableStorageLabel() -> String {
        guard let bytes = availableStorageBytes() else { return "Unknown" }
        return roundedStorageLabel(bytes: bytes)
    }

    static func hasEnoughStorage(forModelBytes modelBytes: Int64) -> Bool {
        guard let availableStorageBytes = availableStorageBytes() else { return true }
        let safetyBuffer = Int64(256 * 1_024 * 1_024)
        return availableStorageBytes >= modelBytes + safetyBuffer
    }

    static func formattedSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    static func roundedStorageLabel(bytes: Int64) -> String {
        let bytesValue = Double(bytes)
        let gb = bytesValue / 1_000_000_000
        if gb >= 1_000 {
            return "\(roundedNumber(gb / 1_000, maximumFractionDigits: 1)) TB"
        }

        if gb >= 1 {
            let fractionDigits = gb >= 100 ? 0 : 1
            return "\(roundedNumber(gb, maximumFractionDigits: fractionDigits)) GB"
        }

        let mb = bytesValue / 1_000_000
        return "\(roundedNumber(max(mb, 0), maximumFractionDigits: 0)) MB"
    }

    private static func folderPaths() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: folderPathsKey) as? [String: String] ?? [:]
    }

    private static func folderSizes() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: folderSizesKey) as? [String: Double] ?? [:]
    }

    private static func preparedDates() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: preparedAtKey) as? [String: Double] ?? [:]
    }

    private static func excludeFromBackup(_ folder: URL) {
        var mutableFolder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableFolder.setResourceValues(values)
    }

    private static func tokenizerRepoPath(for modelName: String) -> String {
        let normalized = modelName.lowercased()
        if normalized.contains("large-v3") { return "openai/whisper-large-v3" }
        if normalized.contains("small.en") { return "openai/whisper-small.en" }
        if normalized.contains("small") { return "openai/whisper-small" }
        if normalized.contains("tiny.en") { return "openai/whisper-tiny.en" }
        return "openai/whisper-tiny"
    }

    private static func isManagedCacheFolder(_ folder: URL) -> Bool {
        let folderPath = normalizedPath(folder)
        return removableCacheRoots.contains { root in
            folderPath.hasPrefix("\(root)/")
        }
    }

    private static var removableCacheRoots: [String] {
        let fileManager = FileManager.default
        let roots = [
            fileManager.temporaryDirectory,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap(\.self)

        return roots.map(normalizedPath)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func roundedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }
}
