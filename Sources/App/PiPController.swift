// The floating window. iPhones only let one app float over another as picture-in-picture
// "video", so TripCheck plays its overlay pictures as a live video in a PiP window.

import AVKit
import AVFoundation
import CoreMedia
import UIKit

final class PiPController: NSObject, ObservableObject {
    /// The video surface. It must be on screen in the app for picture-in-picture to start.
    let displayLayer = AVSampleBufferDisplayLayer()

    @Published private(set) var isActive = false
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var startWhenPossible = false
    /// True while reading offers is on. When false, the window is kept closed.
    private(set) var wantsOpen = false

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect

        // Picture-in-picture needs a "playback" audio session. Mixing means the driver's
        // music and navigation voice carry on as normal; TripCheck makes no sound.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        guard isSupported else { return }
        makeController()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func makeController() {
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        // Floats by itself when the driver switches to the driver app, but only while reading
        // offers is on (see setAutoStart), so it never pops up saying "Not reading".
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip

        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] pip, _ in
            guard let self = self, pip.isPictureInPicturePossible, self.startWhenPossible, self.wantsOpen else { return }
            self.startWhenPossible = false
            DispatchQueue.main.async { pip.startPictureInPicture() }
        }
    }

    func start() {
        wantsOpen = true
        guard let pip = controller else { return }
        if pip.isPictureInPictureActive { return }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            startWhenPossible = true
        }
    }

    /// Closes the window, and keeps making sure it's closed.
    ///
    /// Why the retries: after Stop Broadcast, Apple's broadcast sheet stays on screen over
    /// TripCheck until it's dismissed, and while it's up iOS ignores requests to close the
    /// window. So TripCheck asks again over the next few seconds, again as soon as TripCheck
    /// is back on screen, and if the window still won't close, it replaces the window's
    /// controller, which takes the window away.
    func stop() {
        wantsOpen = false
        startWhenPossible = false
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        enforceClosed()
        for delay in [0.4, 1.0, 2.0, 4.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.enforceClosed()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            self?.enforceClosed(hard: true)
        }
    }

    /// Lets the window float by itself when the driver leaves TripCheck (only while reading).
    func setAutoStart(_ on: Bool) {
        if on { wantsOpen = true }
        controller?.canStartPictureInPictureAutomaticallyFromInline = on
    }

    /// TripCheck came back on screen: if the window should be closed, close it now.
    @objc private func appBecameActive() {
        guard !wantsOpen else { return }
        enforceClosed()
        // Apple's sheet may still be sliding away; ask again, then replace the window if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.enforceClosed() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.enforceClosed(hard: true) }
    }

    private func enforceClosed(hard: Bool = false) {
        guard !wantsOpen, let pip = controller else { return }
        guard pip.isPictureInPictureActive || isActive else { return }
        if hard {
            // Last resort: a new controller. The old window goes away with the old controller.
            closeAttempts += 1
            pip.delegate = nil
            pip.stopPictureInPicture()
            controller = nil
            possibleObservation = nil
            DispatchQueue.main.async { self.isActive = false }
            makeController()
            return
        }
        closeAttempts += 1
        pip.stopPictureInPicture()
    }

    /// How many times TripCheck has had to ask the window to close (for testing).
    private(set) var closeAttempts = 0

    /// Shows a new overlay picture in the window (and in the in-app preview).
    func show(_ image: CGImage?) {
        guard let image = image, let sample = PiPController.sampleBuffer(from: image) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sample)
    }

    /// Wraps a picture as one frame of video.
    private static func sampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width
        let height = image.height
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pixelBufferOut: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatOut)
        guard let format = formatOut else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: format, sampleTiming: &timing,
                                                 sampleBufferOut: &sampleOut)
        guard let sample = sampleOut else { return nil }

        // Show each frame straight away rather than on a video clock.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isActive = true
            // Opened just as reading stopped: close it again.
            if !self.wantsOpen { self.enforceClosed() }
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }
}

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // A "live" stream with no end, so there's no progress bar.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
