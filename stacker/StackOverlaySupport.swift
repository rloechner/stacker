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
        StackOverlayPlacementPreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .top
    }

    static func set(_ preference: StackOverlayPlacementPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: key)
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
    let id: UInt
    let title: String
    let subtitle: String?
    let label: String
    let accent: StackPillAccent
    let isSelected: Bool

    init(
        id: UInt,
        title: String,
        subtitle: String?,
        label: String,
        accent: StackPillAccent,
        isSelected: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.label = label
        self.accent = accent
        self.isSelected = isSelected
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

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: selected
                            ? [tint.opacity(1.0), tint.opacity(0.86)]
                            : [tint.opacity(0.72), tint.opacity(0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(selected ? Color.white.opacity(0.90) : tint.opacity(0.36), lineWidth: selected ? 2.1 : 1)
                )
                .shadow(color: tint.opacity(selected ? 0.28 : 0.08), radius: selected ? 5 : 2, y: selected ? 1 : 0)

            if let symbolName = stackSymbolName(for: token) {
                Image(systemName: symbolName)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.92))
            } else {
                Text(String(token.prefix(2)))
                    .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.92))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
