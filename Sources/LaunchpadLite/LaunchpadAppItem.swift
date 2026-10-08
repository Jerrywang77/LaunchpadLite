import AppKit

struct LaunchpadAppItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    /// Apple app by bundle identifier, including App Store installs like Pages.
    let isOfficialApp: Bool
    let installDate: Date
    let officialOrder: Int?

    static func == (lhs: LaunchpadAppItem, rhs: LaunchpadAppItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
