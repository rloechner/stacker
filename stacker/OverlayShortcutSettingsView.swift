import SwiftUI
import AppKit

struct OverlayShortcutSettingsView: View {
    @AppStorage(OverlayShortcutPreference.keyCodeKey) private var keyCode = OverlayShortcutPreference.defaultKeyCode
    @AppStorage(OverlayShortcutPreference.modifiersKey) private var modifiersRawValue = OverlayShortcutPreference.defaultModifiers
    @AppStorage(OverlayShortcutPreference.hiddenKey) private var overlayHidden = false
    @AppStorage(StackJumpShortcutPreference.enabledKey) private var stackJumpShortcutsEnabled = StackJumpShortcutPreference.defaultEnabled
    @AppStorage(StackJumpShortcutPreference.modifiersKey) private var stackJumpModifiersRawValue = StackJumpShortcutPreference.defaultModifiers
    @AppStorage(StackOverlayAppearancePreference.key) private var widgetAppearanceRawValue = StackOverlayAppearance.system.rawValue
    @AppStorage(StackOverlayDotPalettePreference.key) private var dotPaletteRawValue = StackOverlayDotPalette.classic.rawValue
    @AppStorage(StackOverlayPlacementPreferenceStore.key) private var placementRawValue = StackOverlayPlacementPreference.top.rawValue
    @AppStorage(MaximizedWindowOverlayPreference.enabledKey) private var maximizedOverlayEnabled = true
    @AppStorage(MaximizedWindowOverlayPreference.expandOnHoverKey) private var maximizedOverlayExpandOnHover = false
    @State private var accessibilityTrusted = AccessibilityPermissionSupport.isProcessTrusted
    @State private var showPostUpdateAccessibilityHint = false

