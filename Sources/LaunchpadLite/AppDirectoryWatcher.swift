import Darwin
import Foundation

/// Watches the folders the scanner reads and reports when their contents change.
///
/// Without this the app list is only built at launch, so a freshly installed
/// app would not show up until the user picked “重新扫描应用”.
final class AppDirectoryWatcher {
    private let queue = DispatchQueue(label: "io.github.jerrywang77.LaunchpadLite.directory-watcher")
    private let debounceInterval: TimeInterval
    private let onChange: () -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?

    init(roots: [URL], debounceInterval: TimeInterval = 1.0, onChange: @escaping () -> Void) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        start(roots: roots)
    }

    deinit {
        stop()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func start(roots: [URL]) {
        let fileManager = FileManager.default

        for root in roots where fileManager.fileExists(atPath: root.path) {
            let descriptor = open(root.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleNotification()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources.append(source)
        }
    }

    /// Installs usually touch the folder several times; wait for things to settle.
    private func scheduleNotification() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                self.onChange()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
