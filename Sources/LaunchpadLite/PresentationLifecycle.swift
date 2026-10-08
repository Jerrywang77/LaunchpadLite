struct PresentationLifecycle {
    private var generation = 0

    /// True from the moment a presentation starts until the panel is ordered out.
    private(set) var isPresented = false

    mutating func beginPresent() -> Int {
        generation += 1
        isPresented = true
        return generation
    }

    mutating func beginDismiss() -> Int {
        generation += 1
        return generation
    }

    func shouldFinishDismiss(token: Int) -> Bool {
        token == generation
    }

    /// Called once the panel has actually left the screen.
    mutating func didFinishDismiss() {
        isPresented = false
    }
}
