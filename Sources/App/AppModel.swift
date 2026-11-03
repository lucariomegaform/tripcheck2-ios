// Holds the driver's settings, listens to the screen broadcast reader, and keeps the
// floating window up to date.

import Foundation
import Combine
import SwiftUI
import UIKit

final class AppModel: ObservableObject {
    @Published var settings: TripSettings {
        didSet {
            saveSettings()
            refreshOverlay()
        }
    }
    @Published private(set) var reader = ReaderState()
    @Published private(set) var sampleOffer: Offer? = nil
    /// When the screen broadcast reader was last heard from, and how ("shared folder" / "direct link").
    @Published private(set) var lastHeard: Date? = nil
    @Published private(set) var heardVia: String = ""
    /// True while the screen broadcast is on. The Start/Stop button follows this.
    @Published private(set) var reading = false

    let pip = PiPController()
    private let link = LoopbackReceiver()

    private var sampleUntil = Date.distantPast
    private var sampleIndex = 0
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(TripSettings.self, from: data) {
            settings = saved
        } else {
            settings = TripSettings()
        }
        reader = SharedChannel.read() ?? ReaderState()

        // Pass the floating window's on/off changes on to the screen.
        pip.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        listenToReader()

        // The direct link works even when signing left out the shared folder.
        link.onState = { [weak self] state in
            self?.receive(state, via: "direct link")
        }
        link.ensureRunning()
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.link.ensureRunning()
            self?.refresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refreshOverlay()
    }

    // MARK: state

    /// The reader is running: it checks in every 2 seconds while the broadcast is on, so
    /// 8 seconds of silence means the broadcast has stopped (even if the "stopped" message was lost).
    var isReading: Bool {
        reader.broadcasting && Date().timeIntervalSince(reader.updated) < 8
    }

    /// Keeps the button and floating window in step with the broadcast.
    private func updateReading() {
        let now = isReading
        guard now != reading else { return }
        reading = now
        if !now {
            // Broadcast ended (Stop Broadcast on Apple's sheet, or the red pill): close the window.
            pip.stop()
        }
    }

    var overlayMode: OverlayMode {
        if let sample = sampleOffer, Date() < sampleUntil {
            return .offer(sample, evaluate(sample, settings))
        }
        guard isReading else { return .notReading }
        if let offer = reader.offer {
            return .offer(offer, evaluate(offer, settings))
        }
        return reader.unreadable ? .unreadable : .ready
    }

    // MARK: actions

    /// One tap: start the floating window and open Apple's Screen Broadcast sheet.
    func startReading() {
        pip.start()
        BroadcastPicker.shared.open()
    }

    /// Apple's sheet is the only way to stop a broadcast from inside an app; it shows "Stop Broadcast".
    func stopReading() {
        BroadcastPicker.shared.open()
    }

    /// Shows a sample offer in the floating window for 15 seconds, to try it without a real offer.
    func showSample() {
        let samples = Offer.samples
        sampleOffer = samples[sampleIndex % samples.count]
        sampleIndex += 1
        sampleUntil = Date().addingTimeInterval(15)
        refreshOverlay()
    }

    func resetMinimums() {
        settings.resetMinimums()
    }

    // MARK: plumbing

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
    }

    private func refreshOverlay() {
        pip.show(OverlayRenderer.render(overlayMode, settings: settings))
    }

    private func receive(_ state: ReaderState, via: String) {
        lastHeard = Date()
        heardVia = via
        if state != reader {
            reader = state
        }
        updateReading()
        refreshOverlay()
    }

    fileprivate func refresh() {
        if let latest = SharedChannel.read(), latest != reader, latest.updated >= reader.updated {
            receive(latest, via: "shared folder")
        }
        if sampleOffer != nil && Date() >= sampleUntil {
            sampleOffer = nil
        }
        updateReading()
        refreshOverlay()
    }

    /// The reader rings a system-wide bell whenever it sees something new.
    private func listenToReader() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { model.refresh() }
            },
            SharedChannel.notificationName as CFString, nil, .deliverImmediately)
    }
}
