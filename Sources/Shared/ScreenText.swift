// Reads the words on a picture of the screen with Apple's on-device text recognition.
// Used by both ways of capturing an offer: the screen broadcast reader (live video of the
// screen) and the screenshot shortcut (one picture when the driver taps the button).
// Nothing leaves the phone.

import Foundation
import Vision
import CoreVideo
import CoreGraphics
import ImageIO

enum ScreenText {
    /// Lower part of the screen to read (the offer card sits at the bottom).
    static let readArea = CGRect(x: 0, y: 0, width: 1, height: 0.65)

    /// Words from one frame of the screen broadcast.
    static func read(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> String {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return perform(handler)
    }

    /// Words from a screenshot.
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) -> String {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        return perform(handler)
    }

    private static func perform(_ handler: VNImageRequestHandler) -> String {
        let request = VNRecognizeTextRequest()
        // If the broadcast reader ever stops on its own (iOS limits it to about 50 MB),
        // switch this from .accurate to .fast.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = readArea
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return linesInReadingOrder(request.results ?? [])
    }

    /// Puts the recognised bits of text back into lines, top to bottom and left to right,
    /// so "4 min • 0.9 mi" stays on one line even if it was recognised in pieces.
    static func linesInReadingOrder(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Piece {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
            let height: CGFloat
        }
        let pieces: [Piece] = observations.compactMap { (o: VNRecognizedTextObservation) -> Piece? in
            guard let best = o.topCandidates(1).first else { return nil }
            return Piece(text: best.string, midY: o.boundingBox.midY, minX: o.boundingBox.minX, height: o.boundingBox.height)
        }.sorted { $0.midY > $1.midY }   // Vision measures from the bottom, so larger is higher up

        var rows: [[Piece]] = []
        for piece in pieces {
            if let first = rows.last?.first, abs(first.midY - piece.midY) < max(first.height, piece.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows
            .map { row in row.sorted { $0.minX < $1.minX }.map { $0.text }.joined(separator: " ") }
            .joined(separator: "\n")
    }
}
