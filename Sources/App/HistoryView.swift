// The History tab: every offer read while reading offers was on, newest first, with what
// the card showed and the analysis using the current settings.

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var history: HistoryStore

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if history.records.isEmpty {
                    Text("No offers recorded yet. Offers are saved here while reading offers is on, and each time you use the screenshot shortcut.")
                        .foregroundColor(.secondary)
                } else {
                    Section {
                        ForEach(history.records) { record in
                            row(record)
                        }
                        .onDelete { history.delete(at: $0) }
                    } header: {
                        Text("\(history.records.count) offers")
                    } footer: {
                        Text("Saved exactly as shown on each offer card, without the pickup and drop-off addresses. The analysis uses your current minimums, so it updates if you change them. Swipe left on an offer to delete it.")
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if let url = history.exportURL, !history.records.isEmpty {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func row(_ r: OfferRecord) -> some View {
        let offer = r.offer
        // History shows plain green / red against the minimums (no nearly ranges or fare range).
        let v = evaluate(offer, model.settings.strict)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(Color(OverlayRenderer.fillColour(v.overall)))
                    .frame(width: 10, height: 10)
                Text(HistoryView.dateFormat.string(from: r.seenAt))
                    .font(.subheadline.bold())
                Spacer()
                Text(money(r.fare))
                    .font(.headline)
            }
            // What the card showed
            HStack(spacing: 6) {
                if r.types.isEmpty {
                    Text("Type not read")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(r.types, id: \.self) { type in
                    Text(type)
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                Text(r.exclusive ? "exclusive" : "trip radar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Label(r.sourceText, systemImage: r.source == "shortcut" ? "hand.tap" : (r.source == "both" ? "checkmark.seal" : "dot.radiowaves.left.and.right"))
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(details(r))
                .font(.footnote)
                .foregroundColor(.secondary)
            // The analysis with the current settings
            HStack(spacing: 12) {
                chip(v.perMile.map { money($0) + "/mile" } ?? "?/mile", v.mile)
                chip(v.perHour.map { money($0) + "/hour" } ?? "?/hour", v.hour)
                chip("rating " + (v.rating.map { String(format: "%.2f", $0) } ?? "new"), v.ratingCheck)
            }
            if abs(v.fareUsed - r.fare) > 0.004 {
                Text("Worked out on \(money(v.fareUsed))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            locationLine(r)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func locationLine(_ r: OfferRecord) -> some View {
        if let lat = r.latitude, let lon = r.longitude,
           let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Offer") {
            Link(destination: url) {
                Label(String(format: "%.5f, %.5f", lat, lon), systemImage: "mappin.and.ellipse")
                    .font(.caption)
            }
        } else {
            Text("Location not recorded")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func chip(_ text: String, _ check: Check) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(Color(OverlayRenderer.textColour(check)))
    }

    private func details(_ r: OfferRecord) -> String {
        let rating = r.rating.map { String(format: "%.2f", $0) } ?? "new"
        return "Pickup \(Int(r.pickupMinutes)) min, " + String(format: "%.1f", r.pickupMiles) + " mi · journey \(Int(r.tripMinutes)) min, "
            + String(format: "%.1f", r.tripMiles) + " mi · rating " + rating
    }

    private func money(_ v: Double) -> String {
        String(format: "£%.2f", v)
    }
}
