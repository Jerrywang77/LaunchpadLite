import CoreGraphics

struct LaunchpadGridLayout: Equatable {
    let columns: Int
    let rows: Int

    var pageSize: Int {
        max(1, columns * rows)
    }

    static let fallback = LaunchpadGridLayout(columns: 7, rows: 5)

    static func forScreen(size: CGSize) -> LaunchpadGridLayout {
        let horizontalPadding: CGFloat = 160
        let verticalPadding: CGFloat = 250
        let columnStride = LaunchpadTheme.tileWidth + LaunchpadTheme.tileSpacing
        let rowStride = LaunchpadTheme.tileHeight + LaunchpadTheme.gridSpacing

        let usableWidth = max(720, size.width - horizontalPadding)
        let usableHeight = max(360, size.height - verticalPadding)

        // Keep the familiar 8 columns on a built-in laptop display. Only a
        // genuinely wider external display gets extra columns.
        let columnLimit = size.width > 1_700 ? 14 : 8
        let columns = min(columnLimit, max(4, Int(usableWidth / columnStride)))
        let rows = min(8, max(2, Int(usableHeight / rowStride)))

        return LaunchpadGridLayout(columns: columns, rows: rows)
    }
}
