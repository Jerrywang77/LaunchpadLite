import CoreGraphics

/// Geometry of one page of icons.
///
/// Drag hit-testing and the drop indicator both derive their positions from
/// this, so the two can never disagree about where a tile sits.
struct LaunchpadGridMetrics: Equatable {
    let columns: Int
    let pageWidth: CGFloat

    var cellWidth: CGFloat {
        LaunchpadTheme.tileWidth + LaunchpadTheme.tileSpacing
    }

    var cellHeight: CGFloat {
        LaunchpadTheme.tileHeight
            + LaunchpadTheme.tileVerticalPadding * 2
            + LaunchpadTheme.gridSpacing
    }

    private var contentWidth: CGFloat {
        let columns = max(1, self.columns)
        return CGFloat(columns) * LaunchpadTheme.tileWidth
            + CGFloat(columns - 1) * LaunchpadTheme.tileSpacing
    }

    private var gridWidth: CGFloat {
        max(1, pageWidth - LaunchpadTheme.gridHorizontalPadding * 2)
    }

    /// Left edge of the first column, after the grid is centred in the page.
    var originX: CGFloat {
        LaunchpadTheme.gridHorizontalPadding + max(0, (gridWidth - contentWidth) / 2)
    }

    /// Slot within the page that a drop at `point` should insert before.
    func slotIndex(at point: CGPoint, itemCount: Int) -> Int {
        guard columns > 0 else {
            return 0
        }

        let column = Int(floor((point.x - originX) / cellWidth))
        let row = Int(floor(max(0, point.y) / cellHeight))
        let clampedColumn = min(max(0, column), columns - 1)
        return min(max(0, row) * columns + clampedColumn, max(0, itemCount))
    }

    /// Origin of the insertion marker for `localIndex`, in page coordinates.
    func slotOrigin(localIndex: Int) -> CGPoint {
        let columns = max(1, self.columns)
        let row = localIndex / columns
        let column = localIndex % columns
        return CGPoint(
            x: originX + CGFloat(column) * cellWidth - LaunchpadTheme.tileSpacing / 2,
            y: CGFloat(row) * cellHeight + LaunchpadTheme.tileVerticalPadding
        )
    }
}