    private var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(modifiersRawValue)) }
        set { modifiersRawValue = Int(newValue.rawValue) }
    }

    private var stackJumpModifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(stackJumpModifiersRawValue)) }
        set { stackJumpModifiersRawValue = Int(newValue.rawValue) }
    }

    private var shortcutPreview: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiersRawValue))
        let pieces = [
            flags.contains(.command) ? "Command" : nil,
            flags.contains(.option) ? "Option" : nil,
            flags.contains(.control) ? "Control" : nil,
            flags.contains(.shift) ? "Shift" : nil,
            ShortcutKeyOption.commonOptions.first(where: { $0.id == UInt16(keyCode) })?.title
        ].compactMap { $0 }
        return pieces.joined(separator: " + ")
    }

    private var stackJumpShortcutPreview: String {
        StackJumpShortcutState.shortcutDescription()
    }

    private var selectedPalette: StackOverlayDotPalette {
        StackOverlayDotPalette(rawValue: dotPaletteRawValue) ?? .classic
    }

    private var selectedWidgetAppearance: StackOverlayAppearance {
        StackOverlayAppearance(rawValue: widgetAppearanceRawValue) ?? .system
    }

    private var selectedPlacement: StackOverlayPlacementPreference {
        StackOverlayPlacementPreference(rawValue: placementRawValue) ?? .top
    }

    private var previewDockPosition: StackOverlayDockPosition {
        selectedPlacement.dockPosition ?? .top
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                settingsControls
                    .frame(minWidth: 360, maxWidth: 430, alignment: .topLeading)

                previewSection
                    .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 10) {
                settingsControls
                previewSection
            }
        }
        .padding(18)
        .frame(maxWidth: 720, alignment: .topLeading)
        .onAppear {
            refreshAccessibilityStatus()
            showPostUpdateAccessibilityHint =
                AccessibilityPermissionCoordinator.didUpgradeThisLaunch && !accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackerAccessibilityTrustDidChange)) { notification in
            if let trusted = notification.object as? Bool {
                accessibilityTrusted = trusted
            } else {
                refreshAccessibilityStatus()
            }
            if accessibilityTrusted {
                showPostUpdateAccessibilityHint = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onChange(of: overlayHidden) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerOverlayVisibilityDidChange, object: nil)
            }
        }
        .onChange(of: dotPaletteRawValue) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerOverlayPaletteDidChange, object: nil)
            }
        }
        .onChange(of: widgetAppearanceRawValue) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerOverlayAppearanceDidChange, object: nil)
            }
        }
        .onChange(of: placementRawValue) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerOverlayPlacementDidChange, object: nil)
            }
        }
        .onChange(of: maximizedOverlayEnabled) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerMaximizedOverlayPreferenceDidChange, object: nil)
            }
        }
        .onChange(of: maximizedOverlayExpandOnHover) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stackerMaximizedOverlayPreferenceDidChange, object: nil)
            }
        }
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            lookSection
            widgetSection
            controlsSection
        }
    }

    private var previewSection: some View {
        WidgetPreviewSection(
            palette: selectedPalette,
            appearance: selectedWidgetAppearance,
            dockPosition: previewDockPosition,
            usesAutomaticPlacement: selectedPlacement == .automatic
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stacker")
                .font(.title2.weight(.semibold))
            Text("Keep the widget quiet, readable, and quick to reach.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var lookSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Widget appearance", selection: $widgetAppearanceRawValue) {
                    ForEach(StackOverlayAppearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                palettePicker
            }
            .padding(.top, 2)
        } label: {
            Label("Look", systemImage: "paintpalette")
        }
    }

    private var widgetSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Edge", selection: $placementRawValue) {
                    ForEach(StackOverlayPlacementPreference.allCases, id: \.rawValue) { placement in
                        Text(placement.title).tag(placement.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button(overlayHidden ? "Show Widgets Now" : "Hide Widgets Now") {
                        overlayHidden = OverlayShortcutState.toggleVisibility()
                    }

                    Text("Shortcut: \(shortcutPreview)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Show switcher on maximized windows", isOn: $maximizedOverlayEnabled)

                Toggle("Expand switcher on hover (maximized only)", isOn: $maximizedOverlayExpandOnHover)
                    .disabled(!maximizedOverlayEnabled)
            }
            .padding(.top, 2)
        } label: {
            Label("Widget", systemImage: "capsule")
        }
    }

    private var controlsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                shortcutEditor

                Divider()

                stackJumpShortcutEditor

                Divider()

                accessibilityRow
            }
            .padding(.top, 2)
        } label: {
            Label("Controls", systemImage: "keyboard")
        }
    }

    private var stackJumpShortcutEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Jump to stack slot with number keys", isOn: $stackJumpShortcutsEnabled)

            Text("Control+1 switches to the first stacked window. Only active when a stacked browser is frontmost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    stackJumpModifierButton("Command", flag: .command)
                    stackJumpModifierButton("Option", flag: .option)
                    stackJumpModifierButton("Control", flag: .control)
                    stackJumpModifierButton("Shift", flag: .shift)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        stackJumpModifierButton("Command", flag: .command)
                        stackJumpModifierButton("Option", flag: .option)
                        stackJumpModifierButton("Control", flag: .control)
                        stackJumpModifierButton("Shift", flag: .shift)
                    }
                }
            }
            .disabled(!stackJumpShortcutsEnabled)

            HStack(spacing: 10) {
                Text(stackJumpShortcutPreview)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset Stack Jump Shortcut") {
                    stackJumpModifiersRawValue = StackJumpShortcutPreference.defaultModifiers
                }
                .disabled(!stackJumpShortcutsEnabled)
            }
        }
    }

    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    accessibilityStatus
                    Spacer()
                    accessibilityButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    accessibilityStatus
                    accessibilityButtons
                }
            }

            if showPostUpdateAccessibilityHint {
                Text(AccessibilityPermissionSupport.postUpdatePermissionGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let installGuidance = AccessibilityPermissionSupport.installLocationGuidance {
                Text(installGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)

            Text(accessibilityTrusted ? "Accessibility enabled" : "Accessibility needs approval")
                .font(.system(size: 13, weight: .medium))
        }
    }

    private var accessibilityButtons: some View {
        HStack(spacing: 8) {
            Button("Open Settings") {
                AccessibilityPermissionSupport.openSystemSettings()
            }

            Button("Check Again") {
                _ = AccessibilityPermissionCoordinator.refreshTrustState()
                refreshAccessibilityStatus()
            }
        }
    }

    private var palettePicker: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("Widget dots", selection: $dotPaletteRawValue) {
                ForEach(StackOverlayDotPalette.allCases) { palette in
                    Text(palette.title).tag(palette.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            HStack(spacing: 7) {
                ForEach(Array(selectedPalette.accents.enumerated()), id: \.offset) { _, accent in
                    Circle()
                        .fill(accent.tint)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                }
            }

            Spacer()
        }
    }

    private var shortcutEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    shortcutKeyPicker

                    HStack(spacing: 6) {
                        modifierButton("Command", flag: .command)
                        modifierButton("Option", flag: .option)
                        modifierButton("Control", flag: .control)
                        modifierButton("Shift", flag: .shift)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    shortcutKeyPicker

                    HStack(spacing: 6) {
                        modifierButton("Command", flag: .command)
                        modifierButton("Option", flag: .option)
                        modifierButton("Control", flag: .control)
                        modifierButton("Shift", flag: .shift)
                    }
                }
            }

            HStack(spacing: 10) {
                Text(shortcutPreview)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset Shortcut") {
                    keyCode = Int(OverlayShortcutPreference.defaultKeyCode)
                    modifiersRawValue = OverlayShortcutPreference.defaultModifiers
                }
            }
        }
    }

    private var shortcutKeyPicker: some View {
        Picker("Key", selection: $keyCode) {
            ForEach(ShortcutKeyOption.commonOptions) { option in
                Text(option.title).tag(Int(option.id))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 110)
    }

    private func modifierButton(_ title: String, flag: NSEvent.ModifierFlags) -> some View {
        let isOn = modifierFlags.contains(flag)
        return Button {
            var next = NSEvent.ModifierFlags(rawValue: UInt(modifiersRawValue))
            if isOn {
                next.remove(flag)
            } else {
                next.insert(flag)
            }
            modifiersRawValue = Int(next.rawValue)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isOn ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func stackJumpModifierButton(_ title: String, flag: NSEvent.ModifierFlags) -> some View {
        let isOn = stackJumpModifierFlags.contains(flag)
        return Button {
            var next = NSEvent.ModifierFlags(rawValue: UInt(stackJumpModifiersRawValue))
            if isOn {
                next.remove(flag)
            } else {
                next.insert(flag)
            }
            stackJumpModifiersRawValue = Int(next.rawValue)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isOn ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionCoordinator.refreshTrustState(postOnChangeOnly: true)
    }
}

private struct WidgetPreviewSection: View {
    let palette: StackOverlayDotPalette
    let appearance: StackOverlayAppearance
    let dockPosition: StackOverlayDockPosition
    let usesAutomaticPlacement: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                WidgetPreviewCanvas(
                    palette: palette,
                    appearance: appearance,
                    dockPosition: dockPosition
                )
                    .frame(maxWidth: .infinity)
                    .overlayColorScheme(appearance)

                HStack(spacing: 8) {
                    Label(usesAutomaticPlacement ? "Auto edge preview" : "\(dockPosition.buttonTitle) edge", systemImage: dockPosition.buttonIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(.top, 2)
        } label: {
            Label("Preview", systemImage: "rectangle.on.rectangle")
        }
    }
}

private struct WidgetPreviewCanvas: View {
    let palette: StackOverlayDotPalette
    let appearance: StackOverlayAppearance
    let dockPosition: StackOverlayDockPosition

    private let windowSize = CGSize(width: 208, height: 136)
    private let horizontalWidgetSize = CGSize(width: 132, height: 26)
    private let verticalWidgetSize = CGSize(width: 26, height: 112)

    var body: some View {
        ZStack {
            previewWindow
            previewWidget
        }
        .frame(width: 238, height: 184)
    }

    private var previewWindow: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(appearance == .dark ? 0.30 : 0.16), radius: 18, y: 10)
            .frame(width: windowSize.width, height: windowSize.height)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Circle().fill(Color.red.opacity(0.72))
                    Circle().fill(Color.yellow.opacity(0.72))
                    Circle().fill(Color.green.opacity(0.72))
                }
                .frame(width: 48, height: 12)
                .padding(.top, 12)
                .padding(.leading, 14)
            }
    }

    @ViewBuilder
    private var previewWidget: some View {
        switch dockPosition {
        case .top:
            drawer(dockPosition: .top)
                .offset(y: -(windowSize.height + horizontalWidgetSize.height) / 2 + 1)
        case .bottom:
            drawer(dockPosition: .bottom)
                .offset(y: (windowSize.height + horizontalWidgetSize.height) / 2 - 1)
        case .left:
            drawer(dockPosition: .left)
                .offset(x: -(windowSize.width + verticalWidgetSize.width) / 2 + 1)
        case .right:
            drawer(dockPosition: .right)
                .offset(x: (windowSize.width + verticalWidgetSize.width) / 2 - 1)
        }
    }

    private func drawer(dockPosition: StackOverlayDockPosition) -> some View {
        let isHorizontal = dockPosition.isHorizontal
        let size = isHorizontal ? horizontalWidgetSize : verticalWidgetSize

        return ZStack {
            drawerShape(for: dockPosition)
                .fill(.thinMaterial)
                .overlay(
                    drawerShape(for: dockPosition)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            if isHorizontal {
                HStack(spacing: 8) {
                    dots
                }
            } else {
                VStack(spacing: 8) {
                    dots
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var dots: some View {
        ForEach(Array(palette.accents.prefix(4).enumerated()), id: \.offset) { index, accent in
            let isSelected = index == 0
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.tint.opacity(isSelected ? 1.0 : 0.42),
                            accent.tint.opacity(isSelected ? 0.88 : 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: isSelected ? 15.5 : 14, height: isSelected ? 15.5 : 14)
                .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0.55 : 0.16), lineWidth: isSelected ? 1.1 : 0.75))
                .shadow(color: accent.tint.opacity(isSelected ? 0.55 : 0.04), radius: isSelected ? 8 : 1.5, y: isSelected ? 1 : 0)
        }
    }

    private func drawerShape(for position: StackOverlayDockPosition) -> UnevenRoundedRectangle {
        switch position {
        case .top:
            return UnevenRoundedRectangle(
                topLeadingRadius: 9,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 9,
                style: .continuous
            )
        case .bottom:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 9,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .left:
            return UnevenRoundedRectangle(
                topLeadingRadius: 9,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .right:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 9,
                topTrailingRadius: 9,
                style: .continuous
            )
        }
    }

}
