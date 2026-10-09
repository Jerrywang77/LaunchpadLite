import AppKit
import Combine
import SwiftUI

@MainActor
final class LaunchpadViewModel: ObservableObject {
    @Published private(set) var apps: [LaunchpadAppItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var skippedAppCount = 0

    @Published var query = "" {
        didSet {
            selectedIndex = 0
            page = 0
        }
    }

    @Published var selectedIndex = 0
    @Published var page = 0
    @Published var layout = LaunchpadGridLayout.fallback
    @Published private(set) var pageDirection = 1
    /// False while the overlay is hidden, so the animated backdrop can idle.
    @Published private(set) var isPanelVisible = false
    /// First app of the page pinned as home. Published so the header button
    /// reflects a tap immediately instead of waiting for an unrelated update.
    @Published private(set) var homeAnchorID: String?
    /// Apps the user removed from the grid.
    @Published private(set) var hiddenAppIDs: Set<String>
    /// Extra folders the scanner should include.
    @Published private(set) var extraSearchRoots: [URL]
    /// Edit mode keeps hidden apps on screen so they can be restored in place.
    @Published private(set) var isEditing = false
    /// Bumped whenever an app is hidden or restored, so the UI can confirm it.
    @Published private(set) var hiddenChangeToken = 0
    /// Direction a drag is about to page towards (-1 previous, +1 next).
    @Published private(set) var pendingPageFlip: Int?

    private let scanner: AppScanner
    private let layoutStore: LaunchpadLayoutStore
    private var storedLayout: LaunchpadLayout
    private var scanGeneration = 0
    private var horizontalScrollAccumulator: CGFloat = 0
    private var horizontalSwipeDidTrigger = false
    private var horizontalGestureResetWorkItem: DispatchWorkItem?
    private var pageFlipWorkItem: DispatchWorkItem?
    private var directoryWatcher: AppDirectoryWatcher?
    private var lastGesturePageChangeTime: TimeInterval = 0
    private let gestureDeduplicationInterval: TimeInterval = 0.08

    init(
        scanner: AppScanner = AppScanner(),
        layoutStore: LaunchpadLayoutStore = LaunchpadLayoutStore(),
        initialApps: [LaunchpadAppItem] = []
    ) {
        self.scanner = scanner
        self.layoutStore = layoutStore
        let storedLayout = layoutStore.load() ?? .empty
        self.storedLayout = storedLayout
        self.homeAnchorID = storedLayout.homeAnchorID
        self.hiddenAppIDs = storedLayout.hiddenAppIDs
        self.extraSearchRoots = storedLayout.extraSearchRoots.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        self.apps = initialApps
    }

    private var searchFilteredApps: [LaunchpadAppItem] {
        Self.filteredApps(from: apps, query: query)
    }

    /// What the grid renders. Hidden apps stay listed while editing so they can
    /// be brought back from the same screen.
    var visibleApps: [LaunchpadAppItem] {
        let items = searchFilteredApps
        guard !isEditing else {
            return items
        }
        return items.filter { !hiddenAppIDs.contains($0.id) }
    }

    var selectedApp: LaunchpadAppItem? {
        let items = visibleApps
        guard items.indices.contains(selectedIndex) else {
            return nil
        }
        return items[selectedIndex]
    }

    var pageCount: Int {
        let count = visibleApps.count
        guard count > 0 else {
            return 1
        }
        return Int(ceil(Double(count) / Double(layout.pageSize)))
    }

    var currentPageApps: [LaunchpadAppItem] {
        apps(on: page)
    }

    func apps(on pageIndex: Int) -> [LaunchpadAppItem] {
        pageApps(from: visibleApps, pageIndex: pageIndex)
    }

    private func pageApps(from items: [LaunchpadAppItem], pageIndex: Int) -> [LaunchpadAppItem] {
        let start = max(0, pageIndex) * layout.pageSize
        guard start < items.count else {
            return []
        }
        let end = min(start + layout.pageSize, items.count)
        return Array(items[start..<end])
    }

    /// Apps the grid actually shows, in saved order. Page numbers derived from
    /// this list match the pages the user sees outside edit mode.
    private var gridApps: [LaunchpadAppItem] {
        apps.filter { !hiddenAppIDs.contains($0.id) }
    }

    private var homePageIndex: Int? {
        guard let homeAnchorID,
              let index = gridApps.firstIndex(where: { $0.id == homeAnchorID })
        else {
            return nil
        }
        return index / layout.pageSize
    }

    /// True when the page on screen is the one the user pinned as home.
    var isCurrentPageHome: Bool {
        guard query.isEmpty, let homePageIndex else {
            return false
        }
        return homePageIndex == page
    }

    /// Pins the visible page as home, or unpins it when it is already pinned.
    func toggleHomePage() {
        guard query.isEmpty else {
            return
        }

        let grid = gridApps
        let pageStart = page * layout.pageSize
        guard grid.indices.contains(pageStart) else {
            return
        }

        let anchor = grid[pageStart].id
        homeAnchorID = homeAnchorID == anchor ? nil : anchor
        storedLayout.homeAnchorID = homeAnchorID
        layoutStore.save(storedLayout)
    }

    /// Jumps to the pinned page, or back to the first page when nothing is pinned.
    func goToHomePage() {
        if !query.isEmpty {
            query = ""
        }
        setPage(homePageIndex ?? 0, animated: false)
    }

    // MARK: - Edit mode

    func setEditing(_ editing: Bool) {
        guard isEditing != editing else {
            return
        }
        isEditing = editing
        cancelPageFlip()
        clampSelection()
    }

    func toggleEditing() {
        setEditing(!isEditing)
    }

    func isHidden(_ app: LaunchpadAppItem) -> Bool {
        hiddenAppIDs.contains(app.id)
    }

    var hiddenAppCount: Int {
        hiddenAppIDs.count
    }

    /// Removing an app only takes it off the grid; the bundle is untouched.
    func setHidden(_ hidden: Bool, for app: LaunchpadAppItem) {
        guard hidden != isHidden(app) else {
            return
        }

        if hidden {
            hiddenAppIDs.insert(app.id)
            if homeAnchorID == app.id {
                homeAnchorID = replacementHomeAnchor(hiding: app)
                storedLayout.homeAnchorID = homeAnchorID
            }
        } else {
            hiddenAppIDs.remove(app.id)
        }

        storedLayout.hiddenAppIDs = hiddenAppIDs
        layoutStore.save(storedLayout)
        hiddenChangeToken += 1
        clampSelection()
    }

    func restoreAllHiddenApps() {
        guard !hiddenAppIDs.isEmpty else {
            return
        }
        hiddenAppIDs.removeAll()
        storedLayout.hiddenAppIDs = []
        layoutStore.save(storedLayout)
        hiddenChangeToken += 1
    }

    /// Keeps the home page pointing at the same page by handing the anchor to
    /// whichever app slides into its slot on the grid.
    private func replacementHomeAnchor(hiding app: LaunchpadAppItem) -> String? {
        let gridIndex = apps
            .prefix { $0.id != app.id }
            .filter { !hiddenAppIDs.contains($0.id) }
            .count

        let grid = gridApps
        guard grid.indices.contains(gridIndex) else {
            return nil
        }
        return grid[gridIndex].id
    }

    // MARK: - Manual ordering

    /// Moves an app so it sits directly before `targetID` in the saved order.
    func moveApp(id: String, before targetID: String) {
        guard id != targetID,
              let from = apps.firstIndex(where: { $0.id == id }),
              let to = apps.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        var reordered = apps
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: from < to ? to - 1 : to)
        reorder(to: reordered)
    }

