import AppKit
import Common

extension Workspace {
    @MainActor // todo can be dropped in future Swift versions?
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in mointors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, LayoutContext(self))
    }
}

extension TreeNode {
    @MainActor // todo can be dropped in future Swift versions?
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId {
                    lastAppliedLayoutVirtualRect = virtual
                    if window.isFullscreen && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        window.isFullscreen = false
                        window.setAxFrame(point, CGSize(width: width, height: height))
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                // Dwindle is the only layout now
                try await container.layoutDwindle(point, width: width, height: height, virtual: virtual, context)
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor // todo can be dropped in future Swift versions?
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let currentMonitor = try await getCenter()?.monitorApproximation // Probably not idempotent
        if let currentMonitor, let windowTopLeftCorner = try await getAxTopLeftCorner(), workspace != currentMonitor.activeWorkspace {
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let moveTo = workspace.workspaceMonitor
            setAxTopLeftCorner(CGPoint(
                x: moveTo.visibleRect.topLeftX + xProportion * moveTo.visibleRect.width,
                y: moveTo.visibleRect.topLeftY + yProportion * moveTo.visibleRect.height,
            ))
        }
        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor // todo can be dropped in future Swift versions?
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    /// The fraction of the split box that the first (left/top) side of a dwindle split occupies.
    ///
    /// Hyprland stores a `splitRatio` splittable between `0.1` and `1.9`, where `0.5` means an even
    /// split. The equivalent fraction is `ratio / (1 + ratio)`, which is the same thing as
    /// `firstWeight / (firstWeight + secondWeight)`. The result is clamped to `0.05...0.95` so that
    /// neither side of the split can collapse to zero (the fraction form of Hyprland's clamp).
    ///
    /// Pure and free of AppKit and actor state on purpose: the parity rules are unit-tested directly.
    ///
    /// Weights are shares, not signed quantities. A non-finite weight is a programming error and falls
    /// back to an even split; a non-positive weight is floored at zero, because `resize` is
    /// weight-conserving in absolute units and therefore pushes the non-target sibling through zero on
    /// a two-child container. Flooring keeps the surviving share finite so the clamp still applies,
    /// instead of silently reverting the user's resize to an even split.
    nonisolated static func dwindleFraction(firstWeight: CGFloat, secondWeight: CGFloat) -> CGFloat {
        guard firstWeight.isFinite, secondWeight.isFinite else { return 0.5 }
        let first = max(firstWeight, 0)
        let second = max(secondWeight, 0)
        let sum = first + second
        guard sum > 0 else { return 0.5 }
        return min(max(first / sum, 0.05), 0.95)
    }

    @MainActor // todo can be dropped in future Swift versions?
    fileprivate func layoutDwindle(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        // Dwindle layout uses a binary tree approach with automatic split direction selection
        // The split direction is determined by the container's aspect ratio
        guard !children.isEmpty else { return }
        
        if children.count == 1 {
            // Single child takes full space
            try await children[0].layoutRecursive(point, width: width, height: height, virtual: virtual, context)
            return
        }
        
        // For multiple children, we need to create a binary tree structure
        // We'll split the container and assign children to left/right or top/bottom
        try await layoutDwindleRecursive(children, point: point, width: width, height: height, virtual: virtual, context: context)
    }
    
    @MainActor
    private func layoutDwindleRecursive(_ nodes: [TreeNode], point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, context: LayoutContext) async throws {
        guard !nodes.isEmpty else { return }
        
        if nodes.count == 1 {
            // Single node takes full space
            try await nodes[0].layoutRecursive(point, width: width, height: height, virtual: virtual, context)
            return
        }
        
        // Determine split direction based on aspect ratio
        // Wider containers split vertically, taller ones split horizontally
        let splitVertically = width >= height
        
        // Get gap size for the split direction
        let gapSize = splitVertically 
            ? context.resolvedGaps.inner.horizontal.toDouble()
            : context.resolvedGaps.inner.vertical.toDouble()
        
        // Calculate midpoint for splitting
        let midIndex = nodes.count / 2
        let leftNodes = Array(nodes[0..<midIndex])
        let rightNodes = Array(nodes[midIndex...])

        // Weighted split ratio (Hyprland dwindle parity). Weights only make sense along the axis the
        // container actually splits on; a node's own weight must never be mixed with the weight of an
        // ancestor that happens to run along a different axis, which is what getWeight would return.
        let axis: Orientation = splitVertically ? .h : .v
        let splitRatio: CGFloat = orientation == axis
            ? Self.dwindleFraction(
                firstWeight: leftNodes.map { $0.getWeight(axis) }.reduce(CGFloat(0), +),
                secondWeight: rightNodes.map { $0.getWeight(axis) }.reduce(CGFloat(0), +),
            )
            : 0.5
        
        if splitVertically {
            // Split left/right with gap
            let totalWidth = width - gapSize
            let leftWidth = totalWidth * splitRatio
            let rightWidth = totalWidth - leftWidth
            
            // Layout left side
            try await layoutDwindleRecursive(leftNodes, point: point, width: leftWidth, height: height, 
                                 virtual: Rect(topLeftX: virtual.topLeftX, topLeftY: virtual.topLeftY, 
                                             width: virtual.width * splitRatio, height: virtual.height), 
                                 context: context)
            
            // Layout right side (with gap offset)
            try await layoutDwindleRecursive(rightNodes, point: CGPoint(x: point.x + leftWidth + gapSize, y: point.y), 
                                 width: rightWidth, height: height,
                                 virtual: Rect(topLeftX: virtual.topLeftX + virtual.width * splitRatio, 
                                             topLeftY: virtual.topLeftY, 
                                             width: virtual.width * (1 - splitRatio), height: virtual.height),
                                 context: context)
        } else {
            // Split top/bottom with gap
            let totalHeight = height - gapSize
            let topHeight = totalHeight * splitRatio
            let bottomHeight = totalHeight - topHeight
            
            // Layout top side
            try await layoutDwindleRecursive(leftNodes, point: point, width: width, height: topHeight,
                                 virtual: Rect(topLeftX: virtual.topLeftX, topLeftY: virtual.topLeftY,
                                             width: virtual.width, height: virtual.height * splitRatio),
                                 context: context)
            
            // Layout bottom side (with gap offset)
            try await layoutDwindleRecursive(rightNodes, point: CGPoint(x: point.x, y: point.y + topHeight + gapSize),
                                 width: width, height: bottomHeight,
                                 virtual: Rect(topLeftX: virtual.topLeftX, 
                                             topLeftY: virtual.topLeftY + virtual.height * splitRatio,
                                             width: virtual.width, height: virtual.height * (1 - splitRatio)),
                                 context: context)
        }
    }
}
