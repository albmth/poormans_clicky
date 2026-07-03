//
//  TutorialPromptPanelManager.swift
//  leanring-buddy
//

import AppKit
import CoreGraphics
import SwiftUI

private final class TutorialPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TutorialPromptPanelManager {
    private let companionManager: CompanionManager

    private var promptPanel: TutorialPromptPanel?
    private var shortcutPollingTimer: Timer?
    private var isShortcutPressed = false
    private var outsideClickMonitor: Any?
    private var localKeyMonitor: Any?

    private let panelWidth: CGFloat = 500
    private let panelHeight: CGFloat = 138
    private let screenEdgePadding: CGFloat = 14
    private let panelGapFromMouse: CGFloat = 22

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
    }

    deinit {
        shortcutPollingTimer?.invalidate()

        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func start() {
        startShortcutPolling()
    }

    func stop() {
        shortcutPollingTimer?.invalidate()
        shortcutPollingTimer = nil
        hidePromptPanel()
    }

    private func startShortcutPolling() {
        shortcutPollingTimer?.invalidate()

        let shortcutPollingTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateShortcutState()
            }
        }

        RunLoop.main.add(shortcutPollingTimer, forMode: .common)
        self.shortcutPollingTimer = shortcutPollingTimer
    }

    private func updateShortcutState() {
        let isCommandOptionPressed = Self.isCommandOptionPressed()

        if isCommandOptionPressed && !isShortcutPressed {
            showPromptPanel()
        }

        isShortcutPressed = isCommandOptionPressed
    }

    private static func isCommandOptionPressed() -> Bool {
        let modifierFlags = CGEventSource.flagsState(.combinedSessionState)
        let hasCommand = modifierFlags.contains(.maskCommand)
        let hasOption = modifierFlags.contains(.maskAlternate)
        let hasControl = modifierFlags.contains(.maskControl)
        let hasShift = modifierFlags.contains(.maskShift)

        return hasCommand && hasOption && !hasControl && !hasShift
    }

    private func showPromptPanel() {
        if promptPanel == nil {
            createPromptPanel()
        }

        positionPromptPanelNearMouse()
        NSApp.activate(ignoringOtherApps: true)
        promptPanel?.makeKeyAndOrderFront(nil)
        promptPanel?.orderFrontRegardless()
        installPanelDismissalMonitors()
    }

    private func hidePromptPanel() {
        promptPanel?.orderOut(nil)
        promptPanel = nil
        removePanelDismissalMonitors()
    }

    private func createPromptPanel() {
        let tutorialPromptPanelView = TutorialPromptPanelView(
            companionManager: companionManager,
            onSubmit: { [weak self] userGoal in
                self?.submitTutorialPrompt(userGoal: userGoal)
            },
            onCancel: { [weak self] in
                self?.hidePromptPanel()
            }
        )
        .frame(width: panelWidth, height: panelHeight)

        let hostingView = NSHostingView(rootView: tutorialPromptPanelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let promptPanel = TutorialPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        promptPanel.isFloatingPanel = true
        promptPanel.level = .screenSaver
        promptPanel.isOpaque = false
        promptPanel.backgroundColor = .clear
        promptPanel.hasShadow = false
        promptPanel.hidesOnDeactivate = false
        promptPanel.isExcludedFromWindowsMenu = true
        promptPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        promptPanel.isMovableByWindowBackground = false
        promptPanel.titleVisibility = .hidden
        promptPanel.titlebarAppearsTransparent = true
        promptPanel.contentView = hostingView

        self.promptPanel = promptPanel
    }

    private func positionPromptPanelNearMouse() {
        guard let promptPanel else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main

        guard let screen else {
            return
        }

        let visibleFrame = screen.visibleFrame.insetBy(
            dx: screenEdgePadding,
            dy: screenEdgePadding
        )
        let preferredOriginBelowMouse = CGPoint(
            x: mouseLocation.x - panelWidth / 2,
            y: mouseLocation.y - panelHeight - panelGapFromMouse
        )
        let fallbackOriginAboveMouse = CGPoint(
            x: preferredOriginBelowMouse.x,
            y: mouseLocation.y + panelGapFromMouse
        )
        let unclampedOrigin = preferredOriginBelowMouse.y >= visibleFrame.minY
            ? preferredOriginBelowMouse
            : fallbackOriginAboveMouse

        let clampedOrigin = CGPoint(
            x: min(max(unclampedOrigin.x, visibleFrame.minX), visibleFrame.maxX - panelWidth),
            y: min(max(unclampedOrigin.y, visibleFrame.minY), visibleFrame.maxY - panelHeight)
        )

        promptPanel.setFrame(
            NSRect(x: clampedOrigin.x, y: clampedOrigin.y, width: panelWidth, height: panelHeight),
            display: true
        )
    }

    private func installPanelDismissalMonitors() {
        removePanelDismissalMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let promptPanel = self.promptPanel, promptPanel.isVisible else {
                    return
                }

                if !promptPanel.frame.contains(NSEvent.mouseLocation) {
                    self.hidePromptPanel()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }

            Task { @MainActor [weak self] in
                self?.hidePromptPanel()
            }

            return nil
        }
    }

    private func removePanelDismissalMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func submitTutorialPrompt(userGoal: String) {
        guard companionManager.sendTutorialGuidePrompt(userGoal: userGoal) != nil else {
            return
        }

        hidePromptPanel()
    }
}

private struct TutorialPromptPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    private var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.overlayCursorBlue)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(DS.Colors.overlayCursorBlue.opacity(0.15))
                    )

                Text("Guide")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Spacer()

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusTextColor)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            HStack(spacing: 10) {
                TextField("What do you want to do?", text: $promptText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .focused($isPromptFocused)
                    .onSubmit {
                        submitPromptIfPossible()
                    }

                Button(action: submitPromptIfPossible) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Colors.textOnAccent)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(sendButtonBackgroundColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor(isEnabled: canSubmitPrompt)
                .disabled(!canSubmitPrompt)
            }
        }
        .padding(14)
        .frame(width: 500, height: 138)
        .background(panelBackground)
        .onAppear {
            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.Colors.background)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.18), radius: 22, x: 0, y: 0)
    }

    private var canSubmitPrompt: Bool {
        !trimmedPromptText.isEmpty && !companionManager.isRequestInFlight
    }

    private var sendButtonBackgroundColor: Color {
        canSubmitPrompt ? DS.Colors.accent : DS.Colors.disabledBackground
    }

    private var statusText: String {
        switch companionManager.assistantRunState {
        case .idle:
            return companionManager.assistantErrorMessage == nil ? "Ready" : "Needs attention"
        case .running:
            return "Running"
        case .cancelling:
            return "Stopping"
        }
    }

    private var statusTextColor: Color {
        if companionManager.assistantErrorMessage != nil {
            return DS.Colors.warning
        }

        switch companionManager.assistantRunState {
        case .idle:
            return DS.Colors.textTertiary
        case .running:
            return DS.Colors.blue400
        case .cancelling:
            return DS.Colors.warning
        }
    }

    private func submitPromptIfPossible() {
        guard canSubmitPrompt else {
            return
        }

        onSubmit(trimmedPromptText)
        promptText = ""
    }
}
