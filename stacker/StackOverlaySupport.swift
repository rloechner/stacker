import SwiftUI

enum StackOverlayDisplayMode: String {
    case horizontal
    case vertical

    var buttonTitle: String {
        switch self {
        case .horizontal:
            return "Horizontal"
        case .vertical:
            return "Vertical"
        }
    }

    var buttonIcon: String {
        switch self {
        case .horizontal:
            return "rectangle.grid.1x2"
        case .vertical:
            return "list.bullet"
        }
    }

    mutating func toggle() {
        self = self == .horizontal ? .vertical : .horizontal
    }
}

enum StackOverlayLabelMode: String {
    case names
    case icons

    var buttonTitle: String {
        switch self {
        case .names:
            return "Names"
        case .icons:
            return "Icons"
        }
    }

    var buttonIcon: String {
        switch self {
        case .names:
            return "textformat"
        case .icons:
            return "circle.grid.2x1"
        }
    }

    mutating func toggle() {
        self = self == .names ? .icons : .names
    }
}

enum StackOverlayAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum StackOverlayAppearancePreference {
    static let key = "stacker.overlayAppearance"

    static func current() -> StackOverlayAppearance {
        StackOverlayAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    static func set(_ appearance: StackOverlayAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: key)
    }
}

extension View {
    @ViewBuilder
    func overlayColorScheme(_ appearance: StackOverlayAppearance) -> some View {
        if let colorScheme = appearance.colorScheme {
            environment(\.colorScheme, colorScheme)
        } else {
            self
        }
    }
}

enum StackOverlayDensityMode: String, CaseIterable {
    case compact
    case comfortable
    case expanded

    var buttonTitle: String {
        switch self {
        case .compact:
            return "Compact"
        case .comfortable:
            return "Comfortable"
        case .expanded:
            return "Expanded"
        }
    }

    var buttonIcon: String {
        switch self {
        case .compact:
            return "rectangle.compress.vertical"
        case .comfortable:
            return "capsule.lefthalf.filled"
        case .expanded:
            return "rectangle.expand.vertical"
        }
    }

    var horizontalNamedWidth: CGFloat {
        switch self {
        case .compact:
            return 80
        case .comfortable:
            return 110
        case .expanded:
            return 128
        }
    }

    var horizontalIconWidth: CGFloat {
        switch self {
        case .compact:
            return 32
        case .comfortable:
            return 46
        case .expanded:
            return 54
        }
    }

    var badgeDiameter: CGFloat {
        switch self {
        case .compact:
            return 12
        case .comfortable:
            return 16
        case .expanded:
            return 18
        }
    }

    var verticalBadgeDiameter: CGFloat {
        switch self {
        case .compact:
            return 22
        case .comfortable:
            return 30
        case .expanded:
            return 34
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact:
            return 5
        case .comfortable:
            return 9
        case .expanded:
            return 11
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return 3
        case .comfortable:
            return 5
        case .expanded:
            return 7
        }
    }

    var railSpacing: CGFloat {
        switch self {
        case .compact:
            return 3
        case .comfortable:
            return 6
        case .expanded:
            return 8
        }
    }

    var railHorizontalInset: CGFloat {
        switch self {
        case .compact:
            return 3
        case .comfortable:
            return 7
        case .expanded:
            return 9
        }
    }

    var railVerticalInset: CGFloat {
        switch self {
        case .compact:
            return 2
        case .comfortable:
            return 5
        case .expanded:
            return 7
        }
    }

    var labelFont: CGFloat {
        switch self {
        case .compact:
            return 8
        case .comfortable:
            return 10
        case .expanded:
            return 11
        }
    }

    var widgetChromeInset: CGFloat {
        switch self {
        case .compact:
            return 3
        case .comfortable:
            return 5
        case .expanded:
            return 6
        }
    }
}

enum StackOverlayDockPosition: String, CaseIterable {
    case top
    case bottom
    case left
    case right

