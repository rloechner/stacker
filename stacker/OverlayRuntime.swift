import SwiftUI
import Observation
import AppKit
import ApplicationServices

private enum OverlayAttachmentPreference {
    static let key = "stacker.overlayAttachmentOffsets.v2"
    private static let horizontalOffsetKey = "horizontalOffset"
    private static let verticalOffsetKey = "verticalOffset"

    static func identifier(bundleIdentifier: String?, appName: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return "name:\(appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func storedValues(bundleIdentifier: String?, appName: String) -> [String: Double] {
        let identifier = identifier(bundleIdentifier: bundleIdentifier, appName: appName)
        let offsets = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        return offsets[identifier] ?? [:]
    }

    static func currentHorizontalOffset(bundleIdentifier: String?, appName: String) -> CGFloat {
        CGFloat(storedValues(bundleIdentifier: bundleIdentifier, appName: appName)[horizontalOffsetKey] ?? -100_000)
    }

    static func currentVerticalOffset(bundleIdentifier: String?, appName: String) -> CGFloat {
        CGFloat(storedValues(bundleIdentifier: bundleIdentifier, appName: appName)[verticalOffsetKey] ?? 0)
    }

    static func setHorizontalOffset(_ offset: CGFloat, bundleIdentifier: String?, appName: String) {
        let identifier = identifier(bundleIdentifier: bundleIdentifier, appName: appName)
        var offsets = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        var values = offsets[identifier] ?? [:]
        values[horizontalOffsetKey] = Double(offset)
        offsets[identifier] = values
        UserDefaults.standard.set(offsets, forKey: key)
    }

    static func setVerticalOffset(_ offset: CGFloat, bundleIdentifier: String?, appName: String) {
        let identifier = identifier(bundleIdentifier: bundleIdentifier, appName: appName)
        var offsets = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        var values = offsets[identifier] ?? [:]
        values[verticalOffsetKey] = Double(offset)
        offsets[identifier] = values
        UserDefaults.standard.set(offsets, forKey: key)
    }

    static func resetOffset(bundleIdentifier: String?, appName: String) {
        let identifier = identifier(bundleIdentifier: bundleIdentifier, appName: appName)
        var offsets = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        offsets.removeValue(forKey: identifier)
        UserDefaults.standard.set(offsets, forKey: key)
    }
}

private struct PanelAnchorDragHandle: NSViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    let excludedRects: [CGRect]

    func makeNSView(context: Context) -> PanelAnchorDragHandleView {
        let view = PanelAnchorDragHandleView()
        view.onTap = onTap
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.excludedRects = excludedRects
        return view
    }

    func updateNSView(_ nsView: PanelAnchorDragHandleView, context: Context) {
        nsView.onTap = onTap
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.excludedRects = excludedRects
    }
}

private final class PanelAnchorDragHandleView: NSView {
    var onTap: ((CGPoint) -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    var excludedRects: [CGRect] = []

    private var dragStartScreenPoint: NSPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        if excludedRects.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(point) }) {
            return nil
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = screenPoint(for: event)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartScreenPoint else { return }
        let currentPoint = screenPoint(for: event)
        let delta = CGSize(
            width: currentPoint.x - dragStartScreenPoint.x,
            height: currentPoint.y - dragStartScreenPoint.y
        )
        if !didDrag, hypot(delta.width, delta.height) > 2 {
            didDrag = true
        }
        onDragChanged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartScreenPoint = nil
            didDrag = false
        }
        if didDrag {
            onDragEnded?()
        } else {
            let point = convert(event.locationInWindow, from: nil)
            onTap?(point)
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return event.locationInWindow
    }
}

private struct SecondaryClickGestureHandle: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> SecondaryClickGestureHandleView {
        let view = SecondaryClickGestureHandleView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickGestureHandleView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }
}

private final class SecondaryClickGestureHandleView: NSView {
    var onSecondaryClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTransparency()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTransparency()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return self
        default:
            return nil
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onSecondaryClick?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    override func layout() {
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

enum SuggestionOverlayStyle {
    case createStack(windowCount: Int)
    case addBack(titles: [String])   // multiple windows that can be added back
}

private struct CombineOverlayView: View {
    let style: SuggestionOverlayStyle
    let onTap: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.regularMaterial)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.64),
                            Color(red: 0.91, green: 0.95, blue: 1.0).opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(1)

