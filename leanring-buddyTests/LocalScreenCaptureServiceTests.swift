//
//  LocalScreenCaptureServiceTests.swift
//  leanring-buddyTests
//

import Foundation
import Testing
@testable import leanring_buddy

struct LocalScreenCaptureServiceTests {

    @Test func screenCapturePromptDescriptionIncludesImageAndCoordinateScale() {
        let capture = LocalScreenCapture(
            screenNumber: 1,
            imageFileURL: URL(fileURLWithPath: "/private/tmp/screen1.png"),
            pixelWidth: 3024,
            pixelHeight: 1964,
            pointWidth: 1512,
            pointHeight: 982,
            backingScaleFactor: 2
        )

        #expect(
            capture.promptDescription ==
                "screen1: attached image screen1.png, 3024x1964 pixels, 1512x982 screen points, scale 2.00"
        )
    }
}
