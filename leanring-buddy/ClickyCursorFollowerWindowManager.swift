//
//  ClickyCursorFollowerWindowManager.swift
//  leanring-buddy
//

import AppKit
import SwiftUI

@MainActor
final class ClickyCursorFollowerWindowManager {
    private var cursorPanel: NSPanel?
    private var cursorUpdateTimer: Timer?

    private let cursorWindowSize = NSSize(width: 54, height: 54)
    private let cursorOffsetFromMouse = CGPoint(x: 10, y: -50)
    private let screenEdgePadding: CGFloat = 8

    func start() {
        showCursorPanelIfNeeded()
        updateCursorPanelPosition()
        startCursorUpdateTimer()
    }

    func stop() {
        cursorUpdateTimer?.invalidate()
        cursorUpdateTimer = nil
        cursorPanel?.orderOut(nil)
        cursorPanel = nil
    }

    private func startCursorUpdateTimer() {
        cursorUpdateTimer?.invalidate()

        let cursorUpdateTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCursorPanelPosition()
            }
        }

        RunLoop.main.add(cursorUpdateTimer, forMode: .common)
        self.cursorUpdateTimer = cursorUpdateTimer
    }

    private func showCursorPanelIfNeeded() {
        guard cursorPanel == nil else {
            return
        }

        let cursorPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: cursorWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        cursorPanel.level = .screenSaver
        cursorPanel.isOpaque = false
        cursorPanel.backgroundColor = .clear
        cursorPanel.hasShadow = false
        cursorPanel.ignoresMouseEvents = true
        cursorPanel.hidesOnDeactivate = false
        cursorPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        cursorPanel.isExcludedFromWindowsMenu = true

        let cursorView = ClickyCursorFollowerView()
            .frame(width: cursorWindowSize.width, height: cursorWindowSize.height)

        cursorPanel.contentView = NSHostingView(rootView: cursorView)
        cursorPanel.orderFrontRegardless()
        self.cursorPanel = cursorPanel
    }

    private func updateCursorPanelPosition() {
        showCursorPanelIfNeeded()

        guard let cursorPanel else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let preferredOrigin = CGPoint(
            x: mouseLocation.x + cursorOffsetFromMouse.x,
            y: mouseLocation.y + cursorOffsetFromMouse.y
        )
        let clampedOrigin = clampedPanelOrigin(
            preferredOrigin,
            mouseLocation: mouseLocation
        )

        cursorPanel.setFrameOrigin(clampedOrigin)

        if !cursorPanel.isVisible {
            cursorPanel.orderFrontRegardless()
        }
    }

    private func clampedPanelOrigin(
        _ preferredOrigin: CGPoint,
        mouseLocation: CGPoint
    ) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { screen in
            screen.frame.contains(mouseLocation)
        }) ?? NSScreen.main else {
            return preferredOrigin
        }

        let usableFrame = screen.frame.insetBy(dx: screenEdgePadding, dy: screenEdgePadding)
        let minimumX = usableFrame.minX
        let maximumX = usableFrame.maxX - cursorWindowSize.width
        let minimumY = usableFrame.minY
        let maximumY = usableFrame.maxY - cursorWindowSize.height

        return CGPoint(
            x: min(max(preferredOrigin.x, minimumX), maximumX),
            y: min(max(preferredOrigin.y, minimumY), maximumY)
        )
    }
}

private struct ClickyCursorFollowerView: View {
    @State private var isPulseExpanded = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(
                    DS.Colors.overlayCursorBlue.opacity(isPulseExpanded ? 0.34 : 0.18),
                    lineWidth: 1.2
                )
                .frame(width: 34, height: 34)
                .position(x: 28, y: 28)
                .scaleEffect(isPulseExpanded ? 1.06 : 0.94)

            ClickyCursorTriangle()
                .fill(DS.Colors.overlayCursorBlue)
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(35))
                .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.65), radius: 8, x: 0, y: 0)
                .position(x: 22, y: 20)

            ClickyCursorTriangle()
                .stroke(Color.white.opacity(0.86), lineWidth: 1.1)
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(35))
                .position(x: 22, y: 20)
        }
        .frame(width: 54, height: 54)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.25)
                .repeatForever(autoreverses: true)
            ) {
                isPulseExpanded = true
            }
        }
    }
}

private struct ClickyCursorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}
