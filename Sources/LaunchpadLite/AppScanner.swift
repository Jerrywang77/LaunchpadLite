import AppKit

struct AppScanResult {
    let apps: [LaunchpadAppItem]
    let skipped: Int
}

struct AppScanner: Sendable {
    func scan(additionalRoots: [URL] = []) -> AppScanResult {
        let fileManager = FileManager.default
        var appURLs: [URL] = []

        let roots = Self.searchRoots(fileManager: fileManager, additionalRoots: additionalRoots)
        for root in roots where fileManager.fileExists(atPath: root.path) {
            appURLs.append(contentsOf: appBundleURLs(under: root, fileManager: fileManager))
        }

        appURLs = Self.preferringSystemCopies(appURLs)

        var seen = Set<String>()
        var apps: [LaunchpadAppItem] = []
        var skipped = 0

        for url in appURLs {
            guard let bundle = Bundle(url: url) else {
                skipped += 1
                continue
            }

            let info = bundle.infoDictionary ?? [:]
            let isBackgroundOnly = info["LSBackgroundOnly"] as? Bool == true
            let packageType = info["CFBundlePackageType"] as? String

            guard !isBackgroundOnly, packageType == "APPL" else {
                skipped += 1
                continue
            }

            let identifier = bundle.bundleIdentifier ?? url.standardizedFileURL.path
            let deduplicationKey = bundle.bundleIdentifier ?? url.standardizedFileURL.path

            guard seen.insert(deduplicationKey).inserted else {
                skipped += 1
                continue
            }

            let displayName = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? fileManager.displayName(atPath: url.path)
            let resourceValues = try? url.resourceValues(
                forKeys: [
                    .addedToDirectoryDateKey,
                    .creationDateKey,
                    .contentModificationDateKey
                ]
            )
            let installDate = resourceValues?.addedToDirectoryDate
                ?? resourceValues?.creationDate
                ?? resourceValues?.contentModificationDate
                ?? .distantFuture
            let bundleIdentifier = bundle.bundleIdentifier
            let isOfficialApp = Self.isOfficialApp(at: url, bundleIdentifier: bundleIdentifier)

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 128, height: 128)

            apps.append(
                LaunchpadAppItem(
                    id: identifier,
                    url: url,
                    name: displayName,
                    bundleIdentifier: bundleIdentifier,
                    icon: icon,
                    isOfficialApp: isOfficialApp,
                    installDate: installDate,
                    officialOrder: LaunchpadSystemOrder.priority(for: bundleIdentifier)
                )
            )
        }

        apps = Self.sortedApps(apps)

        return AppScanResult(apps: apps, skipped: skipped)
    }

    static func sortedApps(_ apps: [LaunchpadAppItem]) -> [LaunchpadAppItem] {
        apps.sorted { lhs, rhs in
            if lhs.isOfficialApp != rhs.isOfficialApp {
                return lhs.isOfficialApp && !rhs.isOfficialApp
            }

            if lhs.isOfficialApp {
                let lhsOrder = lhs.officialOrder ?? Int.max
                let rhsOrder = rhs.officialOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
            } else if lhs.installDate != rhs.installDate {
                return lhs.installDate < rhs.installDate
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Preinstalled apps live on the read-only system volume; everything under
    /// `/Applications` (including Apple's App Store apps) was installed by hand.
    static func isSystemApp(at url: URL) -> Bool {
        url.path.hasPrefix("/System/")
    }

    /// Apple's own apps. App Store installs such as Pages and Xcode count as
    /// official even though they live in `/Applications`.
    static func isOfficialApp(at url: URL, bundleIdentifier: String?) -> Bool {
        url.path.hasPrefix("/System/") || bundleIdentifier?.hasPrefix("com.apple.") == true
    }

    /// A few apps ship in both `/System` and `/Applications` (Feedback
    /// Assistant). Scanning the system copies first keeps the de-duplication
    /// below from labelling those apps as user installs.
    static func preferringSystemCopies(_ urls: [URL]) -> [URL] {
        urls.filter { isSystemApp(at: $0) } + urls.filter { !isSystemApp(at: $0) }
    }

    static func searchRoots(
        fileManager: FileManager = .default,
        additionalRoots: [URL] = []
    ) -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in additionalRoots where !roots.contains(where: { $0.path == root.path }) {
            roots.append(root)
        }

        return roots
    }

    private func appBundleURLs(under root: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                urls.append(url)
            }
        }

        // The enumerator does not follow symlinks, and macOS ships some system
        // apps (Safari) as symlinks into a cryptex. The URL-based directory
        // listing drops those entries too, so use the path-based API instead.
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.lowercased().hasSuffix(".app") {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            let resolved = candidate.resolvingSymlinksInPath()
            if resolved.path != candidate.path {
                urls.append(resolved)
            }
        }

        return urls
    }
}
