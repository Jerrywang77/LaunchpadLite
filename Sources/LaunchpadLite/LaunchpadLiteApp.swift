import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LaunchpadController?
    private var hasScheduledInitialPresentation = false
    private var launchedAtLogin = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        launchedAtLogin = isLaunchedAtLogin

        let controller = LaunchpadController()
        self.controller = controller
        controller.start()
        scheduleInitialPresentationIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleInitialPresentationIfNeeded()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        controller?.present()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private var isLaunchedAtLogin: Bool {
        NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: keyAELaunchedAsLogInItem)?
            .booleanValue ?? false
    }

    private func scheduleInitialPresentationIfNeeded() {
        guard !hasScheduledInitialPresentation else {
            return
        }
        guard !launchedAtLogin || CommandLine.arguments.contains("--show-on-launch") else {
            return
        }

        hasScheduledInitialPresentation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.present()
        }
    }
}
