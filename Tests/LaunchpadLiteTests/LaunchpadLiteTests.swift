import AppKit
import Combine
import XCTest
@testable import LaunchpadLite

final class LaunchpadLiteTests: XCTestCase {
    func testGridLayoutAdaptsToScreenSize() {
        let laptop = LaunchpadGridLayout.forScreen(size: CGSize(width: 1_440, height: 900))
        let display = LaunchpadGridLayout.forScreen(size: CGSize(width: 2_560, height: 1_440))

        XCTAssertEqual(laptop.columns, 8)
        XCTAssertEqual(laptop.rows, 4)
        XCTAssertEqual(display.columns, 8)
        XCTAssertEqual(display.rows, 6)
    }

    func testFilterMatchesAppNameOnly() {
        let apps = [
            makeApp(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            makeApp(name: "Notes", bundleIdentifier: "com.apple.Notes"),
            makeApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal")
        ]

        XCTAssertEqual(
            LaunchpadViewModel.filteredApps(from: apps, query: "saf").map(\.name),
            ["Safari"]
        )
        XCTAssertEqual(
            LaunchpadViewModel.filteredApps(from: apps, query: "notes").map(\.name),
            ["Notes"]
        )
        XCTAssertEqual(
            LaunchpadViewModel.filteredApps(from: apps, query: "term").map(\.name),
            ["Terminal"]
        )

        // 只搜应用名：bundle id 不参与（普通用户看不到它，之前会搜出一堆看不懂的结果）
        XCTAssertTrue(LaunchpadViewModel.filteredApps(from: apps, query: "com.apple.notes").isEmpty)
        XCTAssertTrue(LaunchpadViewModel.filteredApps(from: apps, query: "apple").isEmpty)
    }

    func testSearchShowsNameMatchesFirstAndIgnoresBundleIdentifierNoise() {
        let apps = [
            makeApp(name: "About This Mac", bundleIdentifier: "com.apple.AboutThisMacLauncher"),
            makeApp(name: "Time Machine", bundleIdentifier: "com.apple.backup.launcher"),
            makeApp(name: "Siri", bundleIdentifier: "com.apple.siri.launcher"),
            makeApp(name: "Downie 4", bundleIdentifier: "com.charliemonroe.Downie-4"),
            makeApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            makeApp(name: "Chess", bundleIdentifier: "com.apple.Chess"),
            makeApp(name: "PyCharm", bundleIdentifier: "com.jetbrains.pycharm")
        ]

        // 搜 "ch" 只应命中名字里真的有 ch 的应用（Time Machine 的 "Machine" 也算），
        // 并且前缀匹配排在包含匹配前面；About This Mac、Siri、Downie 4 这些名字里
        // 没有 ch、只靠 bundle id（Launcher / charliemonroe）命中的必须消失。
        XCTAssertEqual(
            LaunchpadViewModel.filteredApps(from: apps, query: "ch").map(\.name),
            ["Chess", "Google Chrome", "Time Machine", "PyCharm"]
        )

        // 搜完整名字同样能定位（Google Chrome 里的单词前缀匹配）。
        XCTAssertEqual(
            LaunchpadViewModel.filteredApps(from: apps, query: "chrome").map(\.name),
            ["Google Chrome"]
        )
    }

    @MainActor
    func testHorizontalSwipeChangesPage() {
        let apps = (0..<12).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        viewModel.handleHorizontalScroll(deltaX: -30, phase: .began)
        XCTAssertEqual(viewModel.page, 1)
        XCTAssertEqual(viewModel.pageDirection, 1)

        viewModel.resetHorizontalGesture()
        viewModel.handleHorizontalScroll(deltaX: 30, phase: .began)
        XCTAssertEqual(viewModel.page, 0)
        XCTAssertEqual(viewModel.pageDirection, -1)
    }

    @MainActor
    func testOneHorizontalGestureOnlyChangesOnePage() {
        let apps = (0..<20).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        viewModel.handleHorizontalScroll(deltaX: -30, phase: .began)
        viewModel.handleHorizontalScroll(deltaX: -30, phase: .changed)
        viewModel.handleHorizontalScroll(deltaX: -30, phase: .changed)
        viewModel.handleHorizontalScroll(deltaX: -30, phase: .ended)
        viewModel.handleHorizontalScroll(deltaX: -60, phase: [])

        XCTAssertEqual(viewModel.page, 1)

        viewModel.resetHorizontalGesture()
        viewModel.handleHorizontalScroll(deltaX: -30, phase: .began)
        XCTAssertEqual(viewModel.page, 2)
    }

    @MainActor
    func testSwipeAndScrollPathsCannotBothChangePage() {
        let apps = (0..<20).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        viewModel.handleHorizontalScroll(deltaX: -30, phase: .began)
        viewModel.handleTrackpadSwipe(deltaX: -80)

        XCTAssertEqual(viewModel.page, 1)

        viewModel.resetHorizontalGesture()
        viewModel.handleTrackpadSwipe(deltaX: -80)
        viewModel.handleHorizontalScroll(deltaX: -30, phase: .began)

        XCTAssertEqual(viewModel.page, 2)
    }

    @MainActor
    func testHoverSelectionDoesNotChangePage() {
        let apps = (0..<20).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)
        viewModel.page = 1
        viewModel.selectedIndex = 4

        viewModel.select(app: apps[8])

        XCTAssertEqual(viewModel.selectedIndex, 4)
        XCTAssertEqual(viewModel.page, 1)
    }

