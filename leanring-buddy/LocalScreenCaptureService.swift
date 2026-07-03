//
//  LocalScreenCaptureService.swift
//  leanring-buddy
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct LocalScreenCaptureBatch: Equatable, Sendable {
    let captures: [LocalScreenCapture]
    let temporaryDirectoryURL: URL

    var imageFileURLs: [URL] {
        captures.map(\.imageFileURL)
    }

    var promptDescription: String {
        captures
            .map(\.promptDescription)
            .joined(separator: "\n")
    }
}

struct LocalScreenCapture: Equatable, Sendable {
    let screenNumber: Int
    let imageFileURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let pointWidth: Int
    let pointHeight: Int
    let backingScaleFactor: Double

    var promptDescription: String {
        let formattedScaleFactor = String(format: "%.2f", backingScaleFactor)

        return "screen\(screenNumber): attached image \(imageFileURL.lastPathComponent), \(pixelWidth)x\(pixelHeight) pixels, \(pointWidth)x\(pointHeight) screen points, scale \(formattedScaleFactor)"
    }
}

enum LocalScreenCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case noDisplaysCaptured
    case cannotCreateImageDestination(String)
    case cannotFinalizeImage(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is needed before Codex can see the screen."
        case .noDisplaysCaptured:
            return "No screen images could be captured."
        case .cannotCreateImageDestination(let path):
            return "Could not create a screenshot file at \(path)."
        case .cannotFinalizeImage(let path):
            return "Could not write a screenshot file at \(path)."
        }
    }
}

@MainActor
enum LocalScreenCaptureService {
    static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func captureAllDisplays(
        fileManager: FileManager = .default
    ) async throws -> LocalScreenCaptureBatch {
        guard hasScreenCapturePermission() else {
            throw LocalScreenCaptureError.permissionDenied
        }

        let shareableContent = try await SCShareableContent.current
        let displaysByDisplayID = Dictionary(
            uniqueKeysWithValues: shareableContent.displays.map { display in
                (display.displayID, display)
            }
        )
        let temporaryDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "clicky-screen-captures-\(UUID().uuidString)",
                isDirectory: true
            )

        try fileManager.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )

        var captures: [LocalScreenCapture] = []

        for (screenIndex, screen) in NSScreen.screens.enumerated() {
            guard let displayID = displayID(for: screen),
                  let display = displaysByDisplayID[displayID],
                  let capture = try await capture(
                screen: screen,
                display: display,
                screenNumber: screenIndex + 1,
                temporaryDirectoryURL: temporaryDirectoryURL
            ) else {
                continue
            }

            captures.append(capture)
        }

        guard !captures.isEmpty else {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
            throw LocalScreenCaptureError.noDisplaysCaptured
        }

        return LocalScreenCaptureBatch(
            captures: captures,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    static func removeTemporaryCaptureDirectory(
        for captureBatch: LocalScreenCaptureBatch?,
        fileManager: FileManager = .default
    ) {
        guard let captureBatch else {
            return
        }

        try? fileManager.removeItem(at: captureBatch.temporaryDirectoryURL)
    }

    private static func capture(
        screen: NSScreen,
        display: SCDisplay,
        screenNumber: Int,
        temporaryDirectoryURL: URL
    ) async throws -> LocalScreenCapture? {
        let imageFileURL = temporaryDirectoryURL
            .appendingPathComponent("screen\(screenNumber).png", isDirectory: false)
        let pointWidth = Int(screen.frame.width.rounded())
        let pointHeight = Int(screen.frame.height.rounded())
        let scaleFactor = screen.backingScaleFactor
        let streamConfiguration = SCStreamConfiguration()

        streamConfiguration.width = max(Int(screen.frame.width * scaleFactor), display.width)
        streamConfiguration.height = max(Int(screen.frame.height * scaleFactor), display.height)
        streamConfiguration.showsCursor = true
        streamConfiguration.capturesAudio = false

        let contentFilter = SCContentFilter(
            display: display,
            excludingWindows: []
        )
        let cgImage = try await captureImage(
            contentFilter: contentFilter,
            configuration: streamConfiguration
        )

        try writePNGImage(
            cgImage,
            to: imageFileURL
        )

        let capturedScaleFactor = Double(cgImage.width) / max(Double(pointWidth), 1)

        return LocalScreenCapture(
            screenNumber: screenNumber,
            imageFileURL: imageFileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            backingScaleFactor: capturedScaleFactor
        )
    }

    private static func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            ) { cgImage, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let cgImage else {
                    continuation.resume(throwing: LocalScreenCaptureError.noDisplaysCaptured)
                    return
                }

                continuation.resume(returning: cgImage)
            }
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayIDNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(displayIDNumber.uint32Value)
    }

    private static func writePNGImage(
        _ cgImage: CGImage,
        to imageFileURL: URL
    ) throws {
        guard let imageDestination = CGImageDestinationCreateWithURL(
            imageFileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LocalScreenCaptureError.cannotCreateImageDestination(imageFileURL.path)
        }

        CGImageDestinationAddImage(imageDestination, cgImage, nil)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw LocalScreenCaptureError.cannotFinalizeImage(imageFileURL.path)
        }
    }
}