            PanelAnchorDragHandle(
                onTap: { _ in onTap() },
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                excludedRects: []
            )

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.94),
                                    Color.accentColor.opacity(0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: leadingSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)

                Text(primaryTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let countText {
                    Text(countText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.64))
                        )
                }

                // For Add Back, show a mini dot strip to resemble the main widget
                if case .addBack(let titles) = style, titles.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(Array(titles.prefix(4)), id: \.self) { _ in
                            Circle()
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
            .allowsHitTesting(false)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .help(secondaryTitle)
    }

    private var leadingSymbol: String {
        switch style {
        case .createStack:
            return "square.stack.3d.up.badge.a.fill"
        case .addBack:
            return "plus.circle.fill"
        }
    }

    private var primaryTitle: String {
        switch style {
        case .createStack:
            return "Link Windows"
        case .addBack(let titles):
            return titles.count == 1 ? "Add Back" : "Add Back (\(titles.count))"
        }
    }

    private var countText: String? {
        switch style {
        case .createStack(let windowCount):
            return "\(windowCount)"
        case .addBack:
            return nil
        }
    }

    private var secondaryTitle: String {
        switch style {
        case .createStack(let windowCount):
            return "Link \(windowCount) open browser windows"
        case .addBack(let titles):
            if titles.count == 1 {
                return "Add \(titles[0]) back into this stack"
            } else {
                return "Add any of these \(titles.count) windows back into the stack"
            }
        }
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    var onSecondaryClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init(rootView: Content, ignoreSafeArea: Bool) {
        fatalError("init(rootView:ignoreSafeArea:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @inline(never)
    deinit {
        onSecondaryClick = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    override func layout() {
        super.layout()
    }

    override func updateLayer() {
        configureTransparency()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
        configureTransparency()
    }

    override func rightMouseUp(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onSecondaryClick?()
        } else {
            super.otherMouseUp(with: event)
        }
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        superview?.wantsLayer = true
        superview?.layer?.isOpaque = false
        superview?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class TransparentContainerView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTransparency()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTransparency()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    override func layout() {
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() {
            let convertedPoint = convert(point, to: subview)
            if let hitView = subview.hitTest(convertedPoint) {
                return hitView
            }
        }
        return nil
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private func invalidateOverlayRendering(for window: NSWindow) {
    guard let contentView = window.contentView else { return }
    invalidateOverlayRendering(in: contentView)
    contentView.layoutSubtreeIfNeeded()
    contentView.displayIfNeeded()
    window.invalidateShadow()
}

private func invalidateOverlayRendering(in view: NSView) {
    view.invalidateIntrinsicContentSize()
    view.needsLayout = true
    view.needsDisplay = true
    view.layer?.setNeedsDisplay()
    view.subviews.forEach(invalidateOverlayRendering)
}

private final class WidgetOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private func configureOverlayPanel(_ panel: NSPanel) {
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.becomesKeyOnlyIfNeeded = true
    panel.ignoresMouseEvents = false
    panel.isMovableByWindowBackground = false
}

private let stackOverlayDragOverflowMargin: CGFloat = 0

private struct StackOverlayItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UInt: CGRect] = [:]

    static func reduce(value: inout [UInt: CGRect], nextValue: () -> [UInt: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct StackOverlayCollapsedItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UInt: CGRect] = [:]

    static func reduce(value: inout [UInt: CGRect], nextValue: () -> [UInt: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum StackOverlayChromeAction: Hashable {
    case focusStack
    case openEditor
    case toggleControls
}

private struct StackOverlayChromeActionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [StackOverlayChromeAction: CGRect] = [:]

    static func reduce(value: inout [StackOverlayChromeAction: CGRect], nextValue: () -> [StackOverlayChromeAction: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@Observable
private final class StackOverlayViewModel {
    var items: [StackOverlayItem]
    var addableWindows: [StackOverlayAddableWindow]
    var controlsPinnedOpen: Bool
    var appearance: StackOverlayAppearance
    var isShowingConfig: Bool
    var displayMode: StackOverlayDisplayMode
    var labelMode: StackOverlayLabelMode
    var densityMode: StackOverlayDensityMode
    var placementPreference: StackOverlayPlacementPreference
    var dockPosition: StackOverlayDockPosition
    var horizontalSide: StackOverlayHorizontalSide
    var maxPrimaryWindowWidth: CGFloat?
    var overlayHealth: StackOverlayHealth
    var isWindowChanging: Bool

    init(
        items: [StackOverlayItem] = [],
        addableWindows: [StackOverlayAddableWindow] = [],
        controlsPinnedOpen: Bool = false,
        appearance: StackOverlayAppearance = .system,
        isShowingConfig: Bool = false,
        displayMode: StackOverlayDisplayMode,
        labelMode: StackOverlayLabelMode,
        densityMode: StackOverlayDensityMode = .comfortable,
        placementPreference: StackOverlayPlacementPreference = .automatic,
        dockPosition: StackOverlayDockPosition,
        horizontalSide: StackOverlayHorizontalSide = .left,
        maxPrimaryWindowWidth: CGFloat? = nil,
        overlayHealth: StackOverlayHealth = .visible,
        isWindowChanging: Bool = false
    ) {
        self.items = items
        self.addableWindows = addableWindows
        self.controlsPinnedOpen = controlsPinnedOpen
        self.appearance = appearance
        self.isShowingConfig = isShowingConfig
        self.displayMode = displayMode
        self.labelMode = labelMode
        self.densityMode = densityMode
        self.placementPreference = placementPreference
        self.dockPosition = dockPosition
        self.horizontalSide = horizontalSide
        self.maxPrimaryWindowWidth = maxPrimaryWindowWidth
        self.overlayHealth = overlayHealth
        self.isWindowChanging = isWindowChanging
    }
}

private struct StackOverlayStripView: View {
    let appName: String
    let stackPID: Int32
    let model: StackOverlayViewModel
    let onSelect: (UInt) -> Void
    let onToggleConfig: () -> Void
    let onToggleDisplayMode: () -> Void
    let onToggleLabelMode: () -> Void
    let onSetDensityMode: (StackOverlayDensityMode) -> Void
    let onBackgroundDragChanged: (CGSize) -> Void
    let onBackgroundDragEnded: () -> Void
    let onSetControlsPinnedOpen: (Bool) -> Void
    let onSetAppearance: (StackOverlayAppearance) -> Void
    let onSetPlacementPreference: (StackOverlayPlacementPreference) -> Void
    let onSetDockPosition: (StackOverlayDockPosition) -> Void
    let onAddWindow: (UInt) -> Void
    let onOpenEditor: () -> Void
    let onHideWidget: () -> Void
    let onResetPosition: () -> Void
    let onFocusStack: () -> Void
    let onTurnOff: () -> Void
    let onMove: (UInt, Int) -> Void
    let onReorder: (UInt, UInt) -> Void
    let onRemove: (UInt) -> Void

    private struct RemovalAnimationState: Identifiable {
        let item: StackOverlayItem
        let frame: CGRect
        let position: CGPoint

        var id: UInt { item.id }
    }

    @State private var draggingWindowID: UInt?
    @State private var dragTranslation: CGSize = .zero
    @State private var itemFrames: [UInt: CGRect] = [:]
    @State private var collapsedItemFrames: [UInt: CGRect] = [:]
    @State private var chromeActionFrames: [StackOverlayChromeAction: CGRect] = [:]
    @State private var hoveredWindowID: UInt?
    @State private var hoveredRemoveBadgeID: UInt?
    @State private var removalAnimation: RemovalAnimationState?
    @State private var removalAnimationProgress: CGFloat = 0

    private var densityMetrics: StackOverlayDensityMode { model.densityMode }
    private var appearance: StackOverlayAppearance { model.appearance }
    private var widgetMoveGutter: CGFloat { densityMetrics.widgetChromeInset }

    var body: some View {
        if model.overlayHealth == .degraded {
            // For degraded stacks the widget simply disappears (per user preference for clean failure).
            // The stack remains in the sidebar/menu with "Paused" status and can be retried.
            EmptyView()
        } else {
            collapsedEdgeMarker
            .opacity(model.isWindowChanging ? 0.58 : 1.0)
            .scaleEffect(model.isWindowChanging ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: model.isWindowChanging)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.04), value: model.dockPosition)
            .coordinateSpace(name: "StackOverlayWidget")
            .padding(.horizontal, stackOverlayDragOverflowMargin)
            .padding(.top, stackOverlayDragOverflowMargin)
            .padding(.bottom, stackOverlayDragOverflowMargin + widgetBottomInset)
            .fixedSize()
            .overlayColorScheme(appearance)
        }
    }

    private var railBackgroundColors: [Color] {
        switch appearance {
        case .system, .light:
            return [
                Color.white.opacity(0.90),
                Color(red: 0.95, green: 0.97, blue: 0.99).opacity(0.68)
            ]
        case .dark:
            return [
                Color(red: 0.18, green: 0.19, blue: 0.21).opacity(0.88),
                Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.74)
            ]
        }
    }

    private var railOverlayColors: [Color] {
        switch appearance {
        case .system, .light:
            return [Color.white.opacity(0.20), Color.white.opacity(0.02)]
        case .dark:
            return [Color.white.opacity(0.12), Color.black.opacity(0.18)]
        }
    }

    private var railBorderColor: Color {
        switch appearance {
        case .system, .light:
            return Color.primary.opacity(0.04)
        case .dark:
            return Color.white.opacity(0.10)
        }
    }

    private var neutralTabColors: [Color] {
        switch appearance {
        case .system, .light:
            return [Color.white.opacity(0.72), Color.white.opacity(0.52)]
        case .dark:
            return [
                Color.white.opacity(0.12),
                Color.white.opacity(0.06)
            ]
        }
    }

    private var widgetBottomInset: CGFloat {
        0
    }

    private var isHorizontalDock: Bool {
        model.dockPosition.isHorizontal
    }

    private var horizontalTabs: some View {
        VStack(alignment: model.horizontalSide == .left ? .leading : .trailing, spacing: 12) {
            switcherRail
        }
    }

    private var verticalRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: model.dockPosition == .top ? .top : .bottom, spacing: 12) {
                verticalItemsStack
            }
        }
    }

    private var collapsedEdgeMarker: some View {
        ZStack {
            compactIndicatorStrip

            PanelAnchorDragHandle(
                onTap: handleCollapsedMarkerTap,
                onDragChanged: onBackgroundDragChanged,
                onDragEnded: onBackgroundDragEnded,
                excludedRects: []
            )
        }
        .coordinateSpace(name: "StackOverlayCollapsedStrip")
        .compositingGroup()
        .contextMenu { controlsContextMenu }
        .help("Click a window icon to focus its browser window. Drag the widget to move it.")
        .onPreferenceChange(StackOverlayCollapsedItemFramePreferenceKey.self) { collapsedItemFrames = $0 }
        .onPreferenceChange(StackOverlayChromeActionFramePreferenceKey.self) { chromeActionFrames = $0 }
    }

    private var collapsedInteractiveRects: [CGRect] {
        Array(collapsedItemFrames.values)
    }

    private var switcherRail: some View {
        windowTabsRail
    }

    private var compactIndicatorStrip: some View {
        Group {
            if isHorizontalDock {
                horizontalCapStrip
            } else {
                verticalCapStrip
            }
        }
    }

    private var horizontalCapStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: collapsedStripSpacing) {
                ForEach(model.items) { item in
                    collapsedTab(for: item)
                }
            }

            if showsCollapsedUtilities {
                horizontalCapDivider

                horizontalCapUtilities
            }
        }
        .padding(.horizontal, collapsedStripMainAxisPadding)
        .padding(.vertical, collapsedStripCrossAxisPadding)
        .background(horizontalCapChrome)
        .contentShape(horizontalCapShape)
    }

    private var verticalCapStrip: some View {
        VStack(spacing: collapsedStripSpacing) {
            ForEach(model.items) { item in
                collapsedTab(for: item)
            }

            if showsCollapsedUtilities {
                verticalCapDivider

                verticalCapUtilities
            }
        }
        .padding(.horizontal, collapsedStripCrossAxisPadding)
        .padding(.vertical, collapsedStripMainAxisPadding)
        .background(verticalCapChrome)
        .contentShape(verticalCapShape)
    }

    private var showsCollapsedChromeActions: Bool {
        densityMetrics != .compact
    }

    private var showsCollapsedUtilities: Bool {
        false
    }

    private var horizontalCapDivider: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(Color.black.opacity(0.10))
            .frame(width: 1, height: 20)
    }

    private var verticalCapDivider: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(Color.black.opacity(0.10))
            .frame(width: 20, height: 1)
    }

    private var horizontalCapGlyphs: some View {
        HStack(spacing: 18) {
            chromeGlyph("slider.horizontal.3", action: .toggleControls, help: model.controlsPinnedOpen ? "Hide widget controls" : "Show widget controls")
            chromeGlyph("rectangle.split.2x1", action: .focusStack, help: "Focus this stack")
            chromeGlyph("list.bullet.rectangle", action: .openEditor, help: "Open in Stacker")
        }
    }

    private var verticalCapGlyphs: some View {
        VStack(spacing: 12) {
            chromeGlyph("slider.horizontal.3", action: .toggleControls, help: model.controlsPinnedOpen ? "Hide widget controls" : "Show widget controls")
            chromeGlyph("rectangle.split.2x1", action: .focusStack, help: "Focus this stack")
            chromeGlyph("list.bullet.rectangle", action: .openEditor, help: "Open in Stacker")
        }
    }

    private var horizontalCapUtilities: some View {
        HStack(spacing: 18) {
            if model.overlayHealth.isAttentionState {
                attentionGlyph
            }

            if showsCollapsedChromeActions {
                horizontalCapGlyphs
            }
        }
    }

    private var verticalCapUtilities: some View {
        VStack(spacing: 12) {
            if model.overlayHealth.isAttentionState {
                attentionGlyph
            }

            if showsCollapsedChromeActions {
                verticalCapGlyphs
            }
        }
    }

    private var attentionGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.orange.opacity(0.9))
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                Circle()
                    .stroke(Color.orange.opacity(0.16), lineWidth: 1)
            )
            .help(model.overlayHealth.surfaceMessage)
    }

    private func chromeGlyph(_ systemImage: String, action: StackOverlayChromeAction, help: String) -> some View {
        Button {
            handleChromeAction(action)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.54))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.black.opacity(action == .toggleControls && model.controlsPinnedOpen ? 0.075 : 0.045))
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(action == .toggleControls && model.controlsPinnedOpen ? 0.10 : 0.055), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .background(chromeActionFrameReader(for: action))
        .help(help)
    }

    private var horizontalCapShape: UnevenRoundedRectangle {
        collapsedCapShape
    }

    private var verticalCapShape: UnevenRoundedRectangle {
        collapsedCapShape
    }

    private var collapsedCapShape: UnevenRoundedRectangle {
        let outerRadius = collapsedChromeOuterCornerRadius
        let attachedRadius = collapsedChromeAttachedCornerRadius

        switch model.dockPosition {
        case .top:
            return UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: attachedRadius,
                bottomTrailingRadius: attachedRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        case .bottom:
            return UnevenRoundedRectangle(
                topLeadingRadius: attachedRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: attachedRadius,
                style: .continuous
            )
        case .left:
            return UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: attachedRadius,
                topTrailingRadius: attachedRadius,
                style: .continuous
            )
        case .right:
            return UnevenRoundedRectangle(
                topLeadingRadius: attachedRadius,
                bottomLeadingRadius: attachedRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        }
    }

    private var collapsedChromeOuterCornerRadius: CGFloat {
        switch densityMetrics {
        case .compact:
            return 10
        case .comfortable:
            return 12
        case .expanded:
            return 14
        }
    }

    private var collapsedChromeAttachedCornerRadius: CGFloat {
        0
    }

    private var collapsedChromeDividerAlignment: Alignment {
        switch model.dockPosition {
        case .top:
            return .bottom
        case .bottom:
            return .top
        case .left:
            return .trailing
        case .right:
            return .leading
        }
    }

    private var collapsedChromeDividerStartPoint: UnitPoint {
        switch model.dockPosition {
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .leading
        case .right:
            return .trailing
        }
    }

    private var collapsedChromeDividerEndPoint: UnitPoint {
        switch model.dockPosition {
        case .top:
            return .bottom
        case .bottom:
            return .top
        case .left:
            return .trailing
        case .right:
            return .leading
        }
    }

    private func collapsedChromeBase(_ shape: UnevenRoundedRectangle) -> some View {
        shape
            .fill(.thinMaterial)
            .overlay {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
            }
    }

    @ViewBuilder
    private func collapsedChromeAttachmentLine() -> some View {
        if model.dockPosition == .bottom {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.02)
                        ],
                        startPoint: collapsedChromeDividerStartPoint,
                        endPoint: collapsedChromeDividerEndPoint
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 9)
        } else if model.dockPosition == .top {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.02)
                        ],
                        startPoint: collapsedChromeDividerStartPoint,
                        endPoint: collapsedChromeDividerEndPoint
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 9)
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.02)
                        ],
                        startPoint: collapsedChromeDividerStartPoint,
                        endPoint: collapsedChromeDividerEndPoint
                    )
                )
                .frame(width: 1)
                .padding(.vertical, 6)
        }
    }

    private var horizontalCapChrome: some View {
        let shape = horizontalCapShape

        return collapsedChromeBase(shape)
        .overlay {
            shape
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: collapsedChromeDividerAlignment) {
            collapsedChromeAttachmentLine()
        }
    }

    private var verticalCapChrome: some View {
        let shape = verticalCapShape

        return collapsedChromeBase(shape)
        .overlay {
            shape
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: collapsedChromeDividerAlignment) {
            collapsedChromeAttachmentLine()
        }
    }

    private func collapsedTab(for item: StackOverlayItem) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            collapsedTabBadge(for: item, diameter: collapsedDotDiameter)
        }
        .buttonStyle(.plain)
        .shadow(
            color: item.accent.tint.opacity(item.isSelected ? 0.58 : 0.06),
            radius: item.isSelected ? 11 : 2,
            y: item.isSelected ? 2 : 0
        )
        .scaleEffect(item.isSelected ? 1.12 : 1.0)
        .background(collapsedTabFrameReader(for: item.id))
        .help("\(item.title)\nClick to focus this window")
    }

    private func collapsedTabFill(for item: StackOverlayItem) -> LinearGradient {
        if item.isSelected {
            return LinearGradient(
                colors: [
                    item.accent.tint.opacity(1.0),
                    item.accent.tint.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                item.accent.tint.opacity(0.42),
                item.accent.tint.opacity(0.24)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func collapsedTabStroke(for item: StackOverlayItem) -> Color {
        item.isSelected ? Color.white.opacity(0.55) : item.accent.tint.opacity(0.20)
    }

    private func collapsedTabBadge(for item: StackOverlayItem, diameter: CGFloat) -> some View {
        Circle()
            .fill(collapsedTabFill(for: item))
        .overlay(
            Circle()
                .stroke(collapsedTabStroke(for: item), lineWidth: item.isSelected ? 1.25 : 1)
        )
        .frame(width: diameter, height: diameter)
    }

    private var collapsedDotDiameter: CGFloat {
        switch densityMetrics {
        case .compact:
            return 11.5
        case .comfortable:
            return 13.5
        case .expanded:
            return 15.5
        }
    }

    private var collapsedStripMainAxisPadding: CGFloat {
        switch densityMetrics {
        case .compact:
            return 16
        case .comfortable:
            return 19
        case .expanded:
            return 22
        }
    }

    private var collapsedStripCrossAxisPadding: CGFloat {
        switch densityMetrics {
        case .compact:
            return 8
        case .comfortable:
            return 9
        case .expanded:
            return 11
        }
    }

    private var collapsedStripSpacing: CGFloat {
        switch densityMetrics {
        case .compact:
            return 8
        case .comfortable:
            return 9
        case .expanded:
            return 10
        }
    }

    private func collapsedTabFrameReader(for id: UInt) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: StackOverlayCollapsedItemFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named("StackOverlayCollapsedStrip"))]
                )
        }
    }

    private func chromeActionFrameReader(for action: StackOverlayChromeAction) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: StackOverlayChromeActionFramePreferenceKey.self,
                    value: [action: proxy.frame(in: .named("StackOverlayCollapsedStrip"))]
                )
        }
    }

    private func handleCollapsedMarkerTap(at point: CGPoint) {
        if let tappedID = collapsedItemFrames.first(where: { $0.value.contains(point) })?.key {
            onSelect(tappedID)
            return
        }

    }

    private func handleChromeAction(_ action: StackOverlayChromeAction) {
        switch action {
        case .focusStack:
            onFocusStack()
        case .openEditor:
            onOpenEditor()
        case .toggleControls:
            toggleControlsDrawer()
        }
    }

    private func toggleControlsDrawer() {
        let isOpen = !model.controlsPinnedOpen
        withAnimation(.easeOut(duration: 0.14)) {
            model.controlsPinnedOpen = isOpen
        }
        onSetControlsPinnedOpen(isOpen)
    }

    private var windowTabsRail: some View {
        ZStack {
            switcherRailBackground
            HStack(spacing: densityMetrics.railSpacing) {
                ForEach(model.items) { item in
                    horizontalWindowTab(for: item)
                }
            }
            .padding(.horizontal, densityMetrics.railHorizontalInset + widgetMoveGutter)
            .padding(.vertical, densityMetrics.railVerticalInset + widgetMoveGutter)
        }
        .coordinateSpace(name: "StackOverlayRail")
        .contextMenu { controlsContextMenu }
        .overlay(switcherRailBorder)
        .overlay {
            interactionOverlay
        }
        .onPreferenceChange(StackOverlayItemFramePreferenceKey.self) { itemFrames = $0 }
    }

    private var verticalItemsStack: some View {
        ZStack {
            verticalRailBackground
            VStack(alignment: .leading, spacing: densityMetrics.railSpacing) {
                ForEach(model.items) { item in
                    verticalWindowTab(for: item)
                }
            }
            .padding(.horizontal, densityMetrics.railHorizontalInset + widgetMoveGutter)
            .padding(.vertical, densityMetrics.railVerticalInset + widgetMoveGutter)
        }
        .coordinateSpace(name: "StackOverlayRail")
        .contextMenu { controlsContextMenu }
        .overlay(verticalRailBorder)
        .overlay {
            interactionOverlay
        }
        .onPreferenceChange(StackOverlayItemFramePreferenceKey.self) { itemFrames = $0 }
    }

    @ViewBuilder
    private var interactionOverlay: some View {
        if let draggedItem {
            Group {
                if effectiveDisplayMode == .horizontal {
                    horizontalTabBody(for: draggedItem)
                } else {
                    verticalTabBody(for: draggedItem)
                }
            }
            .frame(
                width: dragGhostFrame?.width,
                height: dragGhostFrame?.height
            )
            .scaleEffect(1.03)
            .opacity(1.0)
            .position(dragGhostPosition ?? .zero)
            .shadow(color: draggedItem.accent.tint.opacity(0.18), radius: 12, y: 6)
            .allowsHitTesting(false)
            .zIndex(50)
        }

        if let removalAnimation {
            removalBurstOverlay(removalAnimation)
                .zIndex(60)
        }
    }

    private var configDrawerTransition: AnyTransition {
        let edge: Edge
        if effectiveDisplayMode == .vertical {
            edge = model.horizontalSide == .left ? .trailing : .leading
        } else {
            edge = model.dockPosition == .top ? .bottom : .top
        }
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func horizontalWindowTab(for item: StackOverlayItem) -> some View {
        let isDraggedItem = draggingWindowID == item.id
        let isRemovingItem = removalAnimation?.id == item.id

        return horizontalTabBody(for: item)
            .padding(.top, 5)
            .padding(.trailing, 5)
            .background(frameReader(for: item.id))
            .opacity(isRemovingItem ? 0.02 : (isDraggedItem ? 0.18 : 1.0))
            .offset(horizontalShift(for: item.id))
            .contentShape(Capsule(style: .continuous))
            .onTapGesture {
                onSelect(item.id)
            }
            .onHover { hovering in
                if hovering {
                    hoveredWindowID = item.id
                } else if hoveredWindowID == item.id, hoveredRemoveBadgeID != item.id {
                    hoveredWindowID = nil
                }
            }
            .highPriorityGesture(windowDragGesture(for: item))
            .help("\(item.title)\nClick to focus this window")
            .zIndex(isDraggedItem ? 2 : 0)
    }

    private func verticalWindowTab(for item: StackOverlayItem) -> some View {
        let isDraggedItem = draggingWindowID == item.id
        let isRemovingItem = removalAnimation?.id == item.id

        return verticalTabBody(for: item)
            .padding(.top, 5)
            .padding(.trailing, 5)
            .background(frameReader(for: item.id))
            .opacity(isRemovingItem ? 0.02 : (isDraggedItem ? 0.18 : 1.0))
            .offset(verticalShift(for: item.id))
            .contentShape(Capsule(style: .continuous))
            .onTapGesture {
                onSelect(item.id)
            }
            .onHover { hovering in
                if hovering {
                    hoveredWindowID = item.id
                } else if hoveredWindowID == item.id, hoveredRemoveBadgeID != item.id {
                    hoveredWindowID = nil
                }
            }
            .highPriorityGesture(windowDragGesture(for: item))
            .help("\(item.title)\nClick to focus this window")
            .zIndex(isDraggedItem ? 2 : 0)
    }

    private func verticalWindowBadge(for item: StackOverlayItem) -> some View {
        StackBadgeView(
            token: item.label,
            tint: item.accent.tint,
            selected: item.isSelected,
            diameter: densityMetrics.verticalBadgeDiameter
        )
            .background(
                Circle()
                    .fill(item.isSelected ? Color.clear : Color.white.opacity(0.72))
            )
            .overlay(
                Circle()
                    .stroke(item.isSelected ? item.accent.tint.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: item.isSelected ? item.accent.tint.opacity(0.10) : Color.black.opacity(0.03), radius: item.isSelected ? 5 : 2, y: 1)
            .scaleEffect(item.isSelected ? 1.02 : 1.0)
    }

    private func horizontalTabBody(for item: StackOverlayItem) -> some View {
        HStack(spacing: 6) {
            StackBadgeView(
                token: item.label,
                tint: item.accent.tint,
                selected: item.isSelected,
                diameter: densityMetrics.badgeDiameter
            )

            if effectiveLabelMode == .names {
                Text(item.title)
                    .font(.system(size: densityMetrics.labelFont, weight: item.isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, densityMetrics.horizontalPadding)
        .padding(.vertical, densityMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tabBackground(isSelected: item.isSelected, accent: item.accent, isConfig: false))
        .overlay(tabBorder(isSelected: item.isSelected))
        .shadow(color: item.isSelected ? item.accent.tint.opacity(0.08) : Color.clear, radius: 5, y: 2)
        .scaleEffect(item.isSelected ? 1.01 : 1.0)
    }

    private func verticalTabBody(for item: StackOverlayItem) -> some View {
        Group {
            if effectiveLabelMode == .names {
                HStack(spacing: 6) {
                    verticalWindowBadge(for: item)

                    Text(item.title)
                        .font(.system(size: densityMetrics.labelFont, weight: item.isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, densityMetrics.horizontalPadding)
                .padding(.vertical, densityMetrics.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tabBackground(isSelected: item.isSelected, accent: item.accent, isConfig: false))
                .overlay(tabBorder(isSelected: item.isSelected))
                .shadow(color: item.isSelected ? item.accent.tint.opacity(0.08) : Color.clear, radius: 5, y: 2)
            } else {
                verticalWindowBadge(for: item)
            }
        }
    }

    private var addWindowMenu: some View {
        Menu {
            ForEach(model.addableWindows) { window in
                Button {
                    onAddWindow(window.id)
                } label: {
                    HStack(spacing: 8) {
                        StackBadgeView(token: window.label, tint: Color.accentColor, selected: false, diameter: 16)
                        Text(window.title)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.accentColor.opacity(0.10), radius: 6, y: 3)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Add another window back into this stack")
    }

    @ViewBuilder
    private var controlsContextMenu: some View {
        // "Focus Stack" removed from right-click menu (user request)
        Button(action: onOpenEditor) {
            Label("Open In Stacker", systemImage: "list.bullet.rectangle")
        }
        Divider()
        Menu {
            Button {
                onSetDensityMode(.compact)
            } label: {
                Label("Compat Mode", systemImage: StackOverlayDensityMode.compact.buttonIcon)
            }

            Button {
                onSetDensityMode(.comfortable)
            } label: {
                Label("Comfortable Size", systemImage: StackOverlayDensityMode.comfortable.buttonIcon)
            }

            Button {
                onSetDensityMode(.expanded)
            } label: {
                Label("Full Mode", systemImage: StackOverlayDensityMode.expanded.buttonIcon)
            }
        } label: {
            Label("Widget Size", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Menu {
            ForEach(StackOverlayPlacementPreference.allCases, id: \.rawValue) { preference in
                Button {
                    onSetPlacementPreference(preference)
                } label: {
                    Label(
                        "\(preference == model.placementPreference ? "✓ " : "")\(preference.title)",
                        systemImage: preference.systemImage
                    )
                }
            }
        } label: {
            Label("Widget Side", systemImage: "rectangle.inset.filled.and.person.filled")
        }
        Divider()
        Button(action: onResetPosition) {
            Label("Reset Position", systemImage: "arrow.uturn.backward")
        }
        Button(action: onHideWidget) {
            Label("Hide Window Widget", systemImage: "eye.slash")
        }
        Button(role: .destructive, action: onTurnOff) {
            Label("Turn Off Stack", systemImage: "power")
        }
    }

    private var switcherRailBackground: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: railBackgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: railOverlayColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(Capsule(style: .continuous))
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }

    private var switcherRailBorder: some View {
        Capsule(style: .continuous)
            .stroke(railBorderColor, lineWidth: 1)
            .allowsHitTesting(false)
    }

    private var verticalRailBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: railBackgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: railOverlayColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }

    private var verticalRailBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(railBorderColor, lineWidth: 1)
            .allowsHitTesting(false)
    }

    private func tabBackground(isSelected: Bool, accent: StackPillAccent, isConfig: Bool) -> some View {
        if isConfig && isSelected {
            return AnyView(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.78, blue: 0.28).opacity(0.96),
                                Color(red: 0.07, green: 0.47, blue: 0.10).opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .padding(1)
                    )
            )
        }

        return AnyView(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [accent.tint.opacity(0.18), accent.tint.opacity(0.06)]
                            : isConfig
                                ? [Color(red: 0.33, green: 0.62, blue: 1.0).opacity(0.95), Color(red: 0.58, green: 0.78, blue: 1.0).opacity(0.78)]
                                : neutralTabColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isConfig
                                    ? [Color.white.opacity(0.26), Color.clear]
                                    : [Color.white.opacity(isSelected ? 0.10 : 0.04), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
    }

    private func tabBorder(isSelected: Bool) -> some View {
        if isSelected {
            return AnyView(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
        }

        return AnyView(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var configForegroundStyle: Color {
        .white
    }

    private var configSecondaryForegroundStyle: Color {
        Color.white.opacity(0.84)
    }

    private func overlayGridButton(
        _ systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(role == .destructive ? Color.red.opacity(0.9) : Color.primary.opacity(0.72))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.025), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func overlayActionButton(
        _ title: String,
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(role == .destructive ? .red : .accentColor)
        .help(help)
    }

    private func overlayIconButton(
        _ systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(role == .destructive ? Color.red : Color.secondary)
        .help(help)
    }

    private var isDraggingPill: Bool {
        draggingWindowID != nil
    }

    private var markerTint: Color {
        model.items.first(where: \.isSelected)?.accent.tint ?? Color.accentColor
    }

    private var draggedItem: StackOverlayItem? {
        guard let draggingWindowID else { return nil }
        return model.items.first(where: { $0.id == draggingWindowID })
    }

    private var dragGhostPosition: CGPoint? {
        guard let draggingWindowID,
              let frame = itemFrames[draggingWindowID] else {
            return nil
        }
        return CGPoint(
            x: frame.midX + dragTranslation.width,
            y: frame.midY + dragTranslation.height
        )
    }

    private var dragGhostFrame: CGRect? {
        guard let draggingWindowID else { return nil }
        return itemFrames[draggingWindowID]
    }

    private var previewTargetIndex: Int? {
        guard let draggingWindowID,
              let sourceIndex = model.items.firstIndex(where: { $0.id == draggingWindowID }) else {
            return nil
        }

        let delta = effectiveDisplayMode == .horizontal ? dragTranslation.width : dragTranslation.height
        let step: CGFloat = effectiveDisplayMode == .horizontal
            ? (effectiveLabelMode == .names ? 122 : 52)
            : (effectiveLabelMode == .names ? 50 : 42)
        let rawOffset = Int((delta / step).rounded())
        return max(0, min(model.items.count - 1, sourceIndex + rawOffset))
    }

    private func horizontalShift(for itemID: UInt) -> CGSize {
        guard effectiveDisplayMode == .horizontal,
              let draggingWindowID,
              let sourceIndex = model.items.firstIndex(where: { $0.id == draggingWindowID }),
              let itemIndex = model.items.firstIndex(where: { $0.id == itemID }),
              let targetIndex = previewTargetIndex,
              sourceIndex != targetIndex else {
            return .zero
        }

        let step = effectiveLabelMode == .names ? densityMetrics.horizontalNamedWidth : densityMetrics.horizontalIconWidth
        if sourceIndex < targetIndex, itemIndex > sourceIndex, itemIndex <= targetIndex {
            return CGSize(width: -step, height: 0)
        }
        if targetIndex < sourceIndex, itemIndex >= targetIndex, itemIndex < sourceIndex {
            return CGSize(width: step, height: 0)
        }
        return .zero
    }

    private func verticalShift(for itemID: UInt) -> CGSize {
        guard effectiveDisplayMode == .vertical,
              let draggingWindowID,
              let sourceIndex = model.items.firstIndex(where: { $0.id == draggingWindowID }),
              let itemIndex = model.items.firstIndex(where: { $0.id == itemID }),
              let targetIndex = previewTargetIndex,
              sourceIndex != targetIndex else {
            return .zero
        }

        let step = effectiveLabelMode == .names ? densityMetrics.verticalBadgeDiameter + densityMetrics.verticalPadding * 2 + densityMetrics.railSpacing : densityMetrics.verticalBadgeDiameter + densityMetrics.railSpacing
        if sourceIndex < targetIndex, itemIndex > sourceIndex, itemIndex <= targetIndex {
            return CGSize(width: 0, height: -step)
        }
        if targetIndex < sourceIndex, itemIndex >= targetIndex, itemIndex < sourceIndex {
            return CGSize(width: 0, height: step)
        }
        return .zero
    }

    private func windowDragGesture(for item: StackOverlayItem) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if draggingWindowID == nil {
                    draggingWindowID = item.id
                }
                guard draggingWindowID == item.id else { return }
                dragTranslation = value.translation
            }
            .onEnded { _ in
                guard draggingWindowID == item.id else { return }
                let targetIndex = previewTargetIndex
                let translationWasMeaningful = abs(dragTranslation.width) > 6 || abs(dragTranslation.height) > 6
                draggingWindowID = nil
                dragTranslation = .zero

                guard translationWasMeaningful else { return }
                guard let sourceIndex = model.items.firstIndex(where: { $0.id == item.id }),
                      let targetIndex,
                      sourceIndex != targetIndex,
                      model.items.indices.contains(targetIndex) else {
                    return
                }

                let targetID = model.items[targetIndex].id
                if targetID != item.id {
                    onReorder(item.id, targetID)
                }
            }
    }

    private func frameReader(for id: UInt) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: StackOverlayItemFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named("StackOverlayRail"))]
                )
        }
    }

    @ViewBuilder
    private func removeBadge(for item: StackOverlayItem) -> some View {
        let isVisible =
            (hoveredWindowID == item.id || hoveredRemoveBadgeID == item.id) &&
            draggingWindowID == nil &&
            removalAnimation?.id != item.id

        Button {
            triggerRemovalAnimation(for: item)
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.32, blue: 0.28),
                                    Color(red: 0.86, green: 0.08, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: Color.red.opacity(0.16), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(.top, 1)
        .padding(.trailing, 1)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.72)
        .animation(.easeOut(duration: 0.14), value: isVisible)
        .onHover { hovering in
            if hovering {
                hoveredRemoveBadgeID = item.id
                hoveredWindowID = item.id
            } else if hoveredRemoveBadgeID == item.id {
                hoveredRemoveBadgeID = nil
                if hoveredWindowID == item.id {
                    hoveredWindowID = nil
                }
            }
        }
        .help("Remove this window from the stack")
    }

    @ViewBuilder
    private func removalBurstOverlay(_ removalAnimation: RemovalAnimationState) -> some View {
        ZStack {
            Group {
                if effectiveDisplayMode == .horizontal {
                    horizontalTabBody(for: removalAnimation.item)
                } else {
                    verticalTabBody(for: removalAnimation.item)
                }
            }
            .scaleEffect(1 - 0.18 * removalAnimationProgress)
            .opacity(1 - removalAnimationProgress)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.40, blue: 0.30).opacity(0.28),
                                Color(red: 1.0, green: 0.18, blue: 0.18).opacity(0.04)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .frame(
                        width: 26 + removalAnimationProgress * 42,
                        height: 26 + removalAnimationProgress * 42
                    )
                    .scaleEffect(0.85 + removalAnimationProgress * 0.5)

                removalBurstParticle(angle: -70, distance: 20)
                removalBurstParticle(angle: -18, distance: 26)
                removalBurstParticle(angle: 22, distance: 24)
                removalBurstParticle(angle: 78, distance: 18)

                Image(systemName: "xmark")
                    .font(.system(size: 12 + removalAnimationProgress * 6, weight: .black))
                    .foregroundStyle(.white.opacity(0.96))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.34, blue: 0.28),
                                        Color(red: 0.86, green: 0.08, blue: 0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color.red.opacity(0.16), radius: 10, y: 4)
                    .scaleEffect(0.55 + removalAnimationProgress * 0.8)
            }
            .opacity(0.18 + removalAnimationProgress * 0.82)
        }
        .frame(width: removalAnimation.frame.width, height: removalAnimation.frame.height)
        .position(removalAnimation.position)
        .allowsHitTesting(false)
    }

    private func removalBurstParticle(angle: Double, distance: CGFloat) -> some View {
        let radians = angle * .pi / 180
        let offsetScale = max(removalAnimationProgress, 0.001)

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.64, blue: 0.24),
                        Color(red: 1.0, green: 0.22, blue: 0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 4, height: 10)
            .rotationEffect(.degrees(angle + 90))
            .offset(
                x: cos(radians) * distance * offsetScale,
                y: sin(radians) * distance * offsetScale
            )
            .opacity(max(0, 1 - removalAnimationProgress * 0.92))
            .blur(radius: removalAnimationProgress * 0.8)
    }

    private func triggerRemovalAnimation(for item: StackOverlayItem, position: CGPoint? = nil) {
        guard removalAnimation == nil else {
            onRemove(item.id)
            return
        }

        let frame = itemFrames[item.id] ?? CGRect(x: 0, y: 0, width: 36, height: 36)
        let anchorPosition = position ?? CGPoint(x: frame.midX, y: frame.midY)
        removalAnimation = RemovalAnimationState(item: item, frame: frame, position: anchorPosition)
        removalAnimationProgress = 0

        withAnimation(.easeOut(duration: 0.24)) {
            removalAnimationProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onRemove(item.id)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            if removalAnimation?.id == item.id {
                removalAnimation = nil
                removalAnimationProgress = 0
            }
        }
    }

    private var effectiveDisplayMode: StackOverlayDisplayMode {
        guard model.displayMode == .horizontal,
              let maxWidth = model.maxPrimaryWindowWidth else {
            return model.displayMode
        }

        let namedWidth = CGFloat(model.items.count) * densityMetrics.horizontalNamedWidth + CGFloat(model.addableWindows.isEmpty ? 0 : 42) + densityMetrics.railHorizontalInset * 2
        let iconWidth = CGFloat(model.items.count) * densityMetrics.horizontalIconWidth + CGFloat(model.addableWindows.isEmpty ? 0 : 42) + densityMetrics.railHorizontalInset * 2

        if namedWidth > maxWidth && iconWidth > maxWidth {
            return .vertical
        }

        return .horizontal
    }

    private var effectiveLabelMode: StackOverlayLabelMode {
        .icons
    }
}

