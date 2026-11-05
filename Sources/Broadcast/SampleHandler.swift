// The screen broadcast reader. iOS runs this as a separate small process while the
// driver's screen broadcast is on, and hands it pictures of the screen. About twice a
// second it reads the words in the lower part of the screen (where the offer card
// appears) with Apple's on-device text recognition, and tells the app what it found.
// Nothing leaves the phone.
//
// Memory note: iOS limits broadcast readers to about 50 MB. If the reader stops on its
// own, switch `recognitionLevel` below from .accurate to .fast.

import ReplayKit
import Vision
import ImageIO
import CoreMedia

@objc(SampleHandler)
class SampleHandler: RPBroadcastSampleHandler {
    private var state = ReaderState()
    private var lastRead: CFAbsoluteTime = 0
    private var lastWrite: CFAbsoluteTime = 0
    private var missedReads = 0
    /// The direct link to the app, used as well as the shared folder (which may be missing).
    private let link = LoopbackSender()

    /// Seconds between reads.
    private let readInterval: CFAbsoluteTime = 0.5
    /// Lower part of the screen to read (the offer card sits at the bottom).
    private let readArea = CGRect(x: 0, y: 0, width: 1, height: 0.65)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        state = ReaderState(broadcasting: true, offer: nil, unreadable: false, updated: Date())
        publish()
    }

    override func broadcastFinished() {
        state = ReaderState(broadcasting: false, offer: nil, unreadable: false, updated: Date())
        publish()
        link.close()   // waits a moment so the "stopped" message gets through first
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRead >= readInterval else { return }
        lastRead = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var orientation = CGImagePropertyOrientation.up
        if let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let o = CGImagePropertyOrientation(rawValue: value.uint32Value) {
            orientation = o
        }

        let text = readText(pixelBuffer, orientation: orientation)
        update(with: text, now: now)
    }

    private func readText(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = readArea
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return SampleHandler.linesInReadingOrder(request.results ?? [])
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

    private func update(with text: String, now: CFAbsoluteTime) {
        var next = state
        next.broadcasting = true
        if var offer = OfferReader.parse(text) {
            // Keep a rating read moments ago if this read of the same card missed it.
            if offer.rating == nil, let previous = state.offer, previous.rating != nil,
               previous.fare == offer.fare, previous.tripMiles == offer.tripMiles {
                offer.rating = previous.rating
            }
            next.offer = offer
            next.unreadable = false
            next.rawText = text
            missedReads = 0
            remember(offer, in: &next)
        } else {
            missedReads += 1
            if OfferReader.looksLikeOffer(text) {
                // An offer card is showing but couldn't be read fully. Keep a good read of the
                // same card if there was one; otherwise say so rather than guess.
                if state.offer == nil {
                    next.unreadable = true
                    next.rawText = text
                }
            } else if missedReads >= 2 {
                next.offer = nil
                next.unreadable = false
            }
        }

        let changed = next.offer != state.offer || next.unreadable != state.unreadable
            || next.broadcasting != state.broadcasting || next.recent != state.recent
        state = next
        // Write when something changed, and every few seconds anyway so the app knows the reader is alive.
        if changed || now - lastWrite > 2 {
            publish()
        }
    }

    /// Adds the offer to the list of offers seen, or fills in a rating a later read found.
    private func remember(_ offer: Offer, in next: inout ReaderState) {
        var recent = next.recent ?? []
        let now = Date()
        if let last = recent.last, last.isSameCard(as: offer, at: now) {
            if last.offer.rating == nil && offer.rating != nil {
                recent[recent.count - 1].offer.rating = offer.rating
            }
        } else {
            recent.append(SeenOffer(id: UUID().uuidString, seenAt: now, offer: offer))
            if recent.count > 30 { recent.removeFirst(recent.count - 30) }
        }
        next.recent = recent
    }

    private func publish() {
        state.updated = Date()
        lastWrite = CFAbsoluteTimeGetCurrent()
        SharedChannel.write(state)   // does nothing if there's no shared folder
        link.send(state)
    }
}
