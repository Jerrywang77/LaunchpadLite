import Foundation

/// Persisted icon order. IDs are bundle identifiers (or the file path when an
/// app has no bundle identifier), so the layout survives rescans and relaunches.
struct LaunchpadLayout: Codable, Equatable, Sendable {
    var orderedAppIDs: [String]
    /// First app shown on the page the user pinned as home, if any.
    var homeAnchorID: String?
    /// Apps the user removed from the grid. They stay in `orderedAppIDs` so
    /// restoring one puts it back where it was.
    var hiddenAppIDs: Set<String>
    /// Extra folders to scan for apps, in addition to the built-in locations.
    var extraSearchRoots: [String]

    static let empty = LaunchpadLayout(orderedAppIDs: [])

    init(
        orderedAppIDs: [String],
        homeAnchorID: String? = nil,
        hiddenAppIDs: Set<String> = [],
        extraSearchRoots: [String] = []
    ) {
        self.orderedAppIDs = orderedAppIDs
        self.homeAnchorID = homeAnchorID
        self.hiddenAppIDs = hiddenAppIDs
        self.extraSearchRoots = extraSearchRoots
    }

    /// Layout files written before these fields existed must keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderedAppIDs = try container.decodeIfPresent([String].self, forKey: .orderedAppIDs) ?? []
        homeAnchorID = try container.decodeIfPresent(String.self, forKey: .homeAnchorID)
        hiddenAppIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenAppIDs) ?? []
        extraSearchRoots = try container.decodeIfPresent([String].self, forKey: .extraSearchRoots) ?? []
    }

    /// Reconciles a freshly scanned, default-sorted list with a saved order.
    ///
    /// - Apps still present keep their saved position, which is how a manual
    ///   arrangement (or the first generated layout) stays put.
    /// - Apps that disappeared are dropped.
    /// - Newly discovered Apple apps join the end of the official block so they
    ///   cannot land behind third-party apps.
    /// - Every other new app is appended at the very end.
    static func reconcile(scanned: [LaunchpadAppItem], with layout: LaunchpadLayout) -> [LaunchpadAppItem] {
        guard !layout.orderedAppIDs.isEmpty else {
            return scanned
        }

        var scannedByID = Dictionary(scanned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var known: [LaunchpadAppItem] = []

        for id in layout.orderedAppIDs {
            guard let app = scannedByID.removeValue(forKey: id) else {
                continue
            }
            known.append(app)
        }

        let newcomers = scanned.filter { scannedByID[$0.id] != nil }

        guard !newcomers.isEmpty else {
            return known
        }
        guard !known.isEmpty else {
            return scanned
        }

        let newOfficialApps = newcomers.filter(\.isOfficialApp)
        let newOtherApps = newcomers.filter { !$0.isOfficialApp }

        guard let lastOfficialIndex = known.lastIndex(where: \.isOfficialApp) else {
            return newOfficialApps + known + newOtherApps
        }

        return Array(known[...lastOfficialIndex])
            + newOfficialApps
            + Array(known[(lastOfficialIndex + 1)...])
            + newOtherApps
    }
}

/// Reads and writes `layout.json` under Application Support.
struct LaunchpadLayoutStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    var location: URL {
        fileURL
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("Launchpad Lite", isDirectory: true)
            .appendingPathComponent("layout.json", isDirectory: false)
    }

    func load() -> LaunchpadLayout? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(LaunchpadLayout.self, from: data)
    }

    @discardableResult
    func save(_ layout: LaunchpadLayout) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(layout).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
