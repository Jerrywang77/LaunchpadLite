import Foundation

/// 双击会触发两次点击事件，这里把紧随其后的重复启动挡掉，
/// 避免一次双击连开两个应用。
struct LaunchThrottle {
    private let interval: TimeInterval
    private var lastLaunch: TimeInterval?

    init(interval: TimeInterval = 0.5) {
        self.interval = interval
    }

    mutating func shouldLaunch(at uptime: TimeInterval) -> Bool {
        if let lastLaunch, uptime - lastLaunch < interval {
            return false
        }
        lastLaunch = uptime
        return true
    }
}
