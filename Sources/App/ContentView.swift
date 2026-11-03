import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                overlaySection
                if case .offer(let offer, let verdict) = model.overlayMode {
                    offerSection(offer, verdict)
                }
                minimumsSection
                windowSection
                helpSection
            }
            .navigationTitle("TripCheck")
            .background(
                BroadcastPickerHost()
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
            )
        }
    }

    // MARK: sections

    private var overlaySection: some View {
        Section {
            OverlayPreview(layer: model.pip.displayLayer)
                .aspectRatio(model.settings.compactOverlay ? 3 : 1.5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Button {
                if model.isReading { model.stopReading() } else { model.startReading() }
            } label: {
                Text(model.isReading ? "Stop reading offers" : "Start reading offers")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isReading ? .red : .green)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Text(statusText)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(connectionText)
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text("Floating result window")
        }
    }

    private var statusText: String {
        var parts: [String] = []
        parts.append(model.isReading ? "Reading offers." : "Not reading offers.")
        if !model.pip.isSupported {
            parts.append("This iPhone doesn't support picture-in-picture.")
        } else {
            parts.append(model.pip.isActive ? "Floating window on." : "The window floats when you switch to the driver app.")
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
            resultRow("Per minute", v.perMinute.map { money($0) } ?? "?", minimum: money(model.settings.minPerMinute), v.minute)
            resultRow("Rider rating", v.rating.map { String(format: "%.2f", $0) } ?? "New rider",
                      minimum: String(format: "%.2f", model.settings.minRating), v.ratingCheck)
            Text("\(money(v.fareUsed)) · pickup \(Int(o.pickupMinutes)) min, \(String(format: "%.1f", o.pickupMiles)) mi · trip \(Int(o.tripMinutes)) min, \(String(format: "%.1f", o.tripMiles)) mi")
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text(o.exclusive ? "Exclusive offer" : "Trip radar offer")
        }
    }

    private var minimumsSection: some View {
        Section {
            Stepper(value: $model.settings.minPerMile, in: 0.5...3.0, step: 0.01) {
                LabeledContent("Pay per mile", value: money(model.settings.minPerMile))
            }
            Stepper(value: $model.settings.minPerMinute, in: 0.1...1.5, step: 0.01) {
                LabeledContent("Pay per minute", value: money(model.settings.minPerMinute))
            }
            Stepper(value: $model.settings.minRating, in: 4.0...5.0, step: 0.01) {
                LabeledContent("Passenger rating", value: String(format: "%.2f", model.settings.minRating))
            }
            Toggle("Count the drive to the pickup in the miles", isOn: $model.settings.includePickupMiles)
            Toggle("New riders (no rating) meet the rating minimum", isOn: $model.settings.acceptUnrated)
            Toggle("Leave holiday pay out of the fare", isOn: $model.settings.excludeHolidayPay)
            Button("Reset to £1.20, £0.42 and 4.70") { model.resetMinimums() }
        } header: {
            Text("Your minimums")
        } footer: {
            Text("Pay per minute includes the drive to the pickup. Changes are saved straight away.")
        }
    }

    private var windowSection: some View {
        Section {
            Toggle("Compact window (verdict and three dots)", isOn: $model.settings.compactOverlay)
            Button("Show a sample offer") { model.showSample() }
        } header: {
            Text("Window")
        } footer: {
            Text("Drag the floating window to any corner. Pinch it to resize it. Swipe it to the side of the screen to tuck it away.")
        }
    }

    private var helpSection: some View {
        Section {
            Text("1. Tap Start reading offers, then Start Broadcast on the iPhone's sheet.")
            Text("2. Switch to the driver app. The TripCheck window floats on top.")
            Text("3. When an offer appears, the window shows green (meets your minimum), red (below it) or amber (couldn't tell).")
            Text("TripCheck only reads the screen on this phone. It never logs in to your driver account and nothing is uploaded.")
                .foregroundColor(.secondary)
        } header: {
            Text("How to use")
        }
        .font(.footnote)
    }

    // MARK: helpers

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