private struct StackOverlayControlsDrawerView: View {
    let onToggleDisplayMode: () -> Void
    let onToggleLabelMode: () -> Void
    let onSetDensityMode: (StackOverlayDensityMode) -> Void
    let onHideWidget: () -> Void
    let onOpenEditor: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            drawerButton("rectangle.grid.1x2", help: "Switch between horizontal and vertical", action: onToggleDisplayMode)
            drawerButton("textformat", help: "Switch between names and icons", action: onToggleLabelMode)
            drawerButton("rectangle.compress.vertical", help: "Compat mode", action: { onSetDensityMode(.compact) })
            drawerButton("capsule.lefthalf.filled", help: "Comfortable size", action: { onSetDensityMode(.comfortable) })
            drawerButton("rectangle.expand.vertical", help: "Full mode", action: { onSetDensityMode(.expanded) })
            drawerButton("eye.slash", help: "Hide the browser window widget", action: onHideWidget)
            drawerButton("list.bullet.rectangle", help: "Open this stack in Stacker", action: onOpenEditor)
            drawerButton("power", help: "Break this stack apart", role: .destructive, action: onTurnOff)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(
            drawerTabChrome
        )
        .fixedSize()
    }

    private var drawerTabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 5,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 12,
            topTrailingRadius: 5,
            style: .continuous
        )
    }

    private var drawerTabChrome: some View {
        drawerTabShape
            .fill(.regularMaterial)
            .overlay {
                drawerTabShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.56),
                                Color(red: 0.95, green: 0.97, blue: 0.99).opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                drawerTabShape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                drawerTabShape
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }

    private func drawerButton(
        _ systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(role == .destructive ? Color.red.opacity(0.9) : Color.primary.opacity(0.72))
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.025), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

