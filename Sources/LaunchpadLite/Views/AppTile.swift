import SwiftUI

struct AppTile: View {
    let app: LaunchpadAppItem
    let isSelected: Bool
    let isEditing: Bool
    let isHidden: Bool
    let isDragging: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onToggleHidden: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 104)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: LaunchpadTheme.tileWidth, height: LaunchpadTheme.tileHeight)
        .padding(.vertical, LaunchpadTheme.tileVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                .fill(tileBackground)
                .shadow(color: cardShadow, radius: 12, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(
                        lineWidth: isSelected || isDragging ? 2 : 1,
                        dash: isDragging ? [6, 4] : []
                    )
                )
        }
        .overlay(alignment: .topLeading) {
            if isUserInstalled {
                installedMarker
            }
        }
        // Hidden apps are greyed out, but the restore badge stays crisp on top.
        .grayscale(isHidden ? 0.9 : 0)
        .opacity(isDragging ? 0.25 : (isHidden ? 0.42 : 1))
        .overlay(alignment: .topTrailing) {
            if isEditing {
                editBadge
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous))
        .scaleEffect(isHovering && !reduceMotion ? 1.025 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(app.isOfficialApp ? "Apple 官方应用" : "自己安装的应用") {}
                .disabled(true)
            Divider()
            Button("打开", action: onOpen)
            Button("在 Finder 中显示", action: onReveal)
            Divider()
            Button(isHidden ? "恢复到面板" : "从面板移除", action: onToggleHidden)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if isEditing {
                onToggleHidden()
            } else {
                onOpen()
            }
        }
    }

    private var borderColor: Color {
        if isDragging {
            return LaunchpadTheme.accent.opacity(0.6)
        }
        if isSelected {
            return LaunchpadTheme.accent
        }
        return Color.black.opacity(isHovering ? 0.10 : 0)
    }

    private var helpText: String {
        if isEditing {
            return isHidden ? "点击恢复到面板" : "点击从面板移除"
        }
        return app.isOfficialApp ? "Apple 官方应用" : "自己安装的应用"
    }

    private var editBadge: some View {
        Image(systemName: isHidden ? "plus" : "xmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isHidden ? Color.white : Color.black.opacity(0.62))
            .frame(width: 22, height: 22)
            .background {
                Circle()
                    .fill(isHidden ? LaunchpadTheme.accent : Color.white.opacity(0.94))
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.black.opacity(isHidden ? 0 : 0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .padding(8)
            .accessibilityHidden(true)
    }

    /// Anything Apple did not ship: those are the apps added by hand.
    private var isUserInstalled: Bool {
        !app.isOfficialApp
    }

    /// Marks apps that were installed by hand, alongside a faint tile tint so
    /// the group is readable at a glance rather than dot by dot.
    private var installedMarker: some View {
        Circle()
            .fill(Color.black.opacity(0.36))
            .frame(width: 7, height: 7)
            .padding(10)
            .accessibilityHidden(true)
    }

    private var tileBackground: Color {
        if isSelected {
            return Color.white.opacity(0.72)
        }
        if isHovering {
            return Color.white.opacity(isUserInstalled ? 0.52 : 0.34)
        }
        return isUserInstalled ? Color.white.opacity(0.38) : Color.clear
    }

    private var cardShadow: Color {
        if isHovering {
            return Color.black.opacity(0.10)
        }
        return isUserInstalled ? Color.black.opacity(0.06) : Color.clear
    }
}
