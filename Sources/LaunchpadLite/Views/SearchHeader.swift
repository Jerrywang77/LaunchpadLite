import SwiftUI

struct SearchHeader: View {
    let query: String
    let appCount: Int
    /// 面板隐藏时暂停光标闪烁，避免后台空转。
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blinkInterval: Double = 0.55

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 1) {
                Text(query.isEmpty ? "搜索应用" : query)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(query.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)

                caret
            }

            Spacer(minLength: 16)

            Text("\(appCount) 个应用")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(width: 440, height: 46)
        .background {
            RoundedRectangle(cornerRadius: LaunchpadTheme.searchCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: LaunchpadTheme.searchCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LaunchpadTheme.searchCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }

    /// 这个面板随时都在接收按键，搜索框不需要先点一下就能打字，
    /// 所以光标一直显示（内容为空时也显示），避免用户看不出能不能输入。
    private var caret: some View {
        TimelineView(.animation(minimumInterval: Self.blinkInterval, paused: !isActive)) { timeline in
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(LaunchpadTheme.accent)
                .frame(width: 1.6, height: 20)
                .opacity(isCaretVisible(at: timeline.date) ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    private func isCaretVisible(at date: Date) -> Bool {
        guard !reduceMotion else {
            return true
        }
        let blink = Int(date.timeIntervalSinceReferenceDate / Self.blinkInterval)
        return blink.isMultiple(of: 2)
    }
}
