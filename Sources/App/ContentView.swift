import SwiftUI
import AVFoundation
import UIKit
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            mainTab
                .tabItem { Label("TripCheck", systemImage: "car.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .background(
            BroadcastPickerHost()
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .allowsHitTesting(false)
        )
    }

    private var mainTab: some View {
        NavigationStack {
            Form {
                overlaySection
                if case .offer(let offer, let verdict) = model.overlayMode {
                    offerSection(offer, verdict)
                }
                minimumsSection
                windowSection
                shortcutSection
                helpSection
            }
            .navigationTitle("TripCheck")
        }
    }

    // MARK: sections

    private var overlaySection: some View {
        Section {
            OverlayPreview(layer: model.pip.displayLayer)
                .aspectRatio(OverlayRenderer.canvasSize(model.settings).width / OverlayRenderer.canvasSize(model.settings).height,
                             contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Button {
                if model.reading { model.stopReading() } else { model.startReading() }
            } label: {
                Text(model.reading ? "Stop reading offers" : "Start reading offers")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.reading ? .red : .green)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Text(statusText)
                .font(.footnote)
                .foregroundColor(.secondary)

            if model.pip.isActive && !model.reading {
                // Should close by itself; this is the fallback while testing.
                Button("Close the floating window") { model.closeFloatingWindow() }
                    .font(.footnote)
            }

            Text(connectionText)
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text("Floating result window")
        }
    }

    private var statusText: String {
        var parts: [String] = []
        if model.reading {
            parts.append("Reading offers.")
            if !model.pip.isSupported {
                parts.append("This iPhone doesn't support picture-in-picture.")
            } else {
                parts.append(model.pip.isActive ? "Floating window on." : "The window floats when you switch to the driver app.")
            }
        } else if model.waitingForBroadcast {
            parts.append("Tap Start Broadcast on the iPhone's sheet. The floating window opens once reading has started.")
        } else {
            parts.append("Not reading offers. The floating window opens when you start, and closes when you stop.")
        }
        return parts.joined(separator: " ")
    }

    /// Which way the screen reader's results reach the app (useful when testing).
    private var connectionText: String {
        let folder = SharedChannel.isConnected
            ? "Shared folder: on."
            : "Shared folder: not available with this signing, so TripCheck uses its direct link instead."
        guard let heard = model.lastHeard else {
            return folder + " Screen reader: not heard from yet. Tap Start reading offers to test it."
        }
        let seconds = max(0, Int(Date().timeIntervalSince(heard)))
        return folder + " Screen reader: last heard \(seconds) s ago, by \(model.heardVia)."
    }

    private func offerSection(_ o: Offer, _ v: Verdict) -> some View {
        Section {
            resultRow("Per mile", v.perMile.map { money($0) } ?? "?", minimum: money(model.settings.minPerMile), v.mile)
            resultRow("Per hour", v.perHour.map { money($0) } ?? "?", minimum: money(model.settings.minHourly), v.hour)
            resultRow("Rider rating", v.rating.map { String(format: "%.2f", $0) } ?? "New rider",
                      minimum: String(format: "%.2f", model.settings.minRating), v.ratingCheck)
            if !v.fareInRange {
                Label("Outside your fare range, so the floating window shows it faded.", systemImage: "circle.dashed")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Text(offerSummary(o, v))
                .font(.footnote)
                .foregroundColor(.secondary)
            if let raw = model.reader.rawText, !raw.isEmpty, model.sampleOffer == nil {
                DisclosureGroup("What TripCheck read") {
                    Text(raw)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy this text") { UIPasteboard.general.string = raw }
                }
                .font(.footnote)
            }
        } header: {
            Text(o.typeText + " · " + (o.exclusive ? "exclusive offer" : "trip radar offer"))
        }
    }

    private var minimumsSection: some View {
        Group {
            Section {
                sliderRow("Pay per mile", money(model.settings.minPerMile),
                          $model.settings.minPerMile, 0.50...3.00, step: 0.05)
                sliderRow("Nearly range", nearlyText(model.settings.perMileThreshold, money),
                          $model.settings.perMileThreshold, 0...0.50, step: 0.05, small: true)
            } header: {
                Text("Pay per mile")
            }

            Section {
                sliderRow("Hourly rate", money(model.settings.minHourly),
                          $model.settings.minHourly, 5...60, step: 0.50)
                sliderRow("Nearly range", nearlyText(model.settings.hourlyThreshold, money),
                          $model.settings.hourlyThreshold, 0...10, step: 0.50, small: true)
            } header: {
                Text("Hourly rate")
            }

            Section {
                sliderRow("Passenger rating", String(format: "%.2f", model.settings.minRating),
                          $model.settings.minRating, 4.00...5.00, step: 0.01)
                sliderRow("Nearly range", nearlyText(model.settings.ratingThreshold) { String(format: "%.2f", $0) },
                          $model.settings.ratingThreshold, 0...0.30, step: 0.01, small: true)
            } header: {
                Text("Passenger rating")
            } footer: {
                Text("Green: meets your minimum. Red: below it. With a nearly range, an offer that misses by no more than that shows amber instead. For example, an hourly rate of £25.00 with a £1.00 range shows £24.01 in amber. Off (the default) means the minimum is strict.")
            }

            Section {
                sliderRow("Minimum fare", money(model.settings.minFare), minFareBinding, 0...fareRangeTop, step: 0.50)
                sliderRow("Maximum fare", model.settings.hasNoMaximumFare ? "Unlimited" : money(model.settings.maxFare),
                          maxFareBinding, 0...fareRangeTop, step: 0.50)
            } header: {
                Text("Fare range")
            } footer: {
                Text("Offers priced outside this range show in faded colours in the floating window. Move the maximum all the way to £50 for no maximum. The price checked is the one the floating window shows (with VAT when the VAT setting is on).")
            }

            Section {
                Toggle("Count the drive to pickup in the analysis", isOn: $model.settings.includePickupMiles)
                Toggle("New riders (no rating) meet the rating minimum", isOn: $model.settings.acceptUnrated)
                Toggle("Leave holiday pay out of the fare", isOn: $model.settings.excludeHolidayPay)
                Toggle("Adjust figures for VAT flat rate scheme", isOn: $model.settings.vatFlatRate)
                Button("Reset to £1.20, £25.00 and 4.70") { model.resetMinimums() }
            } header: {
                Text("Working it out")
            } footer: {
                Text("Counting the drive to pickup adds its miles and minutes to both the per mile and the hourly figures. With the VAT flat rate scheme on, each offer is worked out as offer × 1.2 × 0.9 (a £10.00 offer counts as £10.80) and your minimums include VAT. Reset also clears the nearly ranges and the fare range. Changes are saved straight away.")
            }
        }
    }

    /// The minimum fare can't go above the maximum, and the other way round.
    private var minFareBinding: Binding<Double> {
        Binding(get: { model.settings.minFare }, set: { v in
            model.settings.minFare = v
            if model.settings.maxFare < v { model.settings.maxFare = v }
        })
    }

    private var maxFareBinding: Binding<Double> {
        Binding(get: { model.settings.maxFare }, set: { v in
            model.settings.maxFare = v
            if model.settings.minFare > v { model.settings.minFare = v }
        })
    }

    private func nearlyText(_ v: Double, _ format: (Double) -> String) -> String {
        v < 0.0001 ? "Off" : "within " + format(v)
    }

    private func sliderRow(_ title: String, _ value: String, _ binding: Binding<Double>,
                           _ range: ClosedRange<Double>, step: Double, small: Bool = false) -> some View {
        // Snap anything saved by older versions (which had finer steps) onto the slider.
        let snapped = Binding<Double>(
            get: { min(max(binding.wrappedValue, range.lowerBound), range.upperBound) },
            set: { binding.wrappedValue = ($0 / step).rounded() * step })
        return VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title) {
                Text(value)
                    .font(small ? .body : .headline)
                    .monospacedDigit()
                    .foregroundColor(small ? .secondary : .primary)
            }
            .font(small ? .subheadline : .body)
            Slider(value: snapped, in: range, step: step)
                .tint(small ? .orange : .green)
        }
        .padding(.vertical, 2)
    }

    private var windowSection: some View {
        Section {
            Toggle("Compact window (verdict, price and three dots)", isOn: $model.settings.compactOverlay)
            VStack(alignment: .leading) {
                LabeledContent("Text size", value: "\(Int((model.settings.overlayScale * 100).rounded()))%")
                Slider(value: $model.settings.overlayScale, in: 0.5...2.0, step: 0.05)
            }
            Button("Show a sample offer") { model.showSample() }
        } header: {
            Text("Window")
        } footer: {
            Text("Drag the floating window to any corner. Pinch it to resize it. Swipe it to the side of the screen to tuck it away.")
        }
    }

    /// The second way of capturing offers: a tap on the AssistiveTouch button runs a shortcut
    /// that takes a screenshot and hands it to TripCheck.
    private var shortcutSection: some View {
        Section {
            Toggle("Show shortcut results as a banner", isOn: $model.settings.shortcutBanner)
            sliderRow("Close the banner after", "\(Int(model.settings.shortcutPopupSeconds.rounded())) seconds",
                      $model.settings.shortcutPopupSeconds, 2...10, step: 1)
                .disabled(!model.settings.shortcutBanner)
            Text("The iPhone itself slides banners away after about 5 seconds, so longer times may not keep it on screen longer.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button(bannerAllowed ? "Banners allowed" : "Allow banners") {
                Task {
                    _ = await ShortcutBanner.requestPermission()
                    await refreshBannerPermission()
                }
            }
            .disabled(bannerAllowed)
            DisclosureGroup("Set up the shortcut (once)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Open the Shortcuts app and tap + to make a new shortcut. Name it TripCheck.")
                    Text("2. Add the action Take Screenshot.")
                    Text("3. Add the action Check Trip Offer (it's under TripCheck). It should say \"Check the trip offer in Screenshot\". If it doesn't, tap the blue word and choose Screenshot.")
                    Text("4. Tap the arrow on Check Trip Offer and turn Show When Run off. You then get the banner, which TripCheck closes after the time set above. With Show When Run on, you also get the coloured box, but iOS keeps that open until you tap Done: apps can't close it on a timer.")
                    Text("5. In Settings › Accessibility › Touch › AssistiveTouch, turn AssistiveTouch on. Under Custom Actions, set Single-Tap to the TripCheck shortcut. Remove the other menu items so one tap runs it straight away.")
                    Text("Instead of AssistiveTouch you can use Settings › Accessibility › Touch › Back Tap › Double Tap › TripCheck: tap the back of the phone twice.")
                        .foregroundColor(.secondary)
                }
                .font(.footnote)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Screenshot shortcut (alternative to reading offers)")
        } footer: {
            Text("When an offer appears, tap the AssistiveTouch button. TripCheck reads the screenshot on the phone, saves the offer in History (marked \"screenshot shortcut\") and shows the result at the top of the screen for a few seconds. The screenshot itself isn't saved. This works with or without Start reading offers, so you can compare the two.")
        }
        .task { await refreshBannerPermission() }
    }

    @State private var bannerAllowed = false

    @MainActor
    private func refreshBannerPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        bannerAllowed = status == .authorized || status == .provisional || status == .ephemeral
    }

    private var helpSection: some View {
        Section {
            Text("1. Tap Start reading offers, then Start Broadcast on the iPhone's sheet.")
            Text("2. Switch to the driver app. The TripCheck window floats on top.")
            Text("3. When an offer appears, the window shows green (meets your minimum), red (below it) or amber (nearly meets it, or couldn't tell). Offers outside your fare range are faded.")
            Text("4. To stop, tap Stop reading offers, then Stop Broadcast. The floating window closes by itself.")
            Text("TripCheck only reads the screen on this phone. It never logs in to your driver account and nothing is uploaded.")
                .foregroundColor(.secondary)
        } header: {
            Text("How to use")
        }
        .font(.footnote)
    }

    // MARK: helpers

    private func offerSummary(_ o: Offer, _ v: Verdict) -> String {
        var parts = ["Offer " + money(o.fare)]
        if model.settings.vatFlatRate || model.settings.excludeHolidayPay {
            parts[0] += ", worked out as " + money(v.fareUsed)
        }
        parts.append("pickup \(Int(o.pickupMinutes)) min, " + String(format: "%.1f", o.pickupMiles) + " mi")
        parts.append("trip \(Int(o.tripMinutes)) min, " + String(format: "%.1f", o.tripMiles) + " mi")
        return parts.joined(separator: " · ")
    }

    private func resultRow(_ title: String, _ value: String, minimum: String, _ check: Check) -> some View {
        HStack {
            Image(systemName: icon(check))
                .foregroundColor(Color(OverlayRenderer.fillColour(check)))
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(Color(OverlayRenderer.textColour(check)))
                Text("min \(minimum)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func icon(_ c: Check) -> String {
        switch c {
        case .pass: return "checkmark.circle.fill"
        case .near: return "minus.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "exclamationmark.circle.fill"
        }
    }

    private func money(_ v: Double) -> String {
        String(format: "£%.2f", v)
    }
}

/// Shows the floating window's video surface inside the app (Apple requires it to be on screen).
struct OverlayPreview: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .black
        view.hosted = layer
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}
}

final class LayerHostView: UIView {
    var hosted: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let hosted = hosted { layer.addSublayer(hosted) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hosted?.frame = bounds
    }
}
