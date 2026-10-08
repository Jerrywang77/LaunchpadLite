import SwiftUI

struct PageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Group {
            if pageCount <= 10 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            Capsule()
                                .fill(index == currentPage ? LaunchpadTheme.accent : Color.black.opacity(0.18))
                                .frame(width: index == currentPage ? 18 : 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("第 \(index + 1) 页")
                    }
                }
            } else {
                Text("\(currentPage + 1) / \(pageCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
                    .monospacedDigit()
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.2), value: currentPage)
    }
}
