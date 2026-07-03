//
//  CompanionPanelView.swift
//  leanring-buddy
//

import SwiftUI

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    @State private var promptText: String = ""
    @State private var workingDirectoryText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 14) {
                backendSection
                promptSection
                responseSection
            }
            .padding(16)

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 380)
        .background(panelBackground)
        .onAppear {
            workingDirectoryText = companionManager.workingDirectoryPath
        }
        .onReceive(companionManager.$workingDirectoryPath) { newPath in
            workingDirectoryText = newPath
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusDotColor.opacity(0.6), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clicky")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text(companionManager.assistantBackendDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            Button(action: {
                NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Codex CLI", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)

                Spacer()

                Button(action: {
                    Task {
                        await companionManager.refreshBackendStatus()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            Text(companionManager.assistantBackendStatusText)
                .font(.system(size: 11))
                .foregroundColor(
                    companionManager.assistantErrorMessage == nil
                        ? DS.Colors.textTertiary
                        : DS.Colors.warning
                )
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            screenContextRow

            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)

                TextField("Path for Codex to read", text: $workingDirectoryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                    )

                HStack(spacing: 8) {
                    Button(action: {
                        companionManager.updateWorkingDirectoryPath(workingDirectoryText)
                    }) {
                        Label("Save", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(LocalPanelButtonStyle(isPrimary: false))
                    .pointerCursor()

                    Button(action: {
                        companionManager.resetWorkingDirectoryToTemporaryDirectory()
                    }) {
                        Label("Temp", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(LocalPanelButtonStyle(isPrimary: false))
                    .pointerCursor()
                }
            }
        }
    }

    private var screenContextRow: some View {
        HStack(spacing: 8) {
            Label(
                companionManager.hasScreenCapturePermission ? "Screen context ready" : "Screen context off",
                systemImage: companionManager.hasScreenCapturePermission ? "display" : "exclamationmark.triangle"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(
                companionManager.hasScreenCapturePermission
                    ? DS.Colors.textTertiary
                    : DS.Colors.warning
            )

            Spacer()

            if companionManager.hasScreenCapturePermission {
                Button(action: {
                    companionManager.refreshScreenCapturePermissionStatus()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            } else {
                Button(action: {
                    companionManager.requestScreenCapturePermission()
                }) {
                    Label("Grant", systemImage: "lock.open")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(LocalPanelButtonStyle(isPrimary: false))
                .pointerCursor()
            }
        }
        .help(companionManager.screenCaptureStatusText)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)

            TextEditor(text: $promptText)
                .font(.system(size: 13))
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 108)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )

            HStack(spacing: 8) {
                Button(action: {
                    companionManager.sendPromptToAssistantBackend(promptText: promptText)
                }) {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LocalPanelButtonStyle(isPrimary: true))
                .pointerCursor()
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companionManager.isRequestInFlight)

                Button(action: {
                    companionManager.cancelCurrentAssistantBackendRequest()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(LocalPanelButtonStyle(isPrimary: false))
                .pointerCursor()
                .disabled(!companionManager.isRequestInFlight)
            }
        }
    }

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)

            ScrollView {
                Text(responseText)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private var footerSection: some View {
        HStack {
            Text("Read-only Codex CLI")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            Spacer()

            Button(action: {
                companionManager.clearScreenOverlay()
            }) {
                Label("Clear overlay", systemImage: "eraser")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Button(action: {
                NSApp.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private var responseText: String {
        if companionManager.assistantStreamingResponseText.isEmpty {
            return "Codex output will appear here."
        }

        return companionManager.assistantStreamingResponseText
    }

    private var statusDotColor: Color {
        switch companionManager.assistantRunState {
        case .idle:
            return companionManager.assistantErrorMessage == nil ? DS.Colors.success : DS.Colors.warning
        case .running:
            return DS.Colors.blue400
        case .cancelling:
            return DS.Colors.warning
        }
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

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.Colors.background)
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

private struct LocalPanelButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isPrimary ? DS.Colors.textOnAccent : DS.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isPrimary
                            ? DS.Colors.accent.opacity(configuration.isPressed ? 0.8 : 1.0)
                            : Color.white.opacity(configuration.isPressed ? 0.10 : 0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: isPrimary ? 0 : 0.5)
            )
    }
}
