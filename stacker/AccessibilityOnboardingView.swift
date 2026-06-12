import SwiftUI
import AppKit
import Combine

/// Full detail-pane onboarding shown in the admin window while Stacker lacks
/// Accessibility permission. Polls the trust state so the UI flips to granted
/// (and the pane dismisses) live while the user is in System Settings.
struct AccessibilityOnboardingView: View {
    @State private var trusted = AccessibilityPermissionSupport.isProcessTrusted
    @State private var didRequestAccess = false

    private let trustPoll = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                icon
                heading
                steps
                grantButton
                statusPill

                if let guidance = footerGuidance {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                }
            }
            .padding(.vertical, 44)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Welcome to Stacker")
        .onReceive(trustPoll) { _ in
            // refreshTrustState posts .stackerAccessibilityTrustDidChange on
            // change, which lets the rest of the app react immediately.
            trusted = AccessibilityPermissionCoordinator.refreshTrustState(postOnChangeOnly: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AccessibilityPermissionCoordinator.refreshTrustState(postOnChangeOnly: true)
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 84, height: 84)

            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.top, 8)
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("Allow Stacker to Manage Browser Windows")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Stacker uses macOS Accessibility to read browser window positions and keep stacked windows aligned. macOS requires you to grant this permission once, in System Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(number: 1, text: "Click \"Open System Settings\" below. Stacker is added to the Accessibility list for you.")
            stepRow(number: 2, text: "Turn on the switch next to Stacker.")
            stepRow(number: 3, text: "Come back here — Stacker detects the change automatically.")
        }
        .padding(18)
        .frame(maxWidth: 440, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grantButton: some View {
        Button {
            didRequestAccess = true
            // Registers Stacker in the Accessibility list (no system dialog) so
            // the toggle is already present when System Settings opens.
            AccessibilityPermissionSupport.registerInAccessibilityListSilently()
            AccessibilityPermissionSupport.openSystemSettings()
        } label: {
            Label("Open System Settings", systemImage: "gear")
                .font(.body.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private var statusPill: some View {
        if trusted {
            statusLabel(
                text: "Access granted",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                showsSpinner: false
            )
        } else if didRequestAccess {
            statusLabel(
                text: "Waiting for permission\u{2026}",
                systemImage: "hourglass",
                tint: .orange,
                showsSpinner: true
            )
        }
    }

    private func statusLabel(text: String, systemImage: String, tint: Color, showsSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    }

    private var footerGuidance: String? {
        if AccessibilityPermissionCoordinator.didUpgradeThisLaunch {
            return AccessibilityPermissionSupport.postUpdatePermissionGuidance
        }
        return AccessibilityPermissionSupport.installLocationGuidance
    }
}

#Preview {
    AccessibilityOnboardingView()
        .frame(width: 640, height: 560)
}
