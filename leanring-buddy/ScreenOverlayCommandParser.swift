//
//  ScreenOverlayCommandParser.swift
//  leanring-buddy
//

import CoreGraphics
import Foundation

struct ScreenOverlayCommandParseResult: Equatable {
    let annotations: [ScreenOverlayDraftAnnotation]
    let shouldClear: Bool
}

struct ScreenOverlayDraftAnnotation: Equatable {
    let shape: ScreenOverlayAnnotationShape
    let label: String
    let screenNumber: Int?
}

enum ScreenOverlayCommandParser {
    static func parseCommands(in text: String) -> ScreenOverlayCommandParseResult {
        guard let regularExpression = try? NSRegularExpression(pattern: "\\[([^\\[\\]]+)\\]") else {
            return ScreenOverlayCommandParseResult(annotations: [], shouldClear: false)
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regularExpression.matches(in: text, range: fullRange)
        var annotations: [ScreenOverlayDraftAnnotation] = []
        var shouldClear = false

        for match in matches {
            guard match.numberOfRanges == 2,
                  let contentRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let commandContent = String(text[contentRange])
            let parsedCommand = parseCommandContent(commandContent)
            shouldClear = shouldClear || parsedCommand.shouldClear

            if let annotation = parsedCommand.annotation {
                annotations.append(annotation)
            }
        }

        return ScreenOverlayCommandParseResult(
            annotations: annotations,
            shouldClear: shouldClear
        )
    }

    private static func parseCommandContent(
        _ commandContent: String
    ) -> (annotation: ScreenOverlayDraftAnnotation?, shouldClear: Bool) {
        let commandParts = commandContent.split(
            separator: ":",
            omittingEmptySubsequences: false
        ).map(String.init)

        guard let commandName = commandParts.first?.uppercased() else {
            return (nil, false)
        }

        if commandName == "CLEAR" {
            return (nil, true)
        }

        if commandName == "POINT",
           commandParts.dropFirst().first?.lowercased() == "none" {
            return (nil, false)
        }

        guard commandParts.count >= 3 else {
            return (nil, false)
        }

        let coordinateValues = parseCoordinateValues(commandParts[1])
        let screenNumber = parseScreenNumber(from: commandParts.last)
        let labelEndIndex = screenNumber == nil ? commandParts.count : commandParts.count - 1
        let label = commandParts[2..<labelEndIndex]
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty else {
            return (nil, false)
        }

        switch commandName {
        case "POINT":
            guard coordinateValues.count == 2 else {
                return (nil, false)
            }

            return (
                ScreenOverlayDraftAnnotation(
                    shape: .point(
                        CGPoint(
                            x: coordinateValues[0],
                            y: coordinateValues[1]
                        )
                    ),
                    label: label,
                    screenNumber: screenNumber
                ),
                false
            )
        case "RECT":
            guard coordinateValues.count == 4 else {
                return (nil, false)
            }

            return (
                ScreenOverlayDraftAnnotation(
                    shape: .rectangle(
                        CGRect(
                            x: coordinateValues[0],
                            y: coordinateValues[1],
                            width: coordinateValues[2],
                            height: coordinateValues[3]
                        )
                    ),
                    label: label,
                    screenNumber: screenNumber
                ),
                false
            )
        case "LINE":
            guard coordinateValues.count == 4 else {
                return (nil, false)
            }

            return (
                ScreenOverlayDraftAnnotation(
                    shape: .line(
                        CGPoint(
                            x: coordinateValues[0],
                            y: coordinateValues[1]
                        ),
                        CGPoint(
                            x: coordinateValues[2],
                            y: coordinateValues[3]
                        )
                    ),
                    label: label,
                    screenNumber: screenNumber
                ),
                false
            )
        default:
            return (nil, false)
        }
    }

    private static func parseCoordinateValues(_ coordinateText: String) -> [CGFloat] {
        coordinateText
            .split(separator: ",")
            .compactMap { coordinatePart in
                Double(coordinatePart.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .map { coordinateValue in
                CGFloat(coordinateValue)
            }
    }

    private static func parseScreenNumber(from possibleScreenText: String?) -> Int? {
        guard let possibleScreenText else {
            return nil
        }

        let trimmedText = possibleScreenText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard trimmedText.hasPrefix("screen") else {
            return nil
        }

        let numberText = trimmedText.dropFirst("screen".count)
        guard let screenNumber = Int(numberText),
              screenNumber > 0 else {
            return nil
        }

        return screenNumber
    }
}
