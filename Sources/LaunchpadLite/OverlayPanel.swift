import AppKit

final class OverlayPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var swipeHandler: ((CGFloat) -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func swipe(with event: NSEvent) {
        swipeHandler?(event.deltaX)
    }
}