    func testStaleDismissCannotHideNewPresentation() {
        var lifecycle = PresentationLifecycle()
        let dismissToken = lifecycle.beginDismiss()
        _ = lifecycle.beginPresent()

        XCTAssertFalse(lifecycle.shouldFinishDismiss(token: dismissToken))

        let currentDismissToken = lifecycle.beginDismiss()
        XCTAssertTrue(lifecycle.shouldFinishDismiss(token: currentDismissToken))
    }

    func testRepresentingWhileOnScreenKeepsThePanelPresented() {
        var lifecycle = PresentationLifecycle()
        XCTAssertFalse(lifecycle.isPresented)

        _ = lifecycle.beginPresent()
        XCTAssertTrue(lifecycle.isPresented)

        // A second open request while the panel is still up must keep the
        // "already presented" state so the controller skips the fade-in.
        _ = lifecycle.beginPresent()
        XCTAssertTrue(lifecycle.isPresented)

        let dismissToken = lifecycle.beginDismiss()
        XCTAssertTrue(lifecycle.shouldFinishDismiss(token: dismissToken))
        lifecycle.didFinishDismiss()
        XCTAssertFalse(lifecycle.isPresented)

        // After a completed dismiss the next present fades in again.
        _ = lifecycle.beginPresent()
        XCTAssertTrue(lifecycle.isPresented)
    }

    func testStaleDismissDoesNotClearANewerPresentation() {
        var lifecycle = PresentationLifecycle()
        let staleDismissToken = lifecycle.beginDismiss()

        // Reopened during the fade-out.
        _ = lifecycle.beginPresent()

        XCTAssertFalse(lifecycle.shouldFinishDismiss(token: staleDismissToken))
        XCTAssertTrue(lifecycle.isPresented)
    }

    func testOfficialAppsComeFirstAndUserAppsUseInstallDate() {
        let laterInstall = makeApp(
            name: "Later",
            bundleIdentifier: "com.example.later",
            installDate: Date(timeIntervalSince1970: 200)
        )
        let earlierInstall = makeApp(
            name: "Earlier",
            bundleIdentifier: "com.example.earlier",
            installDate: Date(timeIntervalSince1970: 100)
        )
        let preview = makeApp(
            name: "Preview",
            bundleIdentifier: "com.apple.Preview",
            isOfficialApp: true,
            officialOrder: 16
        )
        let safari = makeApp(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            isOfficialApp: true,
            officialOrder: 0
        )

        let sorted = AppScanner.sortedApps([laterInstall, preview, earlierInstall, safari])

        XCTAssertEqual(
            sorted.map(\.name),
            ["Safari", "Preview", "Earlier", "Later"]
        )
    }

