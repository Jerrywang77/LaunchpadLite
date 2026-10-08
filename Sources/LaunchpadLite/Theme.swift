import SwiftUI

enum LaunchpadTheme {
    static let accent = Color(red: 0.09, green: 0.56, blue: 1.00)
    static let tileCornerRadius: CGFloat = 18
    static let searchCornerRadius: CGFloat = 14
    static let tileWidth: CGFloat = 116
    static let tileHeight: CGFloat = 124
    static let tileVerticalPadding: CGFloat = 8
    static let tileSpacing: CGFloat = 20
    static let gridSpacing: CGFloat = 24
    static let gridHorizontalPadding: CGFloat = 32
    static let pageAnimationDuration: Double = 0.40
    static var pageAnimation: Animation {
        .easeInOut(duration: pageAnimationDuration)
    }
}
