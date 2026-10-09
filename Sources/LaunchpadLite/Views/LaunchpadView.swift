import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let onLaunch: (LaunchpadAppItem) -> Void
    let onClose: () -> Void
    let onReveal: (LaunchpadAppItem) -> Void

    @State private var draggingAppID: String?
    @State private var draggedApp: LaunchpadAppItem?
    @State private var dragLocation: CGPoint?
    @State private var dropInsertionIndex: Int?
    @State private var saveButtonPulse = false

    private static let rootSpace = "launchpad-root"

    var body: some View {
        ZStack {
            background

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: handleBackgroundTap)
                .accessibilityHidden(true)

            VStack(spacing: 24) {
                header
                .padding(.top, 34)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                PageIndicator(
                    pageCount: viewModel.pageCount,
                    currentPage: viewModel.page,
                    onSelect: viewModel.selectPage
                )
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 64)

            pageFlipHint

            if let draggedApp, let dragLocation {
                dragProxy(for: draggedApp)
                    .position(dragLocation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.rootSpace)
        .preferredColorScheme(.light)
        .onChange(of: viewModel.hiddenChangeToken) { _, _ in
            // Remind the user that the change still has to be confirmed with 完成.
            saveButtonPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                saveButtonPulse = false
            }
        }
    }

    private var background: some View {
        AnimatedGradientBackground(isActive: viewModel.isPanelVisible)
    }

    private var header: some View {
        ZStack {
            SearchHeader(
                query: viewModel.query,
                appCount: viewModel.visibleApps.count,
                isActive: viewModel.isPanelVisible
            )

            HStack {
                Spacer(minLength: 0)

                if viewModel.isEditing, viewModel.hiddenAppCount > 0 {
                    Text("已隐藏 \(viewModel.hiddenAppCount) 个")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .padding(.trailing, 4)
                }

                if !viewModel.isEditing {
                    HeaderIconButton(
                        systemName: viewModel.isCurrentPageHome ? "house.fill" : "house",
                        isActive: viewModel.isCurrentPageHome,
                        isEnabled: viewModel.query.isEmpty,
                        helpText: viewModel.isCurrentPageHome ? "已设为主页，点击取消" : "把当前页面设为主页",
                        accessibilityText: viewModel.isCurrentPageHome ? "取消主页" : "设为主页",
                        action: viewModel.toggleHomePage
                    )
                }

                HeaderIconButton(
                    systemName: viewModel.isEditing ? "checkmark" : "pencil",
                    isActive: viewModel.isEditing,
                    isEnabled: true,
                    isPulsing: saveButtonPulse,
                    helpText: viewModel.isEditing ? "完成编辑" : "编辑：拖动排序、移除应用",
                    accessibilityText: viewModel.isEditing ? "完成编辑" : "编辑图标",
                    action: viewModel.toggleEditing
                )
            }
        }
        .frame(maxWidth: 1_360)
    }

    private func handleBackgroundTap() {
        if viewModel.isEditing {
            viewModel.setEditing(false)
        } else {
            onClose()
        }
    }

    /// Shown while a drag is dwelling on the outer column, hinting that the grid
    /// is about to turn the page.
    @ViewBuilder
    private var pageFlipHint: some View {
        if let direction = viewModel.pendingPageFlip {
            HStack(spacing: 0) {
                if direction < 0 {
                    flipIndicator("chevron.left")
                }

                Spacer(minLength: 0)

                if direction > 0 {
                    flipIndicator("chevron.right")
                }
            }
            .padding(.horizontal, 26)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: viewModel.pendingPageFlip)
        }
    }

    private func flipIndicator(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(width: 44, height: 76)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        // Only take over the screen on the very first load: a background rescan
        // (new app installed while the panel is open) shouldn't blank the grid.
        if viewModel.isLoading && viewModel.apps.isEmpty {
            LoadingState()
        } else if let errorMessage = viewModel.errorMessage {
            ErrorState(message: errorMessage) {
                viewModel.reload(force: true)
            }
        } else if viewModel.visibleApps.isEmpty {
            EmptyState(isSearching: !viewModel.query.isEmpty)
        } else {
            appGrid
        }
    }

    private var appGrid: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageCount = max(1, viewModel.pageCount)
            let rootOrigin = geometry.frame(in: .named(Self.rootSpace)).origin

            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { pageIndex in
                    pageGrid(
                        items: viewModel.apps(on: pageIndex),
                        pageIndex: pageIndex,
                        pageWidth: pageWidth,
                        rootOrigin: rootOrigin
                    )
                        .frame(width: pageWidth, alignment: .top)
                        .allowsHitTesting(pageIndex == viewModel.page)
                }
            }
            .frame(width: pageWidth * CGFloat(pageCount), alignment: .leading)
            .offset(x: -CGFloat(viewModel.page) * pageWidth)
        }
        .frame(maxWidth: 1_360, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func pageGrid(
        items: [LaunchpadAppItem],
        pageIndex: Int,
        pageWidth: CGFloat,
        rootOrigin: CGPoint
    ) -> some View {
        let metrics = LaunchpadGridMetrics(
            columns: max(1, viewModel.layout.columns),
            pageWidth: pageWidth
        )
        let columns = Array(
            repeating: GridItem(
                .fixed(LaunchpadTheme.tileWidth),
                spacing: LaunchpadTheme.tileSpacing,
                alignment: .top
            ),
            count: max(1, viewModel.layout.columns)
        )

        return LazyVGrid(columns: columns, alignment: .center, spacing: LaunchpadTheme.gridSpacing) {
            ForEach(items) { app in
                tile(for: app, pageIndex: pageIndex, metrics: metrics, rootOrigin: rootOrigin)
            }
        }
        .padding(.horizontal, LaunchpadTheme.gridHorizontalPadding)
        .coordinateSpace(name: Self.pageSpaceName(pageIndex))
        .overlay(alignment: .topLeading) {
            dropIndicator(pageIndex: pageIndex, metrics: metrics, itemCount: items.count)
        }
    }

    private static func pageSpaceName(_ pageIndex: Int) -> String {
        "launchpad-page-\(pageIndex)"
    }

    /// Thin accent bar showing where the dragged icon would land.
    @ViewBuilder
    private func dropIndicator(
        pageIndex: Int,
        metrics: LaunchpadGridMetrics,
        itemCount: Int
    ) -> some View {
        if let globalIndex = dropInsertionIndex {
            let localIndex = globalIndex - pageIndex * max(1, viewModel.layout.pageSize)
            if localIndex >= 0, localIndex <= itemCount {
                let origin = metrics.slotOrigin(localIndex: localIndex)
                let tileOrigin = CGPoint(
                    x: origin.x + LaunchpadTheme.tileSpacing / 2,
                    y: origin.y
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                        .fill(LaunchpadTheme.accent.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                                .strokeBorder(LaunchpadTheme.accent.opacity(0.45), lineWidth: 1.5)
                        }
                        .frame(
                            width: LaunchpadTheme.tileWidth,
                            height: LaunchpadTheme.tileHeight + LaunchpadTheme.tileVerticalPadding * 2
                        )
                        .offset(x: tileOrigin.x, y: tileOrigin.y)

                    Capsule()
                        .fill(LaunchpadTheme.accent)
                        .frame(width: 4, height: LaunchpadTheme.tileHeight)
                        .offset(x: origin.x - 2, y: origin.y)
                }
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func tile(
        for app: LaunchpadAppItem,
        pageIndex: Int,
        metrics: LaunchpadGridMetrics,
        rootOrigin: CGPoint
    ) -> some View {
        let isHidden = viewModel.isHidden(app)
        let tile = AppTile(
            app: app,
            isSelected: viewModel.selectedApp?.id == app.id,
            isEditing: viewModel.isEditing,
            isHidden: isHidden,
            isDragging: draggingAppID == app.id,
            onOpen: { onLaunch(app) },
            onReveal: { onReveal(app) },
            onToggleHidden: { viewModel.setHidden(!isHidden, for: app) }
        )
        .onHover { hovering in
            if hovering {
                viewModel.select(app: app)
            }
        }

        tile.gesture(
            tileGesture(for: app, pageIndex: pageIndex, metrics: metrics, rootOrigin: rootOrigin)
        )
    }

    /// Hand-rolled drag: SwiftUI's `draggable` never started a session inside
    /// this borderless overlay panel, so clicks and drags are handled here.
    private func tileGesture(
        for app: LaunchpadAppItem,
        pageIndex: Int,
        metrics: LaunchpadGridMetrics,
        rootOrigin: CGPoint
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.rootSpace))
            .onChanged { value in
                if draggingAppID == nil {
                    guard Self.isDragMovement(value.translation) else {
                        return
                    }
                    draggingAppID = app.id
                    draggedApp = app
                    viewModel.select(app: app)
                }

                dragLocation = value.location
                updateDropTarget(
                    // The drop target is whatever page is on screen now, so the
                    // pointer is converted into page-local coordinates.
                    at: CGPoint(
                        x: value.location.x - rootOrigin.x,
                        y: value.location.y - rootOrigin.y
                    ),
                    pageIndex: viewModel.page,
                    metrics: metrics
                )
            }
            .onEnded { _ in
                if draggingAppID == nil {
                    activate(app)
                } else {
                    commitDrag()
                }
            }
    }

    private static func isDragMovement(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > 6
    }

    private func updateDropTarget(
        at location: CGPoint,
        pageIndex: Int,
        metrics: LaunchpadGridMetrics
    ) {
        let localIndex = metrics.slotIndex(
            at: location,
            itemCount: viewModel.apps(on: pageIndex).count
        )
        dropInsertionIndex = min(
            pageIndex * max(1, viewModel.layout.pageSize) + localIndex,
            viewModel.visibleApps.count
        )

        viewModel.armPageFlip(
            LaunchpadViewModel.pageFlipDirection(
                pointerX: location.x,
                pageWidth: metrics.pageWidth,
                pageIndex: pageIndex,
                pageCount: viewModel.pageCount
            )
        )
    }

    private func commitDrag() {
        if let draggingAppID, let dropInsertionIndex {
            viewModel.moveApp(id: draggingAppID, beforeIndex: dropInsertionIndex)
        }
        draggingAppID = nil
        draggedApp = nil
        dragLocation = nil
        dropInsertionIndex = nil
        viewModel.cancelPageFlip()
    }

    /// Lifted copy of the icon that follows the pointer while dragging.
    private func dragProxy(for app: LaunchpadAppItem) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 104)
        }
        .frame(width: LaunchpadTheme.tileWidth, height: LaunchpadTheme.tileHeight)
        .padding(.vertical, LaunchpadTheme.tileVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LaunchpadTheme.tileCornerRadius, style: .continuous)
                .strokeBorder(LaunchpadTheme.accent.opacity(0.85), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
        .scaleEffect(1.08)
        .allowsHitTesting(false)
    }

    /// A press that never turned into a drag: launches, or toggles in edit mode.
    private func activate(_ app: LaunchpadAppItem) {
        if viewModel.isEditing {
            viewModel.setHidden(!viewModel.isHidden(app), for: app)
        } else {
            onLaunch(app)
        }
    }
}

/// Circular frosted button used in the header row.
private struct HeaderIconButton: View {
    let systemName: String
    let isActive: Bool
    let isEnabled: Bool
    var isPulsing = false
    let helpText: String
    let accessibilityText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? LaunchpadTheme.accent : Color.black.opacity(0.55))
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)

                    Circle()
                        .fill(Color.white.opacity(isHovering ? 0.62 : 0.34))
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isPulsing ? LaunchpadTheme.accent.opacity(0.9) : Color.white.opacity(0.75),
                            lineWidth: isPulsing ? 2 : 1
                        )
                }
                .shadow(
                    color: isPulsing ? LaunchpadTheme.accent.opacity(0.35) : .black.opacity(0.08),
                    radius: isPulsing ? 14 : 12,
                    y: 5
                )
                .scaleEffect(isPulsing ? 1.16 : (isHovering ? 1.05 : 1))
                .animation(.easeOut(duration: 0.15), value: isActive)
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPulsing)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }
}

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在整理应用")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("重新扫描", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isSearching ? "magnifyingglass" : "square.grid.3x3")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.secondary)

            Text(isSearching ? "没有找到匹配的应用" : "暂时没有发现可显示的应用")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
