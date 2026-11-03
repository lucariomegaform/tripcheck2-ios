// Holds the driver's settings, listens to the screen broadcast reader, and keeps the
// floating window up to date.

import Foundation
import Combine
import SwiftUI

final class AppModel: ObservableObject {
    @Published var settings: TripSettings {
        didSet {
            saveSettings()
            refreshOverlay()
        }
    }
    @Published private(set) var reader = ReaderState()
    @Published private(set) var sampleOffer: Offer? = nil

    let pip = PiPController()

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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refreshOverlay()
    }

    // MARK: state

    /// The reader is running (it checks in every few seconds while the broadcast is on).
    var isReading: Bool {
        reader.broadcasting && Date().timeIntervalSince(reader.updated) < 15
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
        pip.show(OverlayRenderer.render(overlayMode, compact: settings.compactOverlay))
    }

    fileprivate func refresh() {
        if let latest = SharedChannel.read(), latest != reader {
            reader = latest
        }
        if sampleOffer != nil && Date() >= sampleUntil {
            sampleOffer = nil
        }
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