    func testLayoutKeepsSavedOrderAndAppendsNewApps() {
        let chrome = makeApp(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            installDate: Date(timeIntervalSince1970: 10)
        )
        let slack = makeApp(
            name: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            installDate: Date(timeIntervalSince1970: 20)
        )
        let saved = LaunchpadLayout(orderedAppIDs: [slack.id, chrome.id])

        let reconciled = LaunchpadLayout.reconcile(
            scanned: AppScanner.sortedApps([slack, chrome]),
            with: saved
        )
        XCTAssertEqual(reconciled.map(\.name), ["Slack", "Chrome"])

        let arrival = makeApp(
            name: "Arrival",
            bundleIdentifier: "com.example.arrival",
            installDate: Date(timeIntervalSince1970: 30)
        )
        let withNewcomer = LaunchpadLayout.reconcile(
            scanned: AppScanner.sortedApps([slack, chrome, arrival]),
            with: saved
        )
        XCTAssertEqual(withNewcomer.map(\.name), ["Slack", "Chrome", "Arrival"])
    }

    func testLayoutPlacesNewOfficialAppAtEndOfOfficialBlock() {
        let safari = makeApp(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            isOfficialApp: true,
            officialOrder: 0
        )
        let preview = makeApp(
            name: "Preview",
            bundleIdentifier: "com.apple.Preview",
            isOfficialApp: true,
            officialOrder: 15
        )
        let chrome = makeApp(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            installDate: Date(timeIntervalSince1970: 10)
        )
        // The saved order only knows Safari and Chrome; Preview is newly discovered.
        let saved = LaunchpadLayout(orderedAppIDs: [safari.id, chrome.id])

        let reconciled = LaunchpadLayout.reconcile(
            scanned: AppScanner.sortedApps([safari, preview, chrome]),
            with: saved
        )

        XCTAssertEqual(reconciled.map(\.name), ["Safari", "Preview", "Chrome"])
    }

    func testLayoutDropsAppsThatNoLongerExist() {
        let safari = makeApp(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            isOfficialApp: true,
            officialOrder: 0
        )
        let chrome = makeApp(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            installDate: Date(timeIntervalSince1970: 10)
        )
        let saved = LaunchpadLayout(orderedAppIDs: [chrome.id, safari.id, "com.example.uninstalled"])

        let reconciled = LaunchpadLayout.reconcile(
            scanned: AppScanner.sortedApps([safari, chrome]),
            with: saved
        )

        XCTAssertEqual(reconciled.map(\.name), ["Chrome", "Safari"])
    }

