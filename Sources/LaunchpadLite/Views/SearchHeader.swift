import SwiftUI

struct SearchHeader: View {
    let query: String
    let appCount: Int

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

                if !query.isEmpty {
                    Rectangle()
                        .fill(LaunchpadTheme.accent)
                        .frame(width: 1.5, height: 20)
                }
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
}
