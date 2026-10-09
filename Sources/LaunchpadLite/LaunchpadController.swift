import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class LaunchpadController: NSObject, NSMenuDelegate {
    private let viewModel: LaunchpadViewModel
    private let hotKeyManager = GlobalHotKeyManager()

    private var panel: OverlayPanel?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var editModeItem: NSMenuItem?
    private var restoreHiddenItem: NSMenuItem?
    private var scrollMonitor: Any?
    private var presentationLifecycle = PresentationLifecycle()

    init(viewModel: LaunchpadViewModel? = nil) {
        self.viewModel = viewModel ?? LaunchpadViewModel()
        super.init()
    }

    func start() {
        configureStatusItem()
        installScrollMonitor()
        hotKeyManager.onHotKey = { [weak self] in
            self?.toggle()
        }
        viewModel.reload()
        viewModel.startMonitoringAppDirectories()
    }

    deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        // A second open request (Dock click, reopen event, hotkey race) while the
        // overlay is already up must not replay the fade-in: resetting alpha to 0
        // first blanks the whole panel for a frame, and if that fade is
        // interrupted the panel stays transparent and looks like it never opened.
        let reusePresentedPanel = presentationLifecycle.isPresented && panel?.isVisible == true
        _ = presentationLifecycle.beginPresent()

        guard let screen = screenUnderPointer() ?? NSScreen.main else {
            return
        }

        viewModel.updateLayout(for: screen.frame.size)
        viewModel.refreshIfStale()

        if reusePresentedPanel, let panel {
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            viewModel.setPanelVisible(true)
            return
        }

        viewModel.goToHomePage()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen.frame, display: true)
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        panel.swipeHandler = { [weak self] deltaX in
            self?.viewModel.handleTrackpadSwipe(deltaX: deltaX)
        }
        viewModel.resetHorizontalGesture()
        viewModel.setPanelVisible(true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard let panel else {
            return
        }

        let dismissToken = presentationLifecycle.beginDismiss()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.presentationLifecycle.shouldFinishDismiss(token: dismissToken) == true else {
                    return
                }
                panel.orderOut(nil)
                NSApp.deactivate()
                self?.viewModel.setPanelVisible(false)
                self?.presentationLifecycle.didFinishDismiss()
            }
        }
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(
            rootView: LaunchpadView(
                viewModel: viewModel,
                onLaunch: { [weak self] app in
                    self?.launch(app)
                },
                onClose: { [weak self] in
                    self?.dismiss()
                },
                onReveal: { app in
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
            )
        )

        return panel
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        viewModel.handleKey(
            event,
            onLaunch: { [weak self] app in
                self?.launch(app)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self, self.panel?.isVisible == true else {
                return event
            }

            if event.type == .swipe {
                self.viewModel.handleTrackpadSwipe(deltaX: event.deltaX)
                return nil
            }

            let horizontal = event.scrollingDeltaX

            guard abs(horizontal) > 0.01 else {
                return nil
            }

            self.viewModel.handleHorizontalScroll(
                deltaX: horizontal,
                phase: event.phase
            )
            return nil
        }
    }

    private func launch(_ app: LaunchpadAppItem) {
        dismiss()
        NSWorkspace.shared.open(app.url)
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(pointer, screen.frame, false)
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3",
            accessibilityDescription: "Launchpad Lite"
        )
        statusItem.button?.toolTip = "Launchpad Lite"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(
            makeMenuItem(
                title: "打开 Launchpad Lite",
                action: #selector(showFromMenu),
                keyEquivalent: ""
            )
        )

        let editModeItem = makeMenuItem(
            title: "编辑图标",
            action: #selector(toggleEditModeFromMenu),
            keyEquivalent: "e"
        )
        self.editModeItem = editModeItem
        menu.addItem(editModeItem)

        let restoreHiddenItem = makeMenuItem(
            title: "恢复全部隐藏应用",
            action: #selector(restoreHiddenAppsFromMenu),
            keyEquivalent: ""
        )
        self.restoreHiddenItem = restoreHiddenItem
        menu.addItem(restoreHiddenItem)

        menu.addItem(
            makeMenuItem(
                title: "添加应用目录…",
                action: #selector(addSearchRootFromMenu),
                keyEquivalent: ""
            )
        )

        menu.addItem(.separator())

        let shortcutItem = NSMenuItem(
            title: "快捷键：\(hotKeyManager.shortcutDescription)",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(
            makeMenuItem(
                title: "重新扫描应用",
                action: #selector(rescanFromMenu),
                keyEquivalent: "r"
            )
        )

        menu.addItem(
            makeMenuItem(
                title: "重置布局",
                action: #selector(resetLayoutFromMenu),
                keyEquivalent: ""
            )
        )

        let launchAtLoginItem = makeMenuItem(
            title: "登录时启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.state = launchAtLoginIsEnabled ? .on : .off
        self.launchAtLoginItem = launchAtLoginItem
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        menu.addItem(
            makeMenuItem(
                title: "退出",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private var launchAtLoginIsEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func showFromMenu() {
        present()
    }

    @objc private func rescanFromMenu() {
        viewModel.reload(force: true)
    }

    @objc private func resetLayoutFromMenu() {
        viewModel.resetLayout()
    }

    @objc private func toggleEditModeFromMenu() {
        viewModel.toggleEditing()
        if panel?.isVisible != true {
            present()
        }
    }

    @objc private func restoreHiddenAppsFromMenu() {
        viewModel.restoreAllHiddenApps()
    }

    @objc private func addSearchRootFromMenu() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "添加"
        openPanel.message = "选择一个包含 App 的文件夹"
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        // The overlay sits at screen-saver level, so get it out of the way first.
        let wasVisible = panel?.isVisible == true
        if wasVisible {
            dismiss()
        }

        if openPanel.runModal() == .OK, let url = openPanel.url {
            viewModel.addSearchRoot(url)
        }

        if wasVisible {
            present()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        editModeItem?.title = viewModel.isEditing ? "完成编辑" : "编辑图标"
        editModeItem?.state = viewModel.isEditing ? .on : .off

        let hiddenCount = viewModel.hiddenAppCount
        restoreHiddenItem?.title = hiddenCount > 0
            ? "恢复全部隐藏应用（\(hiddenCount)）"
            : "恢复全部隐藏应用"
        restoreHiddenItem?.isEnabled = hiddenCount > 0
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginIsEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLoginItem?.state = launchAtLoginIsEnabled ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