    func testLayoutStoreRoundTripAndReset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))
        XCTAssertNil(store.load())

        let layout = LaunchpadLayout(orderedAppIDs: ["com.apple.Safari", "com.google.Chrome"])
        XCTAssertTrue(store.save(layout))
        XCTAssertEqual(store.load(), layout)

        store.reset()
        XCTAssertNil(store.load())
    }

    func testSystemAppsAreSeparatedFromUserInstalls() {
        XCTAssertTrue(AppScanner.isSystemApp(at: URL(fileURLWithPath: "/System/Applications/Notes.app")))
        XCTAssertTrue(AppScanner.isSystemApp(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")))
        // Safari ships as a symlink into the cryptex and is resolved before scanning.
        XCTAssertTrue(AppScanner.isSystemApp(
            at: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app")
        ))

        XCTAssertFalse(AppScanner.isSystemApp(at: URL(fileURLWithPath: "/Applications/Keynote.app")))
        XCTAssertFalse(AppScanner.isSystemApp(at: URL(fileURLWithPath: "/Applications/Google Chrome.app")))
        XCTAssertFalse(AppScanner.isSystemApp(at: URL(fileURLWithPath: "/Users/someone/Applications/Tool.app")))
    }

    func testSystemCopyWinsWhenAnAppIsPresentTwice() {
        let installedCopy = URL(fileURLWithPath: "/Applications/Utilities/Feedback Assistant.app")
        let systemCopy = URL(
            fileURLWithPath: "/System/Library/CoreServices/Applications/Feedback Assistant.app"
        )

        XCTAssertEqual(
            AppScanner.preferringSystemCopies([installedCopy, systemCopy]),
            [systemCopy, installedCopy]
        )
    }

    func testAppleAppStoreInstallsStillCountAsOfficial() {
        // Pages, Numbers, Keynote and Xcode live in /Applications but are Apple's
        // own apps, so they stay in the official group without a marker.
        XCTAssertTrue(AppScanner.isOfficialApp(
            at: URL(fileURLWithPath: "/Applications/Pages.app"),
            bundleIdentifier: "com.apple.iWork.Pages"
        ))
        XCTAssertTrue(AppScanner.isOfficialApp(
            at: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleIdentifier: "com.apple.dt.Xcode"
        ))
        XCTAssertTrue(AppScanner.isOfficialApp(
            at: URL(fileURLWithPath: "/System/Applications/Mail.app"),
            bundleIdentifier: "com.apple.mail"
        ))

        XCTAssertFalse(AppScanner.isOfficialApp(
            at: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            bundleIdentifier: "com.google.Chrome"
        ))
        XCTAssertFalse(AppScanner.isOfficialApp(
            at: URL(fileURLWithPath: "/Applications/DingTalk.app"),
            bundleIdentifier: "5ZSL2CJU2T.com.dingtalk.mac"
        ))
    }

    @MainActor
    func testPinnedHomePageIsWhereTheOverlayOpens() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))

        let apps = (0..<40).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)
        viewModel.selectPage(3)

        XCTAssertFalse(viewModel.isCurrentPageHome)
        viewModel.toggleHomePage()
        XCTAssertTrue(viewModel.isCurrentPageHome)

        // Navigating away and reopening lands back on the pinned page.
        viewModel.selectPage(0)
        XCTAssertEqual(viewModel.page, 0)
        viewModel.goToHomePage()
        XCTAssertEqual(viewModel.page, 3)

        // A fresh view model reads the same pin back from disk.
        let reopened = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        reopened.layout = LaunchpadGridLayout(columns: 2, rows: 2)
        reopened.goToHomePage()
        XCTAssertEqual(reopened.page, 3)
        XCTAssertTrue(reopened.isCurrentPageHome)
    }

    @MainActor
    func testTogglingHomeOffFallsBackToFirstPage() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))

        let apps = (0..<40).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        viewModel.selectPage(2)
        viewModel.toggleHomePage()
        XCTAssertTrue(viewModel.isCurrentPageHome)

        viewModel.toggleHomePage()
        XCTAssertFalse(viewModel.isCurrentPageHome)

        viewModel.goToHomePage()
        XCTAssertEqual(viewModel.page, 0)
    }

    @MainActor
    func testTogglingHomePageNotifiesObserversImmediately() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))

        let apps = (0..<8).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        var notifications = 0
        let cancellable = viewModel.objectWillChange.sink { _ in notifications += 1 }
        defer { cancellable.cancel() }

        viewModel.toggleHomePage()

        // The header button reads `homeAnchorID`, so a silent write would leave
        // the UI showing the old state until something else refreshed the view.
        XCTAssertGreaterThan(notifications, 0)
        XCTAssertTrue(viewModel.isCurrentPageHome)
    }

    @MainActor
    func testHidingRemovesFromGridButKeepsItInEditMode() {
        let viewModel = makeViewModel(appCount: 8, pageSize: 4)
        let app = viewModel.apps[0]

        viewModel.setHidden(true, for: app)

        XCTAssertTrue(viewModel.isHidden(app))
        XCTAssertEqual(viewModel.hiddenAppCount, 1)
        XCTAssertFalse(viewModel.visibleApps.contains { $0.id == app.id })

        // Edit mode lists everything so a hidden app can be brought back.
        viewModel.setEditing(true)
        XCTAssertTrue(viewModel.visibleApps.contains { $0.id == app.id })

        viewModel.setHidden(false, for: app)
        XCTAssertFalse(viewModel.isHidden(app))
        XCTAssertEqual(viewModel.hiddenAppCount, 0)
    }

    @MainActor
    func testHidingAndRestoringRaisesTheConfirmationToken() {
        let viewModel = makeViewModel(appCount: 8, pageSize: 4)
        let app = viewModel.apps[0]
        let start = viewModel.hiddenChangeToken

        viewModel.setHidden(true, for: app)
        XCTAssertEqual(viewModel.hiddenChangeToken, start + 1)

        viewModel.setHidden(false, for: app)
        XCTAssertEqual(viewModel.hiddenChangeToken, start + 2)

        // A no-op toggle must not fire another confirmation.
        viewModel.setHidden(false, for: app)
        XCTAssertEqual(viewModel.hiddenChangeToken, start + 2)
    }

    @MainActor
    func testKeyboardNudgeReordersSelectedApp() {
        let viewModel = makeViewModel(appCount: 6, pageSize: 4)
        let idsBefore = viewModel.apps.map(\.id)
        let moved = viewModel.apps[2]
        viewModel.select(app: moved)

        viewModel.moveSelectedApp(by: -2)

        XCTAssertEqual(
            viewModel.apps.map(\.id),
            [idsBefore[2], idsBefore[0], idsBefore[1], idsBefore[3], idsBefore[4], idsBefore[5]]
        )
        XCTAssertEqual(viewModel.selectedApp?.id, moved.id)
    }

    func testPointerNearEdgesArmsThePageFlip() {
        // Middle of the page: stay put.
        XCTAssertNil(LaunchpadViewModel.pageFlipDirection(
            pointerX: 700, pageWidth: 1_440, pageIndex: 3, pageCount: 10
        ))
        // Outer strips page backwards / forwards.
        XCTAssertEqual(LaunchpadViewModel.pageFlipDirection(
            pointerX: 30, pageWidth: 1_440, pageIndex: 3, pageCount: 10
        ), -1)
        XCTAssertEqual(LaunchpadViewModel.pageFlipDirection(
            pointerX: 1_420, pageWidth: 1_440, pageIndex: 3, pageCount: 10
        ), 1)
        // Nothing to reach on the first and last pages.
        XCTAssertNil(LaunchpadViewModel.pageFlipDirection(
            pointerX: 30, pageWidth: 1_440, pageIndex: 0, pageCount: 10
        ))
        XCTAssertNil(LaunchpadViewModel.pageFlipDirection(
            pointerX: 1_420, pageWidth: 1_440, pageIndex: 9, pageCount: 10
        ))
    }

    func testGridMetricsResolveDropSlots() {
        let metrics = LaunchpadGridMetrics(columns: 4, pageWidth: 1_000)

        XCTAssertEqual(
            metrics.slotIndex(at: CGPoint(x: metrics.originX + 5, y: 20), itemCount: 16),
            0
        )
        XCTAssertEqual(
            metrics.slotIndex(
                at: CGPoint(x: metrics.originX + metrics.cellWidth * 2 + 5, y: 20),
                itemCount: 16
            ),
            2
        )
        XCTAssertEqual(
            metrics.slotIndex(
                at: CGPoint(x: metrics.originX + 5, y: metrics.cellHeight + 20),
                itemCount: 16
            ),
            4
        )
        // Past the end of a partly filled page clamps to "append last".
        XCTAssertEqual(
            metrics.slotIndex(at: CGPoint(x: 5_000, y: 5_000), itemCount: 6),
            6
        )
    }

    @MainActor
    func testDroppingAtIndexReordersApps() {
        let viewModel = makeViewModel(appCount: 6, pageSize: 4)
        let ids = viewModel.apps.map(\.id)

        viewModel.moveApp(id: ids[4], beforeIndex: 1)

        XCTAssertEqual(
            viewModel.apps.map(\.id),
            [ids[0], ids[4], ids[1], ids[2], ids[3], ids[5]]
        )
    }

    @MainActor
    func testDwellingOnAnEdgeTurnsThePage() async {
        let viewModel = makeViewModel(appCount: 40, pageSize: 4)
        viewModel.setEditing(true)
        viewModel.selectPage(2)

        viewModel.armPageFlip(1, delay: 0.05)
        XCTAssertEqual(viewModel.pendingPageFlip, 1)
        XCTAssertEqual(viewModel.page, 2)

        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(viewModel.page, 3)
        XCTAssertNil(viewModel.pendingPageFlip)
    }

    @MainActor
    func testLeavingTheEdgeCancelsThePendingFlip() async {
        let viewModel = makeViewModel(appCount: 40, pageSize: 4)
        viewModel.setEditing(true)
        viewModel.selectPage(2)

        viewModel.armPageFlip(1, delay: 0.05)
        viewModel.cancelPageFlip()

        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(viewModel.page, 2)
        XCTAssertNil(viewModel.pendingPageFlip)
    }

    @MainActor
    func testHidingHomeAnchorMovesItWithinTheSamePage() {
        let viewModel = makeViewModel(appCount: 8, pageSize: 4)
        viewModel.selectPage(1)
        viewModel.toggleHomePage()

        let anchor = viewModel.apps[4]
        XCTAssertTrue(viewModel.isCurrentPageHome)

        viewModel.setHidden(true, for: anchor)

        // The home page still resolves, now anchored by the next app on it.
        XCTAssertEqual(viewModel.homeAnchorID, viewModel.apps[5].id)
        XCTAssertTrue(viewModel.isCurrentPageHome)
    }

    @MainActor
    func testManualOrderIsPersisted() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))
        let apps = (0..<6).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: 2)

        // Drag the third app in front of the first one.
        viewModel.moveApp(id: apps[2].id, before: apps[0].id)

        XCTAssertEqual(
            viewModel.apps.map(\.id),
            [apps[2].id, apps[0].id, apps[1].id, apps[3].id, apps[4].id, apps[5].id]
        )
        XCTAssertEqual(store.load()?.orderedAppIDs, viewModel.apps.map(\.id))
    }

    func testLayoutFilesWithoutNewFieldsStillLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("layout.json")
        let legacy = #"{"orderedAppIDs":["com.apple.Safari"],"homeAnchorID":"com.apple.Safari"}"#
        try Data(legacy.utf8).write(to: fileURL)

        let layout = LaunchpadLayoutStore(fileURL: fileURL).load()

        XCTAssertEqual(layout?.orderedAppIDs, ["com.apple.Safari"])
        XCTAssertEqual(layout?.homeAnchorID, "com.apple.Safari")
        XCTAssertEqual(layout?.hiddenAppIDs, [])
        XCTAssertEqual(layout?.extraSearchRoots, [])
    }

    func testExtraSearchRootsAreScanned() {
        let extra = URL(fileURLWithPath: "/Volumes/Portable/Apps", isDirectory: true)
        let roots = AppScanner.searchRoots(additionalRoots: [extra])

        XCTAssertTrue(roots.contains { $0.path == extra.path })
        XCTAssertTrue(roots.contains { $0.path == "/Applications" })

        // Duplicates are ignored.
        XCTAssertEqual(AppScanner.searchRoots(additionalRoots: [extra, extra]).filter { $0.path == extra.path }.count, 1)
    }

    func testDirectoryWatcherReportsFolderChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fired = expectation(description: "watcher fired")
        let watcher = AppDirectoryWatcher(roots: [directory], debounceInterval: 0.1) {
            fired.fulfill()
        }
        defer { watcher.stop() }

        // Installing an app is just a new entry appearing in one of these folders.
        try "new app".write(
            to: directory.appendingPathComponent("NewApp.app"),
            atomically: true,
            encoding: .utf8
        )

        await fulfillment(of: [fired], timeout: 5)
    }

    func testLaunchThrottleIgnoresTheSecondClickOfADoubleClick() {
        var throttle = LaunchThrottle()

        XCTAssertTrue(throttle.shouldLaunch(at: 100.0))
        // 双击的第二下：应该被挡掉，否则一次双击会连开两个应用
        XCTAssertFalse(throttle.shouldLaunch(at: 100.2))
        XCTAssertFalse(throttle.shouldLaunch(at: 100.49))
        // 隔得够久，正常放行
        XCTAssertTrue(throttle.shouldLaunch(at: 100.5))
    }

    @MainActor
    private func makeViewModel(appCount: Int, pageSize: Int) -> LaunchpadViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = LaunchpadLayoutStore(fileURL: directory.appendingPathComponent("layout.json"))
        let apps = (0..<appCount).map {
            makeApp(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
        }
        let viewModel = LaunchpadViewModel(layoutStore: store, initialApps: apps)
        viewModel.layout = LaunchpadGridLayout(columns: 2, rows: pageSize / 2)
        return viewModel
    }

    private func makeApp(
        name: String,
        bundleIdentifier: String,
        isOfficialApp: Bool = false,
        installDate: Date = .distantPast,
        officialOrder: Int? = nil
    ) -> LaunchpadAppItem {
        LaunchpadAppItem(
            id: bundleIdentifier,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            name: name,
            bundleIdentifier: bundleIdentifier,
            icon: NSImage(size: NSSize(width: 128, height: 128)),
            isOfficialApp: isOfficialApp,
            installDate: installDate,
            officialOrder: officialOrder
        )
    }
}
