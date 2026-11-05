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
                    Text("No offers recorded yet. Offers are saved here while reading offers is on.")
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
                        Text("Saved exactly as shown on each offer card. The analysis uses your current settings, so it updates if you change them. Swipe left on an offer to delete it.")
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
        let v = evaluate(offer, model.settings)
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
            Text(r.rideType + (r.exclusive ? " · exclusive" : " · trip radar"))
                .font(.footnote)
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
