//
//  ScreenOverlayWindowManager.swift
//  leanring-buddy
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

enum ScreenOverlayAnnotationShape: Equatable {
    case point(CGPoint)
    case rectangle(CGRect)
    case line(CGPoint, CGPoint)
}

struct ScreenOverlayAnnotation: Identifiable, Equatable {
    let id: UUID
    let shape: ScreenOverlayAnnotationShape
    let label: String
    let screenNumber: Int

    init(
        id: UUID = UUID(),
        shape: ScreenOverlayAnnotationShape,
        label: String,
        screenNumber: Int
    ) {
        self.id = id
        self.shape = shape
        self.label = label
        self.screenNumber = screenNumber
    }
}

@MainActor
final class ScreenOverlayViewModel: ObservableObject {
    @Published var annotations: [ScreenOverlayAnnotation] = []
}

@MainActor
final class ScreenOverlayWindowManager {
    private let viewModel = ScreenOverlayViewModel()
    private var overlayPanels: [NSPanel] = []

    func applyCommands(in text: String) {
        let parseResult = ScreenOverlayCommandParser.parseCommands(in: text)

        if parseResult.shouldClear {
            clear()
        }

        guard !parseResult.annotations.isEmpty else {
            return
        }

        showOverlayPanelsIfNeeded()
        viewModel.annotations = normalizeAnnotations(parseResult.annotations)
    }

    func clear() {
        viewModel.annotations = []
        hideOverlayPanels()
    }

    private func showOverlayPanelsIfNeeded() {
        let screens = NSScreen.screens

        if overlayPanels.count != screens.count {
            recreateOverlayPanels(for: screens)
        }

        for overlayPanel in overlayPanels {
            overlayPanel.orderFrontRegardless()
        }
    }

    private func recreateOverlayPanels(for screens: [NSScreen]) {
        hideOverlayPanels()
        overlayPanels = screens.enumerated().map { screenIndex, screen in
            makeOverlayPanel(
                screen: screen,
                screenNumber: screenIndex + 1
            )
        }
    }

    private func hideOverlayPanels() {
        for overlayPanel in overlayPanels {
            overlayPanel.orderOut(nil)
        }
    }

    private func makeOverlayPanel(
        screen: NSScreen,
        screenNumber: Int
    ) -> NSPanel {
        let overlayPanel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        overlayPanel.level = .screenSaver
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        overlayPanel.isExcludedFromWindowsMenu = true
        overlayPanel.setFrame(screen.frame, display: true)

        let overlayView = ScreenOverlayView(
            screenNumber: screenNumber,
            viewModel: viewModel
        )
        .frame(width: screen.frame.width, height: screen.frame.height)

        overlayPanel.contentView = NSHostingView(rootView: overlayView)
        return overlayPanel
    }

    private func normalizeAnnotations(
        _ draftAnnotations: [ScreenOverlayDraftAnnotation]
    ) -> [ScreenOverlayAnnotation] {
        let fallbackScreenNumber = screenNumberContainingMouse()
        let validScreenNumbers = Set(1...max(NSScreen.screens.count, 1))

        return draftAnnotations.compactMap { draftAnnotation in
            let requestedScreenNumber = draftAnnotation.screenNumber ?? fallbackScreenNumber
            guard validScreenNumbers.contains(requestedScreenNumber) else {
                return nil
            }

            return ScreenOverlayAnnotation(
                shape: draftAnnotation.shape,
                label: draftAnnotation.label,
                screenNumber: requestedScreenNumber
            )
        }
    }

    private func screenNumberContainingMouse() -> Int {
        let mouseLocation = NSEvent.mouseLocation

        for (screenIndex, screen) in NSScreen.screens.enumerated() where screen.frame.contains(mouseLocation) {
            return screenIndex + 1
        }

        return 1
    }
}

private struct ScreenOverlayView: View {
    let screenNumber: Int
    @ObservedObject var viewModel: ScreenOverlayViewModel

    private var annotationsForScreen: [ScreenOverlayAnnotation] {
        viewModel.annotations.filter { annotation in
            annotation.screenNumber == screenNumber
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(annotationsForScreen) { annotation in
                annotationView(annotation)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func annotationView(_ annotation: ScreenOverlayAnnotation) -> some View {
        switch annotation.shape {
        case .point(let point):
            pointAnnotationView(
                point: point,
                label: annotation.label
            )
        case .rectangle(let rectangle):
            rectangleAnnotationView(
                rectangle: rectangle,
                label: annotation.label
            )
        case .line(let startPoint, let endPoint):
            lineAnnotationView(
                startPoint: startPoint,
                endPoint: endPoint,
                label: annotation.label
            )
        }
    }

    private func pointAnnotationView(
        point: CGPoint,
        label: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(DS.Colors.overlayCursorBlue, lineWidth: 3)
                .frame(width: 28, height: 28)
                .position(point)

            Circle()
                .fill(DS.Colors.overlayCursorBlue)
                .frame(width: 8, height: 8)
                .position(point)

            labelView(label)
                .position(x: point.x + 52, y: max(18, point.y - 18))
        }
    }

    private func rectangleAnnotationView(
        rectangle: CGRect,
        label: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Colors.overlayCursorBlue, lineWidth: 3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Colors.overlayCursorBlue.opacity(0.08))
                )
                .frame(width: max(1, rectangle.width), height: max(1, rectangle.height))
                .position(x: rectangle.midX, y: rectangle.midY)

            labelView(label)
                .position(x: rectangle.minX + 54, y: max(18, rectangle.minY - 18))
        }
    }

    private func lineAnnotationView(
        startPoint: CGPoint,
        endPoint: CGPoint,
        label: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            .stroke(
                DS.Colors.overlayCursorBlue,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(DS.Colors.overlayCursorBlue)
                .frame(width: 8, height: 8)
                .position(startPoint)

            Triangle()
                .fill(DS.Colors.overlayCursorBlue)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(rotationDegrees(from: startPoint, to: endPoint)))
                .position(endPoint)

            labelView(label)
                .position(
                    x: (startPoint.x + endPoint.x) / 2 + 52,
                    y: max(18, (startPoint.y + endPoint.y) / 2 - 18)
                )
        }
    }

    private func labelView(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.Colors.overlayCursorBlue)
                    .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.45), radius: 8, x: 0, y: 0)
            )
            .fixedSize()
    }

    private func rotationDegrees(from startPoint: CGPoint, to endPoint: CGPoint) -> Double {
        let radians = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        return Double(radians * 180 / .pi) + 90
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0

        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}