    /// Nudges the selected app `offset` slots earlier (negative) or later.
    func moveSelectedApp(by offset: Int) {
        guard offset != 0,
              let id = selectedApp?.id,
              let index = apps.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let target = min(max(0, index + offset), apps.count - 1)
        guard target != index else {
            return
        }

        var reordered = apps
        let moved = reordered.remove(at: index)
        reordered.insert(moved, at: target)
        reorder(to: reordered)
    }

    /// Moves an app so it lands before whatever currently sits at `targetIndex`.
    func moveApp(id: String, beforeIndex targetIndex: Int) {
        guard let from = apps.firstIndex(where: { $0.id == id }) else {
            return
        }

        var reordered = apps
        let moved = reordered.remove(at: from)
        let insertion = min(max(0, from < targetIndex ? targetIndex - 1 : targetIndex), reordered.count)
        reordered.insert(moved, at: insertion)
        reorder(to: reordered)
    }

    private func reorder(to reordered: [LaunchpadAppItem]) {
        cancelPageFlip()
        let selectedID = selectedApp?.id
        apps = reordered
        persistLayout(for: reordered)

        // Keep the moved app selected so repeated nudges keep moving it.
        if let selectedID,
           let newIndex = visibleApps.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = newIndex
        }
    }

    // MARK: - Cross-page dragging

    /// Which way a drag at `pointerX` should page towards, or nil to stay put.
    /// Only the outer strips of a page arm a flip, and only when there is
    /// another page to reach.
    nonisolated static func pageFlipDirection(
        pointerX: CGFloat,
        pageWidth: CGFloat,
        pageIndex: Int,
        pageCount: Int,
        edgeWidth: CGFloat = 90
    ) -> Int? {
        guard pageWidth > edgeWidth * 2 else {
            return nil
        }
        if pointerX <= edgeWidth, pageIndex > 0 {
            return -1
        }
        if pointerX >= pageWidth - edgeWidth, pageIndex < pageCount - 1 {
            return 1
        }
        return nil
    }

    /// Starts the dwell timer for an edge hover. `nil` cancels a pending flip.
    func armPageFlip(_ direction: Int?, delay: TimeInterval = 0.55) {
        guard let direction else {
            cancelPageFlip()
            return
        }
        guard pendingPageFlip != direction else {
            return
        }

        pageFlipWorkItem?.cancel()
        pendingPageFlip = direction

        let workItem = DispatchWorkItem { [weak self] in
            self?.performPageFlip(direction)
        }
        pageFlipWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPageFlip() {
        pageFlipWorkItem?.cancel()
        pageFlipWorkItem = nil
        pendingPageFlip = nil
    }

    private func performPageFlip(_ direction: Int) {
        pageFlipWorkItem = nil
        pendingPageFlip = nil
        changePage(by: direction)
    }

    // MARK: - Extra scan locations

    func addSearchRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !extraSearchRoots.contains(where: { $0.path == standardized.path }) else {
            return
        }

        extraSearchRoots.append(standardized)
        storedLayout.extraSearchRoots = extraSearchRoots.map(\.path)
        layoutStore.save(storedLayout)
        startMonitoringAppDirectories()
        lastScanDate = nil
        reload(force: true)
    }

    func updateLayout(for screenSize: CGSize) {
        layout = LaunchpadGridLayout.forScreen(size: screenSize)
        page = min(page, max(0, pageCount - 1))
        clampSelection()
    }

    func reload(force: Bool = false) {
        if isLoading {
            return
        }
        if !force, lastScanDate != nil {
            return
        }

        scanGeneration += 1
        let generation = scanGeneration
        let scanner = scanner
        let extraRoots = extraSearchRoots

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self, scanner] in
            let result = scanner.scan(additionalRoots: extraRoots)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == generation else {
                    return
                }

                let previousSelectionID = self.selectedApp?.id

                let orderedApps = LaunchpadLayout.reconcile(scanned: result.apps, with: self.storedLayout)
                self.apps = orderedApps
                self.persistLayout(for: orderedApps)
                self.skippedAppCount = result.skipped
                self.lastScanDate = Date()
                self.isLoading = false

                // A background rescan (new app installed while the panel is up)
                // must not yank the user back to the first page.
                self.clampSelection()
                if let previousSelectionID,
                   let index = self.visibleApps.firstIndex(where: { $0.id == previousSelectionID }) {
                    self.selectedIndex = index
                    self.page = min(index / self.layout.pageSize, max(0, self.pageCount - 1))
                }
            }
        }
    }

    /// Rescans whenever the app folders change, so installing or removing an app
    /// shows up without restarting this app.
    func startMonitoringAppDirectories() {
        directoryWatcher?.stop()
        directoryWatcher = AppDirectoryWatcher(roots: monitoredRoots()) { [weak self] in
            self?.reload(force: true)
        }
    }

    /// Safety net for changes the folder watcher cannot see (apps installed into
    /// a nested folder, network volumes, and the like): refresh on open if the
    /// last scan is getting old.
    func refreshIfStale(maxAge: TimeInterval = 120) {
        guard let lastScanDate else {
            reload()
            return
        }
        guard Date().timeIntervalSince(lastScanDate) > maxAge else {
            return
        }
        reload(force: true)
    }

    private func monitoredRoots() -> [URL] {
        AppScanner.searchRoots(additionalRoots: extraSearchRoots)
    }

    /// Drops the saved order so the next scan regenerates the default layout.
    func resetLayout() {
        layoutStore.reset()
        storedLayout = .empty
        homeAnchorID = nil
        hiddenAppIDs = []
        isEditing = false
        lastScanDate = nil
        reload(force: true)
    }

    func setPanelVisible(_ isVisible: Bool) {
        guard isPanelVisible != isVisible else {
            return
        }
        isPanelVisible = isVisible
    }

    private func persistLayout(for apps: [LaunchpadAppItem]) {
        let layout = LaunchpadLayout(
            orderedAppIDs: apps.map(\.id),
            homeAnchorID: homeAnchorID,
            hiddenAppIDs: hiddenAppIDs,
            extraSearchRoots: extraSearchRoots.map(\.path)
        )
        guard layout != storedLayout else {
            return
        }
        storedLayout = layout
        layoutStore.save(layout)
    }

    func select(app: LaunchpadAppItem) {
        guard let index = visibleApps.firstIndex(where: { $0.id == app.id }) else {
            return
        }
        guard index / layout.pageSize == page else {
            return
        }
        selectedIndex = index
    }

    func selectPage(_ newPage: Int) {
        setPage(newPage, animated: true)
    }

    private func setPage(_ newPage: Int, animated: Bool) {
        let clampedPage = min(max(0, newPage), max(0, pageCount - 1))
        pageDirection = clampedPage >= page ? 1 : -1

        let update = {
            self.page = clampedPage
            self.selectedIndex = min(clampedPage * self.layout.pageSize, max(0, self.visibleApps.count - 1))
        }

        if animated && !reduceMotion {
            withAnimation(LaunchpadTheme.pageAnimation, update)
        } else {
            update()
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func changePage(by delta: Int) {
        guard delta != 0 else {
            return
        }
        selectPage(page + delta)
    }

    func handleHorizontalScroll(
        deltaX: CGFloat,
        phase: NSEvent.Phase
    ) {
        if phase.contains(.began) {
            resetHorizontalGesture(keepDeduplication: true)
        }

        if !horizontalSwipeDidTrigger {
            horizontalScrollAccumulator += deltaX

            let threshold: CGFloat = 10
            if horizontalScrollAccumulator <= -threshold {
                if claimGesturePageChange() {
                    changePage(by: 1)
                }
                horizontalScrollAccumulator = 0
                horizontalSwipeDidTrigger = true
            } else if horizontalScrollAccumulator >= threshold {
                if claimGesturePageChange() {
                    changePage(by: -1)
                }
                horizontalScrollAccumulator = 0
                horizontalSwipeDidTrigger = true
            }
        }

        scheduleHorizontalGestureReset()
    }

    func handleTrackpadSwipe(deltaX: CGFloat) {
        guard !horizontalSwipeDidTrigger else {
            scheduleHorizontalGestureReset()
            return
        }
        guard claimGesturePageChange() else {
            return
        }

        if deltaX < 0 {
            changePage(by: 1)
        } else if deltaX > 0 {
            changePage(by: -1)
        }

        horizontalSwipeDidTrigger = true
        scheduleHorizontalGestureReset()
    }

    func moveSelection(deltaX: Int, deltaY: Int) {
        let items = visibleApps
        guard !items.isEmpty else {
            selectedIndex = 0
            page = 0
            return
        }

        let columns = max(1, layout.columns)
        let pageSize = layout.pageSize
        let currentColumn = selectedIndex % columns
        let currentPage = min(page, max(0, pageCount - 1))
        var target = selectedIndex

        if deltaX > 0 {
            if currentColumn == columns - 1 || target + 1 >= min((currentPage + 1) * pageSize, items.count) {
                if currentPage < pageCount - 1 {
                    page = currentPage + 1
                    target = page * pageSize
                }
            } else {
                target += 1
            }
        } else if deltaX < 0 {
            if currentColumn == 0 {
                if currentPage > 0 {
                    page = currentPage - 1
                    target = min((page + 1) * pageSize - 1, items.count - 1)
                }
            } else {
                target -= 1
            }
        }

        if deltaY != 0 {
            let candidate = target + (deltaY * columns)
            if items.indices.contains(candidate) {
                target = candidate
            }
        }

        selectedIndex = min(max(0, target), items.count - 1)
        let resolvedPage = min(max(0, selectedIndex / pageSize), max(0, pageCount - 1))
        if resolvedPage != page {
            pageDirection = resolvedPage > page ? 1 : -1
            if reduceMotion {
                page = resolvedPage
            } else {
                withAnimation(LaunchpadTheme.pageAnimation) {
                    page = resolvedPage
                }
            }
        }
    }

    func handleKey(
        _ event: NSEvent,
        onLaunch: (LaunchpadAppItem) -> Void,
        onDismiss: () -> Void
    ) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
            reload(force: true)
            return true
        }

        if isEditing, flags.contains(.option) {
            switch event.keyCode {
            case 123:
                moveSelectedApp(by: -1)
                return true
            case 124:
                moveSelectedApp(by: 1)
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 53:
            if isEditing {
                setEditing(false)
            } else {
                onDismiss()
            }
            return true
        case 36, 76:
            guard !isEditing else {
                return true
            }
            if let selectedApp {
                onLaunch(selectedApp)
            }
            return true
        case 123:
            moveSelection(deltaX: -1, deltaY: 0)
            return true
        case 124:
            moveSelection(deltaX: 1, deltaY: 0)
            return true
        case 125:
            moveSelection(deltaX: 0, deltaY: 1)
            return true
        case 126:
            moveSelection(deltaX: 0, deltaY: -1)
            return true
        case 51:
            if !query.isEmpty {
                query.removeLast()
            }
            return true
        default:
            break
        }

        guard !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let characters = event.characters,
              !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return false
        }

        query.append(characters)
        return true
    }

    nonisolated static func filteredApps(from apps: [LaunchpadAppItem], query: String) -> [LaunchpadAppItem] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.localizedLowercase }

        guard !terms.isEmpty else {
            return apps
        }

        return apps.enumerated()
            .compactMap { index, app -> (app: LaunchpadAppItem, score: Int, index: Int)? in
                guard let score = matchScore(for: app, terms: terms) else {
                    return nil
                }
                return (app, score, index)
            }
            // 分越低越相关；同分时保持原来的布局顺序
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
            }
            .map(\.app)
    }

    /// 分数越小越靠前，`nil` 表示没有命中全部关键词。
    nonisolated static func matchScore(for app: LaunchpadAppItem, terms: [String]) -> Int? {
        var total = 0

        for term in terms {
            guard let score = termScore(term, in: app) else {
                return nil
            }
            total += score
        }

        return total
    }

    private nonisolated static func termScore(_ term: String, in app: LaunchpadAppItem) -> Int? {
        let name = app.name.localizedLowercase

        if name == term { return 0 }
        if name.hasPrefix(term) { return 1 }
        if name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .contains(where: { $0.hasPrefix(term) }) {
            return 2
        }
        if name.contains(term) { return 3 }

        // 只按应用名匹配：bundle id 对普通用户是隐形的（文档里也叫「搜索应用」），
        // 之前匹配它会让 "ch" 命中 com.apple.*.launcher 这类用户看不出原因的包。
        return nil
    }

    private func clampSelection() {
        let count = visibleApps.count
        guard count > 0 else {
            selectedIndex = 0
            page = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), count - 1)
        page = min(max(0, page), max(0, pageCount - 1))
    }

    func resetHorizontalGesture(keepDeduplication: Bool = false) {
        horizontalGestureResetWorkItem?.cancel()
        horizontalGestureResetWorkItem = nil
        horizontalScrollAccumulator = 0
        horizontalSwipeDidTrigger = false
        if !keepDeduplication {
            lastGesturePageChangeTime = 0
        }
    }

    private func scheduleHorizontalGestureReset() {
        horizontalGestureResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetHorizontalGesture()
        }
        horizontalGestureResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func claimGesturePageChange() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastGesturePageChangeTime >= gestureDeduplicationInterval else {
            return false
        }
        lastGesturePageChangeTime = now
        return true
    }
}