final class StackOverlayPanelController {
    private enum PerimeterCornerSnap {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    private let panel: NSPanel
    private let containerView: TransparentContainerView
    private let hostingView: TransparentHostingView<StackOverlayStripView>
    private let controlsPanel: NSPanel
    private let controlsContainerView: TransparentContainerView
    private let controlsHostingView: TransparentHostingView<StackOverlayControlsDrawerView>
    private let viewModel: StackOverlayViewModel
    private let appPID: pid_t
    private let appBundleIdentifier: String?
    private var trackingTimer: Timer?
    private let attachmentEngine = WindowAttachmentEngine()
    private var attachmentStateProvider: (() -> StackOverlayAttachmentState)?
    private var selectedItemProvider: (() -> UInt?)?
    private var items: [StackOverlayItem] = []
    private var addableWindows: [StackOverlayAddableWindow] = []
    private let appName: String
    private let onSelect: (UInt) -> Void
    private let onDisplayModeChanged: (StackOverlayDisplayMode) -> Void
    private let onLabelModeChanged: (StackOverlayLabelMode) -> Void
    private let onDensityModeChanged: (StackOverlayDensityMode) -> Void
    private let onPlacementPreferenceChanged: (StackOverlayPlacementPreference) -> Void
    private let onDockPositionChanged: (StackOverlayDockPosition) -> Void
    private let onAddWindow: (UInt) -> Void
    private let onOpenEditor: () -> Void
    private let onHideWidget: () -> Void
    private let onResetPositionRequested: () -> Void
    private let onFocusStack: () -> Void
    private let onTurnOff: () -> Void
    private let onMove: (UInt, Int) -> Void
    private let onReorder: (UInt, UInt) -> Void
    private let onRemove: (UInt) -> Void
    private var moveObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var panelScreenObserver: NSObjectProtocol?
    private var panelBackingObserver: NSObjectProtocol?
    private var controlsPanelScreenObserver: NSObjectProtocol?
    private var controlsPanelBackingObserver: NSObjectProtocol?
    private var isUpdatingPosition = false
    private var isDraggingBackground = false
    private var horizontalAnchorOffset: CGFloat = 0
    private var verticalAnchorOffset: CGFloat = 0
    private var isShowingConfig = false
    private var controlsPinnedOpen = false
    private var appearance = StackOverlayAppearancePreference.current()
    private var displayMode: StackOverlayDisplayMode
    private var labelMode: StackOverlayLabelMode
    private var densityMode: StackOverlayDensityMode
    private var placementPreference: StackOverlayPlacementPreference
    private var preferredDockPosition: StackOverlayDockPosition
    private var dockPosition: StackOverlayDockPosition
    private var horizontalSide: StackOverlayHorizontalSide = .left
    private var dragStartOrigin: CGPoint?
    private var previousBackgroundDragDelta: CGSize = .zero
    private var lastAnchorFrame: CGRect?
    private var movementFadeWorkItem: DispatchWorkItem?
    private(set) var currentHealth: StackOverlayHealth = .visible
    var onHealthChanged: ((StackOverlayHealth) -> Void)?
    private let controlsPanelGap: CGFloat = 4
    private let edgeInset: CGFloat = 18
    private let sideGap: CGFloat = 0
    private let topGap: CGFloat = 0
    private let bottomGap: CGFloat = 0

