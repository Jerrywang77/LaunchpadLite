import Foundation

enum LaunchpadSystemOrder {
    // Mirrors the traditional macOS Launchpad first-page ordering closely enough
    // to keep Apple apps stable and familiar while still allowing new macOS apps.
    private static let orderedIdentifiers: [String] = [
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.AddressBook",
        "com.apple.iCal",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.Maps",
        "com.apple.Photos",
        "com.apple.MobileSMS",
        "com.apple.FaceTime",
        "com.apple.Music",
        "com.apple.TV",
        "com.apple.podcasts",
        "com.apple.AppStore",
        "com.apple.systempreferences",
        "com.apple.Preview",
        "com.apple.QuickTimePlayerX",
        "com.apple.TextEdit",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote",
        "com.apple.iMovieApp",
        "com.apple.garageband10",
        "com.apple.Finder"
    ]

    static func priority(for bundleIdentifier: String?) -> Int? {
        guard let bundleIdentifier else {
            return nil
        }
        return orderedIdentifiers.firstIndex(of: bundleIdentifier)
    }
}
