import Foundation
import Combine

struct LCAppStorageItem: Identifiable {
    let id: UUID

    let appModel: LCAppModel
    let bundleSize: Int64?
    let containersSize: Int64

    let totalSize: Int64

    let containerDetails: [LCAppStorageContainerItem]
}

struct LCAppStorageContainerItem: Identifiable {
    let id: UUID
    let name: String
    let size: Int64
    let isExternalContainer: Bool
}

struct LCStorageBreakdown {
    let totalSize: Int64
    let appBundleSize: Int64
    let containersSize: Int64
    let temporaryFilesSize: Int64
    let appGroupSize: Int64
    let tweaksSize: Int64
    let otherSize: Int64

    let appItems: [LCAppStorageItem]
}

@MainActor
final class LCStorageManagementModel: ObservableObject {
    @Published var lastCalculated: Date?
    private static var cached: (key: String, value: LCStorageBreakdown, date: Date, skipped: Int)?
    private static let scans = StrataStorageScanCoordinator<(LCStorageBreakdown, Int)>()
    @Published private(set) var skippedEntries = 0
    @Published var breakdown: LCStorageBreakdown?
    @Published var isCalculating = false
    @Published private(set) var scannedItems = 0
    @Published var errorInfo: String?

    func refresh(apps: [LCAppModel], hiddenApps: [LCAppModel], force: Bool = false) async {
        guard !isCalculating else {
            return
        }

        let unlocked = DataManager.shared.model.isHiddenAppUnlocked
        let visible = apps + (unlocked ? hiddenApps : [])
        let key = visible.map { liveBoardAppKey($0) + $0.uiContainers.map { $0.folderName }.joined() }.sorted().joined(separator: "|") + String(unlocked)
        if let cached = Self.cached, cached.key == key {
            breakdown = cached.value; lastCalculated = cached.date; skippedEntries = cached.skipped
            if !force && Date().timeIntervalSince(cached.date) < 300 { return }
        } else { breakdown = nil; lastCalculated = nil }
        isCalculating = true
        scannedItems = 0
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scannedItems = StrataStorageIndex.shared.progress.scanned
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        defer { isCalculating = false; progressTask.cancel() }
        errorInfo = nil
        let maxAge: TimeInterval = force ? 0 : 300

        do {
            let result = try await Self.scans.run(key: key) {
                try await StrataStorageIndex.shared.prepare([LCPath.docPath, LCPath.lcGroupDocPath, FileManager.default.temporaryDirectory] + FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask), maxAge: maxAge)
                let value = try await Self.calculateBreakdown(apps: apps, hiddenApps: hiddenApps)
                return (value, await StrataStorageIndex.shared.skippedEntries)
            }
            let value = result.0
            skippedEntries = result.1
            guard unlocked == DataManager.shared.model.isHiddenAppUnlocked else { breakdown = nil; lastCalculated = nil; return }
            breakdown = value; lastCalculated = Date()
            Self.cached = (key, value, lastCalculated!, skippedEntries)
        } catch {
            errorInfo = error.localizedDescription
        }
    }

    func clearForPrivacyChange() { breakdown = nil; lastCalculated = nil; Self.cached = nil; Self.scans.cancel() }

    private enum StorageCategory {
        case appBundle
        case containers
        case temporaryFiles
        case appGroup
        case tweaks
    }

    nonisolated private static func calculateBreakdown(apps: [LCAppModel], hiddenApps: [LCAppModel]) async throws -> LCStorageBreakdown {
        var allApps: [LCAppModel]
        if DataManager.shared.model.isHiddenAppUnlocked {
            allApps = apps + hiddenApps
        } else {
            allApps = apps
        }
        
        if UserDefaults.sideStoreExist() {
            allApps.append(LCAppModel(appInfo: BuiltInSideStoreAppInfo.shared))
        }

        // Show per-app bundle usage only when every installed app has a reliable bundle path.
        let appItems = try await calculateAppItems(
            from: allApps
        )

        var sizesByCategory: [StorageCategory: Int64] = [:]
        
        let knownRoots = uniquePaths([LCPath.docPath, LCPath.lcGroupDocPath])
        let bundleRoots = uniquePaths([LCPath.bundlePath, LCPath.lcGroupBundlePath])
        let containerRoots = uniquePaths([LCPath.dataPath, LCPath.lcGroupDataPath])
        let appGroupRoots = uniquePaths([LCPath.appGroupPath, LCPath.lcGroupAppGroupPath])
        let tweakRoots = uniquePaths([LCPath.tweakPath, LCPath.lcGroupTweakPath])
        
        
        sizesByCategory[.appBundle] = 0
        sizesByCategory[.containers] = 0
        
        var sideStoreContainerSize: Int64 = 0
        for appItem in appItems {
            if !(appItem.appModel.appInfo is BuiltInSideStoreAppInfo) {
                sizesByCategory[.appBundle]! += appItem.bundleSize ?? 0
            } else {
                sideStoreContainerSize = appItem.containersSize
            }
            
            for containerDetail in appItem.containerDetails {
                if containerDetail.isExternalContainer {
                    continue
                }
                sizesByCategory[.containers]! += containerDetail.size
            }
        }

        try await withThrowingTaskGroup(of: (StorageCategory, Int64).self) { group in

            group.addTask(priority: .utility) {
                (.temporaryFiles, try await calculateSize(at: FileManager.default.temporaryDirectory))
            }

            group.addTask(priority: .utility) {
                (.appGroup, try await calculateCombinedSize(of: appGroupRoots))
            }

            group.addTask(priority: .utility) {
                // Surface tweaks as a top-level bucket so managed tweak storage does not disappear into Other.
                (.tweaks, try await calculateCombinedSize(of: tweakRoots))
            }

            for try await (category, size) in group {
                sizesByCategory[category] = size
            }
        }

        let appBundleSize = sizesByCategory[.appBundle] ?? 0
        let containersSize = sizesByCategory[.containers] ?? 0
        let temporaryFilesSize = sizesByCategory[.temporaryFiles] ?? 0
        let appGroupSize = sizesByCategory[.appGroup] ?? 0
        let tweaksSize = sizesByCategory[.tweaks] ?? 0
        let knownRootsSize = try await calculateCombinedSize(of: knownRoots)
        var librarySize: Int64 = 0
        if let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            librarySize = try await calculateSize(at: libraryPath)
        }
        // Other is the residual after explicit categories are removed from the known storage roots, plus loose root-level files.
        let residualOtherSize = knownRootsSize - appBundleSize - containersSize - appGroupSize - tweaksSize
        let otherSize = residualOtherSize + librarySize

        return LCStorageBreakdown(
            totalSize: appBundleSize + containersSize + temporaryFilesSize + appGroupSize + tweaksSize + otherSize,
            appBundleSize: appBundleSize,
            containersSize: containersSize,
            temporaryFilesSize: temporaryFilesSize,
            appGroupSize: appGroupSize,
            tweaksSize: tweaksSize,
            otherSize: otherSize,
            appItems: appItems
        )
    }

    nonisolated private static func calculateAppItem(
        from input: LCAppModel,
    ) async throws -> LCAppStorageItem {
        var containerDetails: [LCAppStorageContainerItem] = []
        containerDetails.reserveCapacity(input.uiContainers.count)

        var containersSize: Int64 = 0
        for container in input.uiContainers {
            if container.bookmarkResolved {
                let _ = container.containerURL.startAccessingSecurityScopedResource()
            }
            
            let size = try await calculateSize(at: container.containerURL)
            
            if container.bookmarkResolved {
                container.containerURL.stopAccessingSecurityScopedResource()
            }
            
            if container.storageBookMark == nil {
                containersSize += size
            }
            containerDetails.append(
                LCAppStorageContainerItem(
                    id: UUID(),
                    name: container.name,
                    size: size,
                    isExternalContainer: container.storageBookMark != nil
                )
            )
        }


        let bundleSize: Int64?
        if let bundlePath = input.appInfo.bundlePath() {
            bundleSize = try await calculateSize(at: URL(fileURLWithPath: bundlePath))
        } else {
            bundleSize = nil
        }
        
        let totalSize: Int64
        if input.appInfo is BuiltInSideStoreAppInfo {
            totalSize = containersSize
        } else {
            totalSize = (bundleSize ?? 0) + containersSize
        }

        return LCAppStorageItem(
            id: UUID(),
            appModel: input,
            bundleSize: bundleSize,
            containersSize: containersSize,
            totalSize: totalSize,
            containerDetails: containerDetails
        )
    }

    nonisolated private static func calculateAppItems(
        from inputs: [LCAppModel]
    ) async throws -> [LCAppStorageItem] {
        var appItems: [LCAppStorageItem] = []
        appItems.reserveCapacity(inputs.count)

        try await withThrowingTaskGroup(of: LCAppStorageItem.self) { group in
            for input in inputs {
                group.addTask(priority: .utility) {
                    try await calculateAppItem(
                        from: input
                    )
                }
            }

            for try await item in group {
                appItems.append(item)
            }
        }

        return appItems.sorted {
            if $0.totalSize == $1.totalSize {
                return ($0.appModel.displayName).localizedCaseInsensitiveCompare($1.appModel.displayName) == .orderedAscending
            }
            return $0.totalSize > $1.totalSize
        }
    }

    nonisolated private static func calculateCombinedSize(of urls: [URL]) async throws -> Int64 {
        try await withThrowingTaskGroup(of: Int64.self) { group in
            for url in uniquePaths(urls) {
                group.addTask(priority: .utility) {
                    try await calculateSize(at: url)
                }
            }

            var totalSize: Int64 = 0
            for try await size in group {
                totalSize += size
            }
            return totalSize
        }
    }

    nonisolated private static func uniquePaths(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardizedPath = url.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    nonisolated private static func calculateSize(at url: URL) async throws -> Int64 {
        if let indexed = await StrataStorageIndex.shared.size(url) { return indexed }
        return try await calculateUnindexedSize(at: url)
    }

    nonisolated private static func calculateUnindexedSize(at url: URL) async throws -> Int64 {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }
            guard resourceValues.isRegularFile == true else {
                continue
            }

            let fileSize = resourceValues.totalFileAllocatedSize
                ?? resourceValues.fileAllocatedSize
                ?? resourceValues.fileSize
                ?? 0
            totalSize += Int64(fileSize)
        }

        return totalSize
    }
}