    init(
        appPID: pid_t,
        appBundleIdentifier: String?,
        appName: String,
        displayMode: StackOverlayDisplayMode,
        labelMode: StackOverlayLabelMode,
        densityMode: StackOverlayDensityMode,
        placementPreference: StackOverlayPlacementPreference,
        dockPosition: StackOverlayDockPosition,
        onSelect: @escaping (UInt) -> Void,
        onDisplayModeChanged: @escaping (StackOverlayDisplayMode) -> Void,
        onLabelModeChanged: @escaping (StackOverlayLabelMode) -> Void,
        onDensityModeChanged: @escaping (StackOverlayDensityMode) -> Void,
        onPlacementPreferenceChanged: @escaping (StackOverlayPlacementPreference) -> Void,
        onDockPositionChanged: @escaping (StackOverlayDockPosition) -> Void,
        onAddWindow: @escaping (UInt) -> Void,
        onOpenEditor: @escaping () -> Void,
        onHideWidget: @escaping () -> Void,
        onResetPositionRequested: @escaping () -> Void,
        onFocusStack: @escaping () -> Void,
        onTurnOff: @escaping () -> Void,
        onMove: @escaping (UInt, Int) -> Void,
        onReorder: @escaping (UInt, UInt) -> Void,
        onRemove: @escaping (UInt) -> Void
    ) {
        self.appPID = appPID
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.displayMode = displayMode
        self.labelMode = labelMode
        self.densityMode = densityMode
        self.placementPreference = placementPreference
        self.preferredDockPosition = dockPosition
        self.dockPosition = dockPosition
        self.horizontalAnchorOffset = OverlayAttachmentPreference.currentHorizontalOffset(
            bundleIdentifier: appBundleIdentifier,
            appName: appName
        )
        self.verticalAnchorOffset = OverlayAttachmentPreference.currentVerticalOffset(
            bundleIdentifier: appBundleIdentifier,
            appName: appName
        )
        self.onSelect = onSelect
        self.onDisplayModeChanged = onDisplayModeChanged
        self.onLabelModeChanged = onLabelModeChanged
        self.onDensityModeChanged = onDensityModeChanged
        self.onPlacementPreferenceChanged = onPlacementPreferenceChanged
        self.onDockPositionChanged = onDockPositionChanged
        self.onAddWindow = onAddWindow
        self.onOpenEditor = onOpenEditor
        self.onHideWidget = onHideWidget
        self.onResetPositionRequested = onResetPositionRequested
        self.onFocusStack = onFocusStack
        self.onTurnOff = onTurnOff
        self.onMove = onMove
        self.onReorder = onReorder
        self.onRemove = onRemove
        viewModel = StackOverlayViewModel(
            appearance: appearance,
            displayMode: displayMode,
            labelMode: labelMode,
            densityMode: densityMode,
            placementPreference: placementPreference,
            dockPosition: dockPosition
        )
        hostingView = TransparentHostingView(
            rootView: StackOverlayStripView(
                appName: appName,
                stackPID: Int32(appPID),
                model: viewModel,
                onSelect: onSelect,
                onToggleConfig: {},
                onToggleDisplayMode: {},
                onToggleLabelMode: {},
                onSetDensityMode: { _ in },
                onBackgroundDragChanged: { _ in },
                onBackgroundDragEnded: {},
                onSetControlsPinnedOpen: { _ in },
                onSetAppearance: { _ in },
                onSetPlacementPreference: { _ in },
                onSetDockPosition: { _ in },
                onAddWindow: { _ in },
                onOpenEditor: {},
                onHideWidget: {},
                onResetPosition: {},
                onFocusStack: onFocusStack,
                onTurnOff: onTurnOff,
                onMove: onMove,
                onReorder: onReorder,
                onRemove: onRemove
            )
        )
        controlsHostingView = TransparentHostingView(
            rootView: StackOverlayControlsDrawerView(
                onToggleDisplayMode: {},
                onToggleLabelMode: {},
                onSetDensityMode: { _ in },
                onHideWidget: {},
                onOpenEditor: {},
                onTurnOff: {}
            )
        )
        panel = WidgetOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlayPanel(panel)
        containerView = TransparentContainerView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        containerView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        panel.contentView = containerView
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.isOpaque = false
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onSecondaryClick = nil

        controlsPanel = WidgetOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlayPanel(controlsPanel)
        controlsContainerView = TransparentContainerView(frame: NSRect(x: 0, y: 0, width: 120, height: 34))
        controlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        controlsHostingView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainerView.addSubview(controlsHostingView)
        NSLayoutConstraint.activate([
            controlsHostingView.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor),
            controlsHostingView.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor),
            controlsHostingView.topAnchor.constraint(equalTo: controlsContainerView.topAnchor),
            controlsHostingView.bottomAnchor.constraint(equalTo: controlsContainerView.bottomAnchor)
        ])
        controlsPanel.contentView = controlsContainerView
        controlsHostingView.wantsLayer = true
        controlsHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        controlsPanel.contentView?.wantsLayer = true
        controlsPanel.contentView?.layer?.isOpaque = false
        controlsPanel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        controlsPanel.contentView?.superview?.wantsLayer = true
        controlsPanel.contentView?.superview?.layer?.isOpaque = false
        controlsPanel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        controlsHostingView.onSecondaryClick = nil

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDraggingBackground else { return }
            self.captureUserAnchorOffset()
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: .stackerFrontmostApplicationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pidValue = notification.userInfo?["pid"]
            let pid: Int32?
            if let int32Value = pidValue as? Int32 {
                pid = int32Value
            } else if let intValue = pidValue as? Int {
                pid = Int32(intValue)
            } else if let numberValue = pidValue as? NSNumber {
                pid = Int32(truncating: numberValue)
            } else {
                pid = nil
            }
            let bundleIdentifier = notification.userInfo?["bundleIdentifier"] as? String
            self?.handleFrontmostApplicationChange(pid: pid, bundleIdentifier: bundleIdentifier)
        }

        visibilityObserver = NotificationCenter.default.addObserver(
            forName: .stackerOverlayVisibilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncVisibility()
        }

        installDisplayChangeObservers()

        installRootView()
    }

    func startTracking(_ attachmentStateProvider: @escaping () -> StackOverlayAttachmentState, selectedItemProvider: @escaping () -> UInt?) {
        self.attachmentStateProvider = attachmentStateProvider
        self.selectedItemProvider = selectedItemProvider
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.syncSelectedItem()
            self?.syncVisibility()
        }
        if let trackingTimer {
            RunLoop.main.add(trackingTimer, forMode: .common)
        }
        syncVisibility()
    }

    func update(
        items: [StackOverlayItem],
        displayMode: StackOverlayDisplayMode? = nil,
        labelMode: StackOverlayLabelMode? = nil,
        densityMode: StackOverlayDensityMode? = nil,
        appearance: StackOverlayAppearance? = nil,
        placementPreference: StackOverlayPlacementPreference? = nil,
        dockPosition: StackOverlayDockPosition? = nil
    ) {
        self.items = items
        if let appearance {
            self.appearance = appearance
        }
        if let displayMode {
            self.displayMode = displayMode
        }
        if let labelMode {
            self.labelMode = labelMode
        }
        if let densityMode {
            self.densityMode = densityMode
        }
        if let placementPreference {
            self.placementPreference = placementPreference
        }
        if let dockPosition {
            self.preferredDockPosition = dockPosition
            self.dockPosition = dockPosition
        }
        updateRootView()
        refreshPanelLayout()
    }

    func update(
        items: [StackOverlayItem],
        addableWindows: [StackOverlayAddableWindow],
        appearance: StackOverlayAppearance? = nil,
        displayMode: StackOverlayDisplayMode? = nil,
        labelMode: StackOverlayLabelMode? = nil,
        densityMode: StackOverlayDensityMode? = nil,
        placementPreference: StackOverlayPlacementPreference? = nil,
        dockPosition: StackOverlayDockPosition? = nil
    ) {
        self.items = items
        self.addableWindows = addableWindows
        if let appearance {
            self.appearance = appearance
        }
        if let displayMode {
            self.displayMode = displayMode
        }
        if let labelMode {
            self.labelMode = labelMode
        }
        if let densityMode {
            self.densityMode = densityMode
        }
        if let placementPreference {
            self.placementPreference = placementPreference
        }
        if let dockPosition {
            self.preferredDockPosition = dockPosition
            self.dockPosition = dockPosition
        }
        updateRootView()
        refreshPanelLayout()
    }

    func close() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        movementFadeWorkItem?.cancel()
        movementFadeWorkItem = nil
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let panelScreenObserver {
            NotificationCenter.default.removeObserver(panelScreenObserver)
        }
        if let panelBackingObserver {
            NotificationCenter.default.removeObserver(panelBackingObserver)
        }
        if let controlsPanelScreenObserver {
            NotificationCenter.default.removeObserver(controlsPanelScreenObserver)
        }
        if let controlsPanelBackingObserver {
            NotificationCenter.default.removeObserver(controlsPanelBackingObserver)
        }
        controlsPanel.orderOut(nil)
        controlsPanel.close()
        panel.orderOut(nil)
        panel.close()
    }

    func setCurrentAppearance(_ appearance: StackOverlayAppearance) {
        self.appearance = appearance
        viewModel.appearance = appearance
        updateRootView()
        refreshPanelLayout()
    }

    func selectWindow(_ id: UInt) {
        items = items.map {
            StackOverlayItem(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                label: $0.label,
                accent: $0.accent,
                isSelected: $0.id == id
            )
        }
        updateRootView()
        syncVisibility()
    }

    private func updateRootView() {
        viewModel.items = items
        viewModel.addableWindows = addableWindows
        viewModel.controlsPinnedOpen = controlsPinnedOpen
        viewModel.appearance = appearance
        viewModel.isShowingConfig = isShowingConfig
        viewModel.displayMode = displayMode
        viewModel.labelMode = labelMode
        viewModel.densityMode = densityMode
        viewModel.placementPreference = placementPreference
        viewModel.dockPosition = dockPosition
        viewModel.horizontalSide = horizontalSide
        viewModel.overlayHealth = currentHealth
        if let anchorFrame = currentAnchorFrameForLayout() {
            viewModel.maxPrimaryWindowWidth = max(anchorFrame.width - 24, 120)
        } else {
            viewModel.maxPrimaryWindowWidth = nil
        }
        hostingView.onSecondaryClick = nil
        controlsHostingView.rootView = StackOverlayControlsDrawerView(
            onToggleDisplayMode: { [weak self] in
                self?.toggleDisplayMode()
            },
            onToggleLabelMode: { [weak self] in
                self?.toggleLabelMode()
            },
            onSetDensityMode: { [weak self] mode in
                self?.setDensityMode(mode)
            },
            onHideWidget: { [weak self] in
                self?.onHideWidget()
            },
            onOpenEditor: { [weak self] in
                self?.onOpenEditor()
            },
            onTurnOff: { [weak self] in
                self?.onTurnOff()
            }
        )
        controlsHostingView.onSecondaryClick = nil
    }

    private func installRootView() {
        hostingView.rootView = StackOverlayStripView(
            appName: appName,
            stackPID: Int32(appPID),
            model: viewModel,
            onSelect: onSelect,
            onToggleConfig: { [weak self] in
                self?.toggleConfigIfAllowed()
            },
            onToggleDisplayMode: { [weak self] in
                self?.toggleDisplayMode()
            },
            onToggleLabelMode: { [weak self] in
                self?.toggleLabelMode()
            },
            onSetDensityMode: { [weak self] mode in
                self?.setDensityMode(mode)
            },
            onBackgroundDragChanged: { [weak self] delta in
                self?.handleBackgroundDrag(delta)
            },
            onBackgroundDragEnded: { [weak self] in
                self?.handleBackgroundDragEnded()
            },
            onSetControlsPinnedOpen: { [weak self] isOpen in
                self?.setControlsPinnedOpen(isOpen)
            },
            onSetAppearance: { [weak self] appearance in
                self?.setAppearance(appearance)
            },
            onSetPlacementPreference: { [weak self] preference in
                self?.setPlacementPreference(preference)
            },
            onSetDockPosition: { [weak self] dockPosition in
                self?.setDockPosition(dockPosition)
            },
            onAddWindow: { [weak self] id in
                self?.onAddWindow(id)
            },
            onOpenEditor: { [weak self] in
                self?.onOpenEditor()
            },
            onHideWidget: { [weak self] in
                self?.onHideWidget()
            },
            onResetPosition: { [weak self] in
                self?.resetHorizontalPosition()
            },
            onFocusStack: onFocusStack,
            onTurnOff: onTurnOff,
            onMove: onMove,
            onReorder: onReorder,
            onRemove: onRemove
        )
        hostingView.onSecondaryClick = nil
    }

    private func toggleConfigIfAllowed() {
        withAnimation(.easeOut(duration: 0.18)) {
            isShowingConfig.toggle()
        }
        updateRootView()
        refreshPanelLayout()
    }

    private func toggleDisplayMode() {
        withAnimation(.easeOut(duration: 0.16)) {
            displayMode.toggle()
        }
        onDisplayModeChanged(displayMode)
        updateRootView()
        refreshPanelLayout()
    }

    private func toggleLabelMode() {
        withAnimation(.easeOut(duration: 0.16)) {
            labelMode.toggle()
        }
        onLabelModeChanged(labelMode)
        updateRootView()
        refreshPanelLayout()
    }

    private func setDensityMode(_ mode: StackOverlayDensityMode) {
        densityMode = mode
        onDensityModeChanged(mode)
        updateRootView()
        refreshPanelLayout()
    }

    private func toggleDockPosition() {
        preferredDockPosition.toggle()
        placementPreference = StackOverlayPlacementPreference(dockPosition: preferredDockPosition)
        onPlacementPreferenceChanged(placementPreference)
        onDockPositionChanged(preferredDockPosition)
        dockPosition = preferredDockPosition
        updateRootView()
        refreshPanelLayout()
    }

    private func setPlacementPreference(_ preference: StackOverlayPlacementPreference) {
        guard placementPreference != preference else { return }
        placementPreference = preference
        if let dockPosition = preference.dockPosition {
            preferredDockPosition = dockPosition
            self.dockPosition = dockPosition
        }
        StackOverlayPlacementPreferenceStore.set(preference)
        onPlacementPreferenceChanged(preference)
        updateRootView()
        refreshPanelLayout()
    }

    private func setDockPosition(_ position: StackOverlayDockPosition) {
        guard preferredDockPosition != position || dockPosition != position else { return }
        placementPreference = StackOverlayPlacementPreference(dockPosition: position)
        preferredDockPosition = position
        dockPosition = position
        StackOverlayPlacementPreferenceStore.set(placementPreference)
        onPlacementPreferenceChanged(placementPreference)
        onDockPositionChanged(position)
        updateRootView()
        refreshPanelLayout()
    }

    private func setControlsPinnedOpen(_ isOpen: Bool) {
        controlsPinnedOpen = isOpen
        viewModel.controlsPinnedOpen = isOpen
        updateRootView()
        refreshPanelLayout()
    }

    private func setAppearance(_ appearance: StackOverlayAppearance) {
        self.appearance = appearance
        StackOverlayAppearancePreference.set(appearance)
        viewModel.appearance = appearance
        updateRootView()
        refreshPanelLayout()
    }

    private func refreshPanelLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizePanelsToFitContent()
            self.invalidatePanelRendering()
            self.syncVisibility()
        }
    }

    private func handleBackgroundDrag(_ delta: CGSize) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            previousBackgroundDragDelta = .zero
            isDraggingBackground = true
        }

        guard let anchorFrame = resolveCurrentAttachment().anchorFrame else {
            return
        }
        let incrementalDelta = CGSize(
            width: delta.width - previousBackgroundDragDelta.width,
            height: delta.height - previousBackgroundDragDelta.height
        )
        previousBackgroundDragDelta = delta
        let dragResult = perimeterDragResult(
            from: panel.frame.origin,
            delta: incrementalDelta,
            anchorFrame: anchorFrame
        )
        var resolvedOrigin = dragResult.origin

        if dockPosition != dragResult.dockPosition {
            dockPosition = dragResult.dockPosition
            preferredDockPosition = dragResult.dockPosition
            placementPreference = StackOverlayPlacementPreference(dockPosition: dragResult.dockPosition)
            onPlacementPreferenceChanged(placementPreference)
            onDockPositionChanged(dragResult.dockPosition)
            updateRootView()
            resizePanelsToFitContent()
            if let cornerSnap = dragResult.cornerSnap {
                resolvedOrigin = snappedCornerOrigin(
                    for: dragResult.dockPosition,
                    cornerSnap: cornerSnap,
                    anchorFrame: anchorFrame,
                    panelSize: panel.frame.size
                )
            }
        }

        let nextHorizontalSide: StackOverlayHorizontalSide = resolvedOrigin.x + panel.frame.width / 2 < anchorFrame.midX ? .left : .right
        if nextHorizontalSide != horizontalSide {
            horizontalSide = nextHorizontalSide
            updateRootView()
        }

        let nextOrigin = clampedOrigin(
            proposedOrigin: resolvedOrigin,
            preferredScreen: referenceScreen(for: anchorFrame)
        )

        isUpdatingPosition = true
        panel.setFrameOrigin(nextOrigin)
        isUpdatingPosition = false
    }

    private func perimeterDragResult(
        from currentOrigin: CGPoint,
        delta: CGSize,
        anchorFrame: CGRect
    ) -> (dockPosition: StackOverlayDockPosition, origin: CGPoint, cornerSnap: PerimeterCornerSnap?) {
        let rawOrigin = CGPoint(
            x: currentOrigin.x + delta.width,
            y: currentOrigin.y + delta.height
        )
        let bounds = perimeterBounds(anchorFrame: anchorFrame, panelSize: panel.frame.size)

        // For tall (full-height) windows, prevent perimeter drag from transitioning
        // from top/bottom onto the left/right rails. The vertical travel is too small
        // and the transition looks broken (widget slides over the window then snaps).
        let sideRailViable = (bounds.maxY - bounds.minY) >= panel.frame.height * 1.5

        switch dockPosition {
        case .top:
            if rawOrigin.x < bounds.minX && sideRailViable {
                return (.left, snappedCornerOrigin(for: .left, cornerSnap: .topLeading, anchorFrame: anchorFrame, panelSize: panel.frame.size), .topLeading)
            }
            if rawOrigin.x > bounds.maxX && sideRailViable {
                return (.right, snappedCornerOrigin(for: .right, cornerSnap: .topTrailing, anchorFrame: anchorFrame, panelSize: panel.frame.size), .topTrailing)
            }
            return (.top, CGPoint(x: min(max(rawOrigin.x, bounds.minX), bounds.maxX), y: anchorFrame.maxY + topGap), nil)
        case .bottom:
            if rawOrigin.x < bounds.minX && sideRailViable {
                return (.left, snappedCornerOrigin(for: .left, cornerSnap: .bottomLeading, anchorFrame: anchorFrame, panelSize: panel.frame.size), .bottomLeading)
            }
            if rawOrigin.x > bounds.maxX && sideRailViable {
                return (.right, snappedCornerOrigin(for: .right, cornerSnap: .bottomTrailing, anchorFrame: anchorFrame, panelSize: panel.frame.size), .bottomTrailing)
            }
            return (.bottom, CGPoint(x: min(max(rawOrigin.x, bounds.minX), bounds.maxX), y: anchorFrame.minY - panel.frame.height - bottomGap), nil)
        case .left:
            // If we're on a side rail but vertical travel is tiny (tall window), force migration to top/bottom on any drag.
            if !sideRailViable || rawOrigin.y > bounds.maxY {
                return (.top, snappedCornerOrigin(for: .top, cornerSnap: .topLeading, anchorFrame: anchorFrame, panelSize: panel.frame.size), .topLeading)
            }
            if rawOrigin.y < bounds.minY {
                return (.bottom, snappedCornerOrigin(for: .bottom, cornerSnap: .bottomLeading, anchorFrame: anchorFrame, panelSize: panel.frame.size), .bottomLeading)
            }
            return (.left, CGPoint(x: anchorFrame.minX - panel.frame.width - sideGap, y: min(max(rawOrigin.y, bounds.minY), bounds.maxY)), nil)
        case .right:
            if !sideRailViable || rawOrigin.y > bounds.maxY {
                return (.top, snappedCornerOrigin(for: .top, cornerSnap: .topTrailing, anchorFrame: anchorFrame, panelSize: panel.frame.size), .topTrailing)
            }
            if rawOrigin.y < bounds.minY {
                return (.bottom, snappedCornerOrigin(for: .bottom, cornerSnap: .bottomTrailing, anchorFrame: anchorFrame, panelSize: panel.frame.size), .bottomTrailing)
            }
            return (.right, CGPoint(x: anchorFrame.maxX + sideGap, y: min(max(rawOrigin.y, bounds.minY), bounds.maxY)), nil)
        }
    }

    private func perimeterBounds(anchorFrame: CGRect, panelSize: CGSize) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let minX = anchorFrame.minX + edgeInset
        let maxX = max(minX, anchorFrame.maxX - panelSize.width - edgeInset)
        let minY = anchorFrame.minY + edgeInset
        let maxY = max(minY, anchorFrame.maxY - panelSize.height - edgeInset)
        return (minX, maxX, minY, maxY)
    }

    private func snappedCornerOrigin(
        for dockPosition: StackOverlayDockPosition,
        cornerSnap: PerimeterCornerSnap,
        anchorFrame: CGRect,
        panelSize: CGSize
    ) -> CGPoint {
        let bounds = perimeterBounds(anchorFrame: anchorFrame, panelSize: panelSize)

        switch (dockPosition, cornerSnap) {
        case (.top, .topLeading):
            return CGPoint(x: bounds.minX, y: anchorFrame.maxY + topGap)
        case (.top, .topTrailing):
            return CGPoint(x: bounds.maxX, y: anchorFrame.maxY + topGap)
        case (.bottom, .bottomLeading):
            return CGPoint(x: bounds.minX, y: anchorFrame.minY - panelSize.height - bottomGap)
        case (.bottom, .bottomTrailing):
            return CGPoint(x: bounds.maxX, y: anchorFrame.minY - panelSize.height - bottomGap)
        case (.left, .topLeading):
            return CGPoint(x: anchorFrame.minX - panelSize.width - sideGap, y: bounds.maxY)
        case (.left, .bottomLeading):
            return CGPoint(x: anchorFrame.minX - panelSize.width - sideGap, y: bounds.minY)
        case (.right, .topTrailing):
            return CGPoint(x: anchorFrame.maxX + sideGap, y: bounds.maxY)
        case (.right, .bottomTrailing):
            return CGPoint(x: anchorFrame.maxX + sideGap, y: bounds.minY)
        default:
            return proposedOrigin(for: anchorFrame, dockPosition: dockPosition)
        }
    }

    private func handleBackgroundDragEnded() {
        dragStartOrigin = nil
        previousBackgroundDragDelta = .zero
        isDraggingBackground = false
        captureUserAnchorOffset()
        syncVisibility()
    }

    private func handleBackgroundDrop(_ payload: String) -> Bool {
        let components = payload.split(separator: ":")
        guard components.count == 2,
              let sourcePID = Int32(components[0]),
              let windowID = UInt(components[1]),
              sourcePID == appPID else {
            return false
        }

        onRemove(windowID)
        return true
    }

    private func syncSelectedItem() {
        guard let selectedID = selectedItemProvider?(),
              items.contains(where: { $0.id == selectedID }),
              !items.contains(where: { $0.id == selectedID && $0.isSelected }) else {
            return
        }
        selectWindow(selectedID)
    }

    private func syncVisibility() {
        guard !items.isEmpty else {
            updateHealth(.missingAnchor)
            controlsPanel.orderOut(nil)
            panel.orderOut(nil)
            return
        }

        guard !isUserOverlayHidden else {
            updateHealth(.hidden)
            controlsPanel.orderOut(nil)
            panel.orderOut(nil)
            return
        }

        guard isTargetContextFrontmost else {
            updateHealth(.visible)
            controlsPanel.orderOut(nil)
            panel.orderOut(nil)
            return
        }

        let state = attachmentStateProvider?() ?? .missingAnchor
        preparePanelLayout(for: state)

        let resolvedAttachment = resolveAttachment(for: state)
        updateHealth(resolvedAttachment.health)

        guard let origin = resolvedAttachment.origin,
              resolvedAttachment.health == .visible || resolvedAttachment.health == .clamped else {
            controlsPanel.orderOut(nil)
            panel.orderOut(nil)
            return
        }

        if isDraggingBackground {
            syncControlsPanelVisibility()
            panel.orderFrontRegardless()
            return
        }

        applyResolvedAttachment(resolvedAttachment, origin: origin)
        syncControlsPanelVisibility()
        panel.orderFrontRegardless()
    }

    private func resolveCurrentAttachment() -> StackOverlayResolvedAttachment {
        let state = attachmentStateProvider?() ?? .missingAnchor
        preparePanelLayout(for: state)
        return resolveAttachment(for: state)
    }

    private func resolveAttachment(for state: StackOverlayAttachmentState) -> StackOverlayResolvedAttachment {
        return attachmentEngine.resolve(
            state: state,
            panelSize: panel.frame.size,
            panelFrame: panel.frame,
            placementPreference: placementPreference,
            preferredDockPosition: preferredDockPosition,
            horizontalOffset: horizontalAnchorOffset,
            verticalOffset: verticalAnchorOffset
        )
    }

    private func preparePanelLayout(for state: StackOverlayAttachmentState) {
        guard state.health == .visible || state.health == .clamped,
              let rawAnchorFrame = state.anchorFrame else {
            if viewModel.maxPrimaryWindowWidth != nil {
                viewModel.maxPrimaryWindowWidth = nil
                resizePanelsToFitContent()
                invalidatePanelRendering()
            }
            return
        }

        let anchorFrame = attachmentEngine.convertAXFrameToScreenCoordinates(rawAnchorFrame)
        let nextMaxPrimaryWindowWidth = max(anchorFrame.width - 24, 120)
        guard viewModel.maxPrimaryWindowWidth.map({ abs($0 - nextMaxPrimaryWindowWidth) > 0.5 }) ?? true else {
            return
        }

        viewModel.maxPrimaryWindowWidth = nextMaxPrimaryWindowWidth
        resizePanelsToFitContent()
        invalidatePanelRendering()
    }

    private func applyResolvedAttachment(_ attachment: StackOverlayResolvedAttachment, origin: CGPoint) {
        if let anchorFrame = attachment.anchorFrame {
            updateAnchorMotion(anchorFrame)
            lastAnchorFrame = anchorFrame
        }

        if dockPosition != attachment.dockPosition {
            dockPosition = attachment.dockPosition
            updateRootView()
        }

        if horizontalSide != attachment.horizontalSide {
            horizontalSide = attachment.horizontalSide
            updateRootView()
        }

        isUpdatingPosition = true
        panel.setFrameOrigin(origin)
        isUpdatingPosition = false
    }

    private func updateHealth(_ health: StackOverlayHealth) {
        guard currentHealth != health else {
            viewModel.overlayHealth = health
            return
        }

        currentHealth = health
        viewModel.overlayHealth = health
        onHealthChanged?(health)
        updateRootView()
    }

    private func updateAnchorMotion(_ anchorFrame: CGRect) {
        defer { lastAnchorFrame = anchorFrame }

        guard let lastAnchorFrame else { return }
        guard abs(lastAnchorFrame.origin.x - anchorFrame.origin.x) > 0.5 ||
              abs(lastAnchorFrame.origin.y - anchorFrame.origin.y) > 0.5 ||
              abs(lastAnchorFrame.width - anchorFrame.width) > 0.5 ||
              abs(lastAnchorFrame.height - anchorFrame.height) > 0.5 else {
            return
        }

        movementFadeWorkItem?.cancel()
        viewModel.isWindowChanging = true

        let workItem = DispatchWorkItem { [weak viewModel] in
            viewModel?.isWindowChanging = false
        }
        movementFadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
    }

    private func currentAnchorFrameForLayout() -> CGRect? {
        if let lastAnchorFrame {
            return lastAnchorFrame
        }

        guard let state = attachmentStateProvider?(),
              let anchorFrame = state.anchorFrame else {
            return nil
        }
        return attachmentEngine.convertAXFrameToScreenCoordinates(anchorFrame)
    }

    private func resizePanelsToFitContent() {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let currentFrame = panel.frame
        let currentContentSize = panel.contentRect(forFrameRect: currentFrame).size
        if currentContentSize != fittingSize {
            let newFrameTemplate = panel.frameRect(forContentRect: CGRect(origin: .zero, size: fittingSize))
            var nextOrigin = currentFrame.origin

            if dockPosition == .right {
                nextOrigin.x = currentFrame.maxX - newFrameTemplate.width
            }

            if dockPosition == .bottom {
                nextOrigin.y = currentFrame.maxY - newFrameTemplate.height
            }

            isUpdatingPosition = true
            panel.setFrame(CGRect(origin: nextOrigin, size: newFrameTemplate.size), display: true)
            isUpdatingPosition = false
        }

        controlsHostingView.invalidateIntrinsicContentSize()
        controlsHostingView.layoutSubtreeIfNeeded()
        let controlsFittingSize = controlsHostingView.fittingSize
        if controlsPanel.contentRect(forFrameRect: controlsPanel.frame).size != controlsFittingSize {
            controlsPanel.setContentSize(controlsFittingSize)
        }
    }

    private func installDisplayChangeObservers() {
        let notificationCenter = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in
            self?.handleDisplayMetricsChanged()
        }

        screenParametersObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
            using: handler
        )
        panelScreenObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: panel,
            queue: .main,
            using: handler
        )
        panelBackingObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: panel,
            queue: .main,
            using: handler
        )
        controlsPanelScreenObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: controlsPanel,
            queue: .main,
            using: handler
        )
        controlsPanelBackingObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: controlsPanel,
            queue: .main,
            using: handler
        )
    }

    private func handleDisplayMetricsChanged() {
        lastAnchorFrame = nil
        resizePanelsToFitContent()
        invalidatePanelRendering()
        syncVisibility()
    }

    private func invalidatePanelRendering() {
        invalidateOverlayRendering(for: panel)
        invalidateOverlayRendering(for: controlsPanel)
    }

    private func positionPanel(using frame: CGRect) {
        let anchorFrame = attachmentEngine.convertAXFrameToScreenCoordinates(frame)
        let preferredScreen = referenceScreen(for: anchorFrame)
        let resolvedDock = resolvedDockPosition(for: anchorFrame, preferredScreen: preferredScreen)
        if dockPosition != resolvedDock {
            dockPosition = resolvedDock
            updateRootView()
        }

        let origin = clampedOrigin(
            proposedOrigin: proposedOrigin(for: anchorFrame, dockPosition: dockPosition),
            preferredScreen: preferredScreen
        )
        let nextHorizontalSide: StackOverlayHorizontalSide = origin.x + panel.frame.width / 2 < anchorFrame.midX ? .left : .right
        if nextHorizontalSide != horizontalSide {
            horizontalSide = nextHorizontalSide
            updateRootView()
        }
        isUpdatingPosition = true
        panel.setFrameOrigin(origin)
        isUpdatingPosition = false
    }

    private func proposedOrigin(for anchorFrame: CGRect, dockPosition: StackOverlayDockPosition) -> CGPoint {
        switch dockPosition {
        case .top:
            return CGPoint(
                x: clampedAttachmentX(
                    proposedX: centeredAttachmentX(for: anchorFrame),
                    anchorFrame: anchorFrame
                ),
                y: anchorFrame.maxY + topGap
            )
        case .bottom:
            return CGPoint(
                x: clampedAttachmentX(
                    proposedX: centeredAttachmentX(for: anchorFrame),
                    anchorFrame: anchorFrame
                ),
                y: anchorFrame.minY - panel.frame.height - bottomGap
            )
        case .left:
            return CGPoint(
                x: anchorFrame.minX - panel.frame.width - sideGap,
                y: clampedAttachmentY(
                    proposedY: anchorFrame.maxY - panel.frame.height - edgeInset + verticalAnchorOffset,
                    anchorFrame: anchorFrame
                )
            )
        case .right:
            return CGPoint(
                x: anchorFrame.maxX + sideGap,
                y: clampedAttachmentY(
                    proposedY: anchorFrame.maxY - panel.frame.height - edgeInset + verticalAnchorOffset,
                    anchorFrame: anchorFrame
                )
            )
        }
    }

    private func centeredAttachmentX(for anchorFrame: CGRect) -> CGFloat {
        anchorFrame.midX - panel.frame.width / 2 + horizontalAnchorOffset
    }

    private func resolvedDockPosition(for anchorFrame: CGRect, preferredScreen: NSScreen?) -> StackOverlayDockPosition {
        let visibleFrame = preferredScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorFrame
        let availableTop = visibleFrame.maxY - anchorFrame.maxY
        let availableBottom = anchorFrame.minY - visibleFrame.minY
        let availableLeft = anchorFrame.minX - visibleFrame.minX
        let availableRight = visibleFrame.maxX - anchorFrame.maxX
        let topFits = availableTop >= panel.frame.height + topGap
        let bottomFits = availableBottom >= panel.frame.height + bottomGap
        let leftFits = availableLeft >= panel.frame.width + sideGap
        let rightFits = availableRight >= panel.frame.width + sideGap

        let preferredFits: Bool = switch preferredDockPosition {
        case .top:
            topFits
        case .bottom:
            bottomFits
        case .left:
            leftFits
        case .right:
            rightFits
        }

        if preferredFits {
            return preferredDockPosition
        }

        for fallback in preferredDockPosition.fallbackOrder {
            switch fallback {
            case .top where topFits:
                return .top
            case .bottom where bottomFits:
                return .bottom
            case .left where leftFits:
                return .left
            case .right where rightFits:
                return .right
            default:
                continue
            }
        }

        // Deprioritize left/right for tall (full-height) windows even in fallback.
        let minY = anchorFrame.minY + edgeInset
        let maxY = max(minY, anchorFrame.maxY - panel.frame.height - edgeInset)
        let verticalTravel = max(0, maxY - minY)
        let sideRailViable = verticalTravel >= panel.frame.height * 1.7

        var fallbackCandidates: [(StackOverlayDockPosition, CGFloat)] = [
            (.top, availableTop),
            (.bottom, availableBottom)
        ]
        if sideRailViable {
            fallbackCandidates.append(contentsOf: [
                (.left, availableLeft),
                (.right, availableRight)
            ])
        }
        return fallbackCandidates.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? preferredDockPosition
    }

    private func syncControlsPanelVisibility() {
        guard !isUserOverlayHidden, isTargetContextFrontmost, controlsPinnedOpen else {
            controlsPanel.orderOut(nil)
            return
        }

        let controlsSize = controlsPanel.contentRect(forFrameRect: controlsPanel.frame).size
        let proposedOrigin: CGPoint = switch dockPosition {
        case .top:
            CGPoint(
                x: panel.frame.midX - controlsSize.width / 2,
                y: panel.frame.minY - controlsSize.height - controlsPanelGap
            )
        case .bottom:
            CGPoint(
                x: panel.frame.midX - controlsSize.width / 2,
                y: panel.frame.maxY + controlsPanelGap
            )
        case .left:
            CGPoint(
                x: panel.frame.maxX + controlsPanelGap,
                y: panel.frame.midY - controlsSize.height / 2
            )
        case .right:
            CGPoint(
                x: panel.frame.minX - controlsSize.width - controlsPanelGap,
                y: panel.frame.midY - controlsSize.height / 2
            )
        }
        controlsPanel.setFrameOrigin(clampedControlsOrigin(proposedOrigin, controlsSize: controlsSize))
        controlsPanel.orderFrontRegardless()
    }

    private func clampedControlsOrigin(_ origin: CGPoint, controlsSize: CGSize) -> CGPoint {
        guard let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return origin
        }

        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX + edgeInset), visibleFrame.maxX - controlsSize.width - edgeInset),
            y: min(max(origin.y, visibleFrame.minY + edgeInset), visibleFrame.maxY - controlsSize.height - edgeInset)
        )
    }

    private var isTargetContextFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID
    }

    private var isUserOverlayHidden: Bool {
        UserDefaults.standard.bool(forKey: "stacker.overlayHidden") ||
        OverlayAppVisibilityPreference.isHidden(bundleIdentifier: appBundleIdentifier, appName: appName)
    }

    private func handleFrontmostApplicationChange(pid: Int32?, bundleIdentifier: String?) {
        _ = pid
        _ = bundleIdentifier
        syncVisibility()
    }

    private func captureUserAnchorOffset() {
        guard !isUpdatingPosition else { return }
        let resolvedAttachment = resolveCurrentAttachment()
        guard let anchorFrame = resolvedAttachment.anchorFrame else { return }
        let clampedOrigin = clampedOrigin(
            proposedOrigin: panel.frame.origin,
            preferredScreen: referenceScreen(for: anchorFrame)
        )
        if panel.frame.origin != clampedOrigin {
            isUpdatingPosition = true
            panel.setFrameOrigin(clampedOrigin)
            isUpdatingPosition = false
        }
        switch dockPosition {
        case .top, .bottom:
            let anchoredX = anchorFrame.midX - panel.frame.width / 2
            horizontalAnchorOffset = panel.frame.minX - anchoredX
            OverlayAttachmentPreference.setHorizontalOffset(
                horizontalAnchorOffset,
                bundleIdentifier: appBundleIdentifier,
                appName: appName
            )
        case .left, .right:
            let anchoredY = anchorFrame.maxY - panel.frame.height - edgeInset
            verticalAnchorOffset = panel.frame.minY - anchoredY
            OverlayAttachmentPreference.setVerticalOffset(
                verticalAnchorOffset,
                bundleIdentifier: appBundleIdentifier,
                appName: appName
            )
        }

        let nextHorizontalSide: StackOverlayHorizontalSide = panel.frame.midX < anchorFrame.midX ? .left : .right
        if nextHorizontalSide != horizontalSide {
            horizontalSide = nextHorizontalSide
            updateRootView()
        }
    }

    private func clampedAttachmentX(proposedX: CGFloat, anchorFrame: CGRect) -> CGFloat {
        let minX = anchorFrame.minX + edgeInset
        let maxX = max(minX, anchorFrame.maxX - panel.frame.width - edgeInset)
        return min(max(proposedX, minX), maxX)
    }

    private func clampedAttachmentY(proposedY: CGFloat, anchorFrame: CGRect) -> CGFloat {
        let minY = anchorFrame.minY + edgeInset
        let maxY = max(minY, anchorFrame.maxY - panel.frame.height - edgeInset)
        return min(max(proposedY, minY), maxY)
    }

    private func resetHorizontalPosition() {
        resetPosition()
    }

    func resetPosition() {
        horizontalAnchorOffset = 0
        verticalAnchorOffset = 0
        OverlayAttachmentPreference.resetOffset(
            bundleIdentifier: appBundleIdentifier,
            appName: appName
        )

        // Reset always tries to put the widget in the most user-friendly default first:
        // 1. Top-left (top rail, left content)
        // 2. Left-top (left rail) for tall windows
        //
        // Only falls back to "best available space" if the preferred sides have very little room.
        // This overrides any previous drag offset or explicit edge the user chose for *this* widget.
        if let anchor = currentAnchorFrameForLayout() {
            let (preferredDock, preferredSide) = preferredInitialDockPositionAndSide(for: anchor)
            dockPosition = preferredDock
            horizontalSide = preferredSide
        }

        onResetPositionRequested()
        syncVisibility()
    }

    /// Called for brand new stacks to force the widget to start on the left side
    /// of a top or bottom rail (instead of letting the first layout decide right).
    func forceLeftBiasForTopDock() {
        if dockPosition == .top || dockPosition == .bottom {
            horizontalSide = .left
            updateRootView()
        }
    }

    /// Returns the user's desired reset/initial position.
    /// Priority order (most user-friendly):
    /// 1. Top rail + left content (top-left) — whenever there's reasonable room on top
    /// 2. Left rail — for tall windows or when left side has decent space
    ///
    /// Only falls back to general "most available space" if the preferred sides
    /// are genuinely constrained.
    private func preferredInitialDockPositionAndSide(for anchorFrame: CGRect)
        -> (StackOverlayDockPosition, StackOverlayHorizontalSide)
    {
        return WindowAttachmentEngine.preferredInitialDockPositionAndSide(for: anchorFrame)
    }

    private func clampedOrigin(proposedOrigin: CGPoint, preferredScreen: NSScreen?) -> CGPoint {
        let visibleFrame = preferredScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: panel.frame.size)
        let inset: CGFloat = 12
        let minX = visibleFrame.minX + inset
        let maxX = max(minX, visibleFrame.maxX - panel.frame.width - inset)
        let minY = visibleFrame.minY + inset
        let maxY = max(minY, visibleFrame.maxY - panel.frame.height - inset)
        let dockMinY = visibleFrame.minY
        let dockMaxY = max(dockMinY, visibleFrame.maxY - panel.frame.height)
        let proposedY = switch dockPosition {
        case .top, .bottom:
            min(max(proposedOrigin.y, dockMinY), dockMaxY)
        case .left, .right:
            min(max(proposedOrigin.y, minY), maxY)
        }

        return CGPoint(
            x: min(max(proposedOrigin.x, minX), maxX),
            y: proposedY
        )
    }

    private func referenceScreen(for anchorFrame: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) })
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
            ?? NSScreen.main
    }

    private func convertAXFrameToScreenCoordinates(_ frame: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            let converted = CGRect(
                x: frame.origin.x,
                y: screen.frame.maxY - frame.origin.y - frame.size.height,
                width: frame.size.width,
                height: frame.size.height
            )
            if screen.frame.intersects(converted) {
                return converted
            }
        }

        return frame
    }
}

