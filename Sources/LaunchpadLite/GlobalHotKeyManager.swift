import Carbon
import Foundation

final class GlobalHotKeyManager {
    var onHotKey: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var registeredShortcuts: [String] = []

    private static let signature: OSType = 0x4C505053 // LPPS

    init() {
        installEventHandler()

        register(id: 1, keyCode: UInt32(kVK_F4), modifiers: 0, label: "F4")
        register(
            id: 2,
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            label: "Option + 空格"
        )
    }

    deinit {
        hotKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    var shortcutDescription: String {
        registeredShortcuts.isEmpty ? "未注册" : registeredShortcuts.joined(separator: " / ")
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            let manager = Unmanaged<GlobalHotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                manager.onHotKey?()
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, label: String) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
            registeredShortcuts.append(label)
        } else {
            NSLog("LaunchpadLite: unable to register \(label), status \(status)")
        }
    }
}
