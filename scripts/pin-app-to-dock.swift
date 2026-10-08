import Foundation

let bundleIdentifier = "io.github.jerrywang77.LaunchpadLite"
let appURL = URL(fileURLWithPath: "/Applications/Launchpad Lite.app")
let defaults = UserDefaults(suiteName: "com.apple.dock")!

func containsLaunchpad(_ value: Any) -> Bool {
    guard
        let tile = value as? [String: Any],
        let tileData = tile["tile-data"] as? [String: Any]
    else {
        return false
    }

    return tileData["bundle-identifier"] as? String == bundleIdentifier
        || (tileData["file-label"] as? String) == "Launchpad Lite"
        || (tileData["file-label"] as? String) == "LaunchpadLite"
}

let bookmark = try appURL.bookmarkData(
    options: .suitableForBookmarkFile,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)

let tile: [String: Any] = [
    "tile-data": [
        "bundle-identifier": bundleIdentifier,
        "dock-extra": false,
        "file-data": [
            "_CFURLString": appURL.absoluteString,
            "_CFURLStringType": 15
        ],
        "file-label": "Launchpad Lite",
        "file-type": 41,
        "is-beta": false,
        "book": bookmark
    ],
    "tile-type": "file-tile"
]

for key in ["persistent-apps", "recent-apps"] {
    var items = defaults.array(forKey: key) ?? []
    items.removeAll(where: containsLaunchpad)

    if key == "persistent-apps" {
        let insertionIndex = min(2, items.count)
        items.insert(tile, at: insertionIndex)
    }

    defaults.set(items, forKey: key)
}

defaults.synchronize()