final class CombineOverlayPanelController {
    private static let showSuggestionKey = "stacker.showCreateStackSuggestion"
    private let panel: NSPanel
    private let containerView: TransparentContainerView
    private let hostingView: TransparentHostingView<CombineOverlayView>
    private let attachmentEngine = WindowAttachmentEngine()
    private var trackingTimer: Timer?
    private var moveObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var panelScreenObserver: NSObjectProtocol?
    private var panelBackingObserver: NSObjectProtocol?
    private var appPID: pid_t = 0
    private var appBundleIdentifier: String?
    private var style: SuggestionOverlayStyle = .createStack(windowCount: 0)
    private var appName = ""
    private var frameProvider: (() -> CGRect?)?
    private var onTap: (() -> Void)?
    private var anchorOffset = CGPoint(x: 14, y: 14)
    private var isUpdatingPosition = false
    private var isDraggingBackground = false
    private var dragStartOrigin: CGPoint?

    init() {
        hostingView = TransparentHostingView(
            rootView: CombineOverlayView(
                style: .createStack(windowCount: 0),
                onTap: {},
                onDragChanged: { _ in },
                onDragEnded: {}
            )
        )
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlayPanel(panel)
        containerView = TransparentContainerView(frame: NSRect(x: 0, y: 0, width: 180, height: 42))
        containerView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        panel.contentView = containerView
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.isOpaque = false
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDraggingBackground else { return }
            self.captureUserAnchorOffset()
        }