    var buttonTitle: String {
        switch self {
        case .top:
            return "Top"
        case .bottom:
            return "Bottom"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var buttonIcon: String {
        switch self {
        case .top:
            return "dock.arrow.up.rectangle"
        case .bottom:
            return "dock.arrow.down.rectangle"
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        }
    }

    mutating func toggle() {
        switch self {
        case .top:
            self = .right
        case .right:
            self = .bottom
        case .bottom:
            self = .left
        case .left:
            self = .top
        }
    }

    var isHorizontal: Bool {
        self == .top || self == .bottom
    }

    var fallbackOrder: [StackOverlayDockPosition] {
        switch self {
        case .top:
            return [.bottom, .right, .left]
        case .bottom:
            return [.top, .right, .left]
        case .left:
            return [.right, .bottom, .top]
        case .right:
            return [.left, .bottom, .top]
        }
    }
}

enum StackOverlayPlacementPreference: String, CaseIterable {
    case automatic
    case top
    case bottom
    case left
    case right

    var title: String {
        switch self {
        case .automatic:
            return "Auto"
        case .top:
            return "Top"
        case .bottom:
            return "Bottom"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic:
            return "sparkles"
        case .top:
            return "dock.arrow.up.rectangle"
        case .bottom:
            return "dock.arrow.down.rectangle"
        case .left:
            return "arrow.left.to.line"
        case .right:
            return "arrow.right.to.line"
        }
    }

    var dockPosition: StackOverlayDockPosition? {
        switch self {
        case .automatic:
            return nil
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    init(dockPosition: StackOverlayDockPosition) {
        switch dockPosition {
        case .top:
            self = .top
        case .bottom:
            self = .bottom
        case .left:
            self = .left
        case .right:
            self = .right
        }
    }
}

enum StackOverlayPlacementPreferenceStore {
    static let key = "stacker.overlayPlacementPreference"

    static func current() -> StackOverlayPlacementPreference {
        StackOverlayPlacementPreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .left
    }

    static func set(_ preference: StackOverlayPlacementPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: key)
    }
}

enum StackOverlayDockPositionPreference {
    static let key = "stacker.overlayDockPositionsByApp.v1"
    private static let globalIdentifier = "global"

    static func appIdentifier(bundleIdentifier: String?, appName: String) -> String {
        globalIdentifier
    }

    private static func legacyAppIdentifier(bundleIdentifier: String?, appName: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return "name:\(appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func current(bundleIdentifier: String?, appName: String) -> StackOverlayDockPosition? {
        let identifier = appIdentifier(bundleIdentifier: bundleIdentifier, appName: appName)
        let values = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let rawValue = values[identifier] ?? values[legacyAppIdentifier(bundleIdentifier: bundleIdentifier, appName: appName)]
        guard let rawValue else { return nil }
        return StackOverlayDockPosition(rawValue: rawValue)
    }

    static func set(_ position: StackOverlayDockPosition, bundleIdentifier: String?, appName: String) {
        let identifier = appIdentifier(bundleIdentifier: bundleIdentifier, appName: appName)
        var values = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        values[identifier] = position.rawValue
        UserDefaults.standard.set(values, forKey: key)
    }
}

enum StackOverlayHorizontalSide {
    case left
    case right
}

enum StackPillAccent: String, CaseIterable {
    case blue
    case green
    case orange
    case pink
    case graphite

    var title: String {
        rawValue.capitalized
    }

    var tint: Color {
        switch self {
        case .blue:
            return Color.accentColor
        case .green:
            return Color(red: 0.15, green: 0.68, blue: 0.33)
        case .orange:
            return Color(red: 0.94, green: 0.53, blue: 0.16)
        case .pink:
            return Color(red: 0.88, green: 0.31, blue: 0.58)
        case .graphite:
            return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }
}

enum StackOverlayDotPalette: String, CaseIterable, Identifiable {
    case classic
    case ocean
    case sunset
    case forest
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            return "Classic"
        case .ocean:
            return "Ocean"
        case .sunset:
            return "Sunset"
        case .forest:
            return "Forest"
        case .mono:
            return "Mono"
        }
    }

    var accents: [StackPillAccent] {
        switch self {
        case .classic:
            return [.blue, .green, .orange, .pink, .graphite]
        case .ocean:
            return [.blue, .graphite, .green, .blue, .graphite]
        case .sunset:
            return [.orange, .pink, .blue, .orange, .graphite]
        case .forest:
            return [.green, .graphite, .orange, .green, .blue]
        case .mono:
            return [.graphite, .blue, .graphite, .blue, .graphite]
        }
    }
}

enum StackOverlayDotPalettePreference {
    static let key = "stacker.overlayDotPalette"

    static func current() -> StackOverlayDotPalette {
        StackOverlayDotPalette(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .classic
    }
}

struct StackOverlayItem: Identifiable {
    enum WindowState {
        case normal
        case minimized
        case fullscreen

        var statusText: String? {
            switch self {
            case .normal:
                return nil
            case .minimized:
                return "Minimized"
            case .fullscreen:
                return "Fullscreen"
            }
        }

        var symbolName: String? {
            switch self {
            case .normal:
                return nil
            case .minimized:
                return "minus"
            case .fullscreen:
                return "arrow.up.left.and.arrow.down.right"
            }
        }

        var tint: Color {
            switch self {
            case .normal:
                return .clear
            case .minimized:
                return Color(red: 1.0, green: 0.72, blue: 0.18)
            case .fullscreen:
                return Color(red: 0.32, green: 0.58, blue: 1.0)
            }
        }
    }

    let id: UInt
    let title: String
    let subtitle: String?
    let label: String
    let accent: StackPillAccent
    let isSelected: Bool
    let windowState: WindowState

    init(
        id: UInt,
        title: String,
        subtitle: String?,
        label: String,
        accent: StackPillAccent,
        isSelected: Bool,
        windowState: WindowState = .normal
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.label = label
        self.accent = accent
        self.isSelected = isSelected
        self.windowState = windowState
    }
}

struct StackOverlayAddableWindow: Identifiable {
    let id: UInt
    let title: String
    let label: String
}

func stackSymbolName(for token: String) -> String? {
    guard token.hasPrefix("sf:") else { return nil }
    let symbol = String(token.dropFirst(3))
    return symbol.isEmpty ? nil : symbol
}

struct StackBadgeView: View {
    let token: String
    let tint: Color
    let selected: Bool
    let diameter: CGFloat
    let windowState: StackOverlayItem.WindowState

    init(
        token: String,
        tint: Color,
        selected: Bool,
        diameter: CGFloat,
        windowState: StackOverlayItem.WindowState = .normal
    ) {
        self.token = token
        self.tint = tint
        self.selected = selected
        self.diameter = diameter
        self.windowState = windowState
    }

    var body: some View {
        let parkedOpacity: Double = windowState == .normal ? 1.0 : 0.56

        ZStack {
            Circle()
                .fill(
                    badgeFill(parkedOpacity: parkedOpacity)
                )
                .overlay(
                    Circle()
                        .stroke(badgeStroke, lineWidth: selected ? 2.1 : 1)
                )
                .shadow(color: badgeShadow, radius: selected ? 5 : 2, y: selected ? 1 : 0)

            if windowState == .minimized {
                Image(systemName: "minus")
                    .font(.system(size: diameter * 0.44, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.96))
            } else if let symbolName = stackSymbolName(for: token) {
                Image(systemName: symbolName)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.92))
            } else {
                Text(String(token.prefix(2)))
                    .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.92))
            }

            if windowState != .minimized, let stateSymbolName = windowState.symbolName {
                Circle()
                    .fill(.regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                    )
                    .frame(width: diameter * 0.46, height: diameter * 0.46)
                    .overlay(
                        Image(systemName: stateSymbolName)
                            .font(.system(size: diameter * 0.20, weight: .heavy))
                            .foregroundStyle(windowState.tint)
                    )
                    .offset(x: diameter * 0.26, y: diameter * 0.26)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func badgeFill(parkedOpacity: Double) -> LinearGradient {
        if windowState == .minimized {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.78, blue: 0.24),
                    Color(red: 0.92, green: 0.52, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: selected
                ? [tint.opacity(1.0 * parkedOpacity), tint.opacity(0.86 * parkedOpacity)]
                : [tint.opacity(0.72 * parkedOpacity), tint.opacity(0.48 * parkedOpacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var badgeStroke: Color {
        if windowState == .minimized {
            return selected ? Color.white.opacity(0.90) : Color(red: 0.70, green: 0.38, blue: 0.02).opacity(0.42)
        }
        return selected ? Color.white.opacity(0.90) : tint.opacity(0.36)
    }

    private var badgeShadow: Color {
        if windowState == .minimized {
            return Color(red: 1.0, green: 0.66, blue: 0.12).opacity(selected ? 0.26 : 0.10)
        }
        return tint.opacity(selected ? 0.28 : 0.08)
    }
}
