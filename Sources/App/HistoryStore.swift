// The saved offers. Each one is stored exactly as it appeared on the card (not affected by
// the VAT, holiday pay or pickup settings); the analysis is worked out from the current
// settings whenever it's shown. Saved as a file on the phone, newest first.

import Foundation
import CoreLocation

struct OfferRecord: Codable, Identifiable, Equatable {
    var id: String
    /// When the offer appeared.
    var seenAt: Date
    var fare: Double
    var pickupMinutes: Double
    var pickupMiles: Double
    var tripMinutes: Double
    var tripMiles: Double
    var rating: Double?
    /// "UberX", "Comfort", "Uber Pet"... from the top left of the card.
    var rideType: String
    /// Exclusive offer (Confirm button) or trip radar (Match button).
    var exclusive: Bool
    /// "£0.63 est. holiday entitlement included"
    var holiday: Double?
    var pickupPlace: String
    var dropPlace: String
    /// Where the driver was when the offer appeared.
    var latitude: Double?
    var longitude: Double?
    /// How precise that location is, in metres.
    var locationAccuracy: Double?

    init(_ seen: SeenOffer, location: CLLocation?) {
        let o = seen.offer
        id = seen.id
        seenAt = seen.seenAt
        fare = o.fare
        pickupMinutes = o.pickupMinutes
        pickupMiles = o.pickupMiles
        tripMinutes = o.tripMinutes
        tripMiles = o.tripMiles
        rating = o.rating
        rideType = o.rideType
        exclusive = o.exclusive
        holiday = o.holiday
        pickupPlace = o.pickupPlace
        dropPlace = o.dropPlace
        latitude = location?.coordinate.latitude
        longitude = location?.coordinate.longitude
        locationAccuracy = location?.horizontalAccuracy
    }

    /// Back to an offer, so the same rules can analyse it.
    var offer: Offer {
        Offer(rideType: rideType, exclusive: exclusive, fare: fare, holiday: holiday,
              pickupMinutes: pickupMinutes, pickupMiles: pickupMiles,
              tripMinutes: tripMinutes, tripMiles: tripMiles, rating: rating,
              pickupPlace: pickupPlace, dropPlace: dropPlace)
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [OfferRecord] = []
    /// A spreadsheet copy of the history, refreshed on every save, for the Export button.
    @Published private(set) var exportURL: URL?

    private let fileURL: URL = {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("offer-history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([OfferRecord].self, from: data) {
            records = saved
        }
        writeExport()
    }

    /// Adds offers the reader has seen that aren't saved yet, and fills in ratings found later.
    func merge(_ seen: [SeenOffer], location: (Date) -> CLLocation?) {
        var changed = false
        for s in seen {
            if let i = records.firstIndex(where: { $0.id == s.id }) {
                if records[i].rating == nil, let r = s.offer.rating {
                    records[i].rating = r
                    changed = true
                }
            } else {
                records.append(OfferRecord(s, location: location(s.seenAt)))
                changed = true
            }
        }
        if changed {
            records.sort { $0.seenAt > $1.seenAt }
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) where i < records.count {
            records.remove(at: i)
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
        writeExport()
    }

    // MARK: export

    private func writeExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TripCheck offers.csv")
        var lines = ["Date,Time,Offer £,Minutes to pickup,Miles to pickup,Journey minutes,Journey miles,Passenger rating,Trip type,Exclusive,Holiday pay £,Pickup,Drop-off,Latitude,Longitude,Location accuracy m"]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func number(_ v: Double?, _ format: String) -> String { v.map { String(format: format, $0) } ?? "" }
        for r in records {
            lines.append([
                day.string(from: r.seenAt), time.string(from: r.seenAt),
                String(format: "%.2f", r.fare),
                String(format: "%.0f", r.pickupMinutes), String(format: "%.1f", r.pickupMiles),
                String(format: "%.0f", r.tripMinutes), String(format: "%.1f", r.tripMiles),
                number(r.rating, "%.2f"), field(r.rideType), r.exclusive ? "yes" : "no",
                number(r.holiday, "%.2f"), field(r.pickupPlace), field(r.dropPlace),
                number(r.latitude, "%.6f"), number(r.longitude, "%.6f"), number(r.locationAccuracy, "%.0f"),
            ].joined(separator: ","))
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
