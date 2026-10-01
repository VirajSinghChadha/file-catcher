import Foundation

enum Scanner {

    /// Recursively scans `root` and returns every regular file found, with its size.
    /// Reports periodic progress via `onProgress` (files scanned so far).
    static func scanAllFiles(
        root: URL,
        onProgress: @escaping (Int) -> Void
    ) -> [FileEntry] {
        var results: [FileEntry] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return results }

        var scanned = 0
        for case let fileURL as URL in enumerator {
            scanned += 1
            if scanned % 500 == 0 { onProgress(scanned) }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, let size = values.fileSize {
                results.append(FileEntry(url: fileURL, size: Int64(size)))
            }
        }
        onProgress(scanned)
        return results
    }

    /// Finds well-known clutter locations that tend to accumulate many small files.
    static func scanClutterCategories(onProgress: @escaping (String) -> Void) -> [ClutterCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var categories: [ClutterCategory] = []

        func collect(_ dir: URL, maxDepth: Int = 6) -> [FileEntry] {
            guard fm.fileExists(atPath: dir.path) else { return [] }
            var entries: [FileEntry] = []
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) else { return [] }
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isRegularFile == true, let size = values.fileSize {
                    entries.append(FileEntry(url: fileURL, size: Int64(size)))
                }
            }
            return entries
        }

        onProgress("User Caches (~/Library/Caches)")
        let caches = collect(home.appendingPathComponent("Library/Caches"))
        if !caches.isEmpty {
            categories.append(ClutterCategory(
                id: "caches", title: "App Caches",
                detail: "Cached data apps can safely regenerate",
                files: caches))
        }

        onProgress("Logs (~/Library/Logs)")
        let logs = collect(home.appendingPathComponent("Library/Logs"))
        if !logs.isEmpty {
            categories.append(ClutterCategory(
                id: "logs", title: "Log Files",
                detail: "Diagnostic logs from apps and the system",
                files: logs))
        }

        onProgress("Xcode DerivedData")
        let derivedData = collect(home.appendingPathComponent("Library/Developer/Xcode/DerivedData"))
        if !derivedData.isEmpty {
            categories.append(ClutterCategory(
                id: "deriveddata", title: "Xcode Derived Data",
                detail: "Build artifacts Xcode regenerates automatically",
                files: derivedData))
        }

        onProgress("iOS Simulator data")
        let simCaches = collect(home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"))
        if !simCaches.isEmpty {
            categories.append(ClutterCategory(
                id: "simcaches", title: "Simulator Caches",
                detail: "Cached data for iOS Simulator devices",
                files: simCaches))
        }

        onProgress(".DS_Store files")
        var dsStores: [FileEntry] = []
        for base in [home.appendingPathComponent("Desktop"), home.appendingPathComponent("Documents"),
                     home.appendingPathComponent("Downloads"), home] {
            guard let enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: []
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == ".DS_Store",
                   let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize {
                    dsStores.append(FileEntry(url: fileURL, size: Int64(size)))
                }
            }
        }
        if !dsStores.isEmpty {
            categories.append(ClutterCategory(
                id: "dsstore", title: ".DS_Store Files",
                detail: "Finder metadata files scattered across folders",
                files: dsStores))
        }

        onProgress("Trash")
        let trash = collect(home.appendingPathComponent(".Trash"))
        if !trash.isEmpty {
            categories.append(ClutterCategory(
                id: "trash", title: "Trash",
                detail: "Items already in Trash, not yet emptied",
                files: trash))
        }

        onProgress("Old Downloads (unmodified 90+ days)")
        let downloadsDir = home.appendingPathComponent("Downloads")
        var oldDownloads: [FileEntry] = []
        if let enumerator = fm.enumerator(
            at: downloadsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) {
            let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                ) else { continue }
                if values.isRegularFile == true,
                   let size = values.fileSize,
                   let modDate = values.contentModificationDate,
                   modDate < cutoff {
                    oldDownloads.append(FileEntry(url: fileURL, size: Int64(size)))
                }
            }
        }
        if !oldDownloads.isEmpty {
            categories.append(ClutterCategory(
                id: "olddownloads", title: "Old Downloads",
                detail: "Files in Downloads untouched for 90+ days",
                files: oldDownloads))
        }

        return categories
    }

    static func moveToTrash(_ entries: [FileEntry]) -> (succeeded: [FileEntry], failed: [(FileEntry, Error)]) {
        var succeeded: [FileEntry] = []
        var failed: [(FileEntry, Error)] = []
        for entry in entries {
            do {
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                succeeded.append(entry)
            } catch {
                failed.append((entry, error))
            }
        }
        return (succeeded, failed)
    }
}
