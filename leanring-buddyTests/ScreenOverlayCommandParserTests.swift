//
//  ScreenOverlayCommandParserTests.swift
//  leanring-buddyTests
//

import CoreGraphics
import Testing
@testable import leanring_buddy

struct ScreenOverlayCommandParserTests {

    @Test func parserExtractsPointRectangleAndLineCommands() {
        let parseResult = ScreenOverlayCommandParser.parseCommands(
            in: """
            Look here.
            [POINT:10,20:save button:screen1]
            [RECT:30,40,120,60:dialog:screen2]
            [LINE:1,2,3,4:path]
            """
        )

        #expect(parseResult.shouldClear == false)
        #expect(parseResult.annotations.count == 3)
        #expect(parseResult.annotations[0] == ScreenOverlayDraftAnnotation(
            shape: .point(CGPoint(x: 10, y: 20)),
            label: "save button",
            screenNumber: 1
        ))
        #expect(parseResult.annotations[1] == ScreenOverlayDraftAnnotation(
            shape: .rectangle(CGRect(x: 30, y: 40, width: 120, height: 60)),
            label: "dialog",
            screenNumber: 2
        ))
        #expect(parseResult.annotations[2] == ScreenOverlayDraftAnnotation(
            shape: .line(CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)),
            label: "path",
            screenNumber: nil
        ))
    }

    @Test func parserHandlesClearAndPointNone() {
        let parseResult = ScreenOverlayCommandParser.parseCommands(
            in: "[CLEAR] [POINT:none]"
        )

        #expect(parseResult.shouldClear)
        #expect(parseResult.annotations.isEmpty)
    }
}