        installDisplayChangeObservers()
    }

    func startTracking(frameProvider: @escaping () -> CGRect?) {
        self.frameProvider = frameProvider
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.syncVisibility()
        }
        if let trackingTimer {
            RunLoop.main.add(trackingTimer, forMode: .common)
        }
        syncVisibility()
    }

    func update(
        appPID: pid_t,
        appBundleIdentifier: String?,
        appName: String,
        style: SuggestionOverlayStyle,
        frameProvider: @escaping () -> CGRect?,
        onTap: @escaping () -> Void
    ) {
        self.appPID = appPID
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.style = style
        self.frameProvider = frameProvider
        self.onTap = onTap
        hostingView.rootView = CombineOverlayView(
            style: style,
            onTap: onTap,
            onDragChanged: { [weak self] delta in
                self?.handleBackgroundDrag(delta)
            },
            onDragEnded: { [weak self] in
                self?.handleBackgroundDragEnded()
            }
        )
        startTracking(frameProvider: frameProvider)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hostingView.invalidateIntrinsicContentSize()
            self.hostingView.layoutSubtreeIfNeeded()
            let fittingSize = self.hostingView.fittingSize
            if self.panel.contentRect(forFrameRect: self.panel.frame).size != fittingSize {
                self.panel.setContentSize(fittingSize)
            }
            self.invalidatePanelRendering()
            self.syncVisibility()
        }
    }

    func clear() {
        appPID = 0
        appBundleIdentifier = nil
        appName = ""
        style = .createStack(windowCount: 0)
        frameProvider = nil
        onTap = nil
        panel.orderOut(nil)
    }

    func close() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let panelScreenObserver {
            NotificationCenter.default.removeObserver(panelScreenObserver)
        }
        if let panelBackingObserver {
            NotificationCenter.default.removeObserver(panelBackingObserver)
        }
        panel.orderOut(nil)
        panel.close()
    }

    private func syncVisibility() {
        guard shouldShowOverlay else {
            panel.orderOut(nil)
            return
        }

        guard let frame = frameProvider?() else {
            panel.orderOut(nil)
            return
        }

        if isDraggingBackground {
            panel.orderFrontRegardless()
            return
        }

        let anchorFrame = attachmentEngine.convertAXFrameToScreenCoordinates(frame)
        let origin = clampedOrigin(
            proposedOrigin: CGPoint(
                x: anchorFrame.minX + anchorOffset.x,
                y: anchorFrame.minY + anchorOffset.y
            ),
            preferredScreen: referenceScreen(for: anchorFrame)
        )
        isUpdatingPosition = true
        panel.setFrameOrigin(origin)
        isUpdatingPosition = false
        panel.orderFrontRegardless()
    }

    private func handleBackgroundDrag(_ delta: CGSize) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            isDraggingBackground = true
        }
        guard let dragStartOrigin else { return }

        let nextOrigin = CGPoint(
            x: dragStartOrigin.x + delta.width,
            y: dragStartOrigin.y + delta.height
        )

        isUpdatingPosition = true
        panel.setFrameOrigin(nextOrigin)
        isUpdatingPosition = false
    }

    private func handleBackgroundDragEnded() {
        dragStartOrigin = nil
        isDraggingBackground = false
        captureUserAnchorOffset()
        syncVisibility()
    }

    private var shouldShowOverlay: Bool {
        appPID != 0 &&
        NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID &&
        isSuggestionEnabled &&
        isSuggestionValid &&
        !OverlayAppVisibilityPreference.isHidden(bundleIdentifier: appBundleIdentifier, appName: appName)
    }

    private var isSuggestionValid: Bool {
        switch style {
        case .createStack(let windowCount):
            return windowCount >= 2
        case .addBack:
            return true
        }
    }

    private var isSuggestionEnabled: Bool {
        switch style {
        case .createStack:
            return UserDefaults.standard.bool(forKey: Self.showSuggestionKey)
        case .addBack:
            return true
        }
    }

    private func captureUserAnchorOffset() {
        guard !isUpdatingPosition, let frame = frameProvider?() else { return }
        let anchorFrame = attachmentEngine.convertAXFrameToScreenCoordinates(frame)
        let clampedOrigin = clampedOrigin(
            proposedOrigin: panel.frame.origin,
            preferredScreen: referenceScreen(for: anchorFrame)
        )
        if panel.frame.origin != clampedOrigin {
            isUpdatingPosition = true
            panel.setFrameOrigin(clampedOrigin)
            isUpdatingPosition = false
        }
        anchorOffset = CGPoint(
            x: panel.frame.minX - anchorFrame.minX,
            y: panel.frame.minY - anchorFrame.minY
        )
    }

    private func clampedOrigin(proposedOrigin: CGPoint, preferredScreen: NSScreen?) -> CGPoint {
        let visibleFrame = preferredScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: panel.frame.size)
        let inset: CGFloat = 12
        let minX = visibleFrame.minX + inset
        let maxX = max(minX, visibleFrame.maxX - panel.frame.width - inset)
        let minY = visibleFrame.minY + inset
        let maxY = max(minY, visibleFrame.maxY - panel.frame.height - inset)
        return CGPoint(
            x: min(max(proposedOrigin.x, minX), maxX),
            y: min(max(proposedOrigin.y, minY), maxY)
        )
    }

    private func referenceScreen(for anchorFrame: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) })
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
            ?? NSScreen.main
    }

    private func installDisplayChangeObservers() {
        let notificationCenter = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in
            self?.handleDisplayMetricsChanged()
        }

        screenParametersObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
            using: handler
        )
        panelScreenObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: panel,
            queue: .main,
            using: handler
        )
        panelBackingObserver = notificationCenter.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: panel,
            queue: .main,
            using: handler
        )
    }

    private func handleDisplayMetricsChanged() {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        if panel.contentRect(forFrameRect: panel.frame).size != fittingSize {
            panel.setContentSize(fittingSize)
        }
        invalidatePanelRendering()
        syncVisibility()
    }

    private func invalidatePanelRendering() {
        invalidateOverlayRendering(for: panel)
    }
}
