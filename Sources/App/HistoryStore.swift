// The saved offers. Each one is stored exactly as it appeared on the card (not affected by
// the VAT, holiday pay or pickup settings); the analysis is worked out from the current
// settings whenever it's shown. Saved as a file on the phone, newest first.
//
// Pickup and drop-off addresses are not kept. Histories saved by older versions have
// their addresses removed the first time this version opens them.

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
    /// The trip types on the card: one or more of "UberX", "Electric", "Comfort", "Business",
    /// "Priority", "Teens", "Pet", "XL", "XXL", "Lux", "Assist".
    var types: [String]
    /// Exclusive offer (Confirm button) or trip radar (Match button).
    var exclusive: Bool
    /// "£0.63 est. holiday entitlement included"
    var holiday: Double?
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
        types = o.types
        exclusive = o.exclusive
        holiday = o.holiday
        setLocation(location)
    }

    mutating func setLocation(_ location: CLLocation?) {
        latitude = location?.coordinate.latitude
        longitude = location?.coordinate.longitude
        locationAccuracy = location?.horizontalAccuracy
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    private enum CodingKeys: String, CodingKey {
        case id, seenAt, fare, pickupMinutes, pickupMiles, tripMinutes, tripMiles, rating, types
        case exclusive, holiday, latitude, longitude, locationAccuracy
        case rideType   // older versions: one line of text, sometimes part of an address
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seenAt = try c.decode(Date.self, forKey: .seenAt)
        fare = try c.decode(Double.self, forKey: .fare)
        pickupMinutes = try c.decodeIfPresent(Double.self, forKey: .pickupMinutes) ?? 0
        pickupMiles = try c.decodeIfPresent(Double.self, forKey: .pickupMiles) ?? 0
        tripMinutes = try c.decodeIfPresent(Double.self, forKey: .tripMinutes) ?? 0
        tripMiles = try c.decodeIfPresent(Double.self, forKey: .tripMiles) ?? 0
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        if let saved = try c.decodeIfPresent([String].self, forKey: .types) {
            types = saved
        } else {
            // Keep only real trip types from the old text, dropping any address that crept in.
            let oldText = try c.decodeIfPresent(String.self, forKey: .rideType) ?? ""
            types = TripType.find(in: oldText)
        }
        exclusive = try c.decodeIfPresent(Bool.self, forKey: .exclusive) ?? false
        holiday = try c.decodeIfPresent(Double.self, forKey: .holiday)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        locationAccuracy = try c.decodeIfPresent(Double.self, forKey: .locationAccuracy)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(seenAt, forKey: .seenAt)
        try c.encode(fare, forKey: .fare)
        try c.encode(pickupMinutes, forKey: .pickupMinutes)
        try c.encode(pickupMiles, forKey: .pickupMiles)
        try c.encode(tripMinutes, forKey: .tripMinutes)
        try c.encode(tripMiles, forKey: .tripMiles)
        try c.encodeIfPresent(rating, forKey: .rating)
        try c.encode(types, forKey: .types)
        try c.encode(exclusive, forKey: .exclusive)
        try c.encodeIfPresent(holiday, forKey: .holiday)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
    }

    /// Back to an offer, so the same rules can analyse it.
    var offer: Offer {
        Offer(types: types, exclusive: exclusive, fare: fare, holiday: holiday,
              pickupMinutes: pickupMinutes, pickupMiles: pickupMiles,
              tripMinutes: tripMinutes, tripMiles: tripMiles, rating: rating)
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [OfferRecord] = []
    /// A spreadsheet copy of the history, refreshed on every save, for the Export button.
    @Published private(set) var exportURL: URL?

    /// Offers seen again later with exactly the same numbers (for example a screenshot of an
    /// offer opened in Photos) aren't saved twice. This is how far back that check looks.
    private let repeatWindow: TimeInterval = 30 * 24 * 3600

    private let fileURL: URL = {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("offer-history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([OfferRecord].self, from: data) {
            records = saved
            // Rewrite older files so any saved addresses are removed from the phone.
            if let text = String(data: data, encoding: .utf8),
               text.contains("pickupPlace") || text.contains("dropPlace") || text.contains("rideType") {
                save()
                return
            }
        }
        writeExport()
    }

    /// Adds offers the reader has seen that aren't saved yet, fills in ratings and trip types
    /// found later, and fills in a location for any recent offer that's still missing one.
    func merge(_ seen: [SeenOffer], location: (Date) -> CLLocation?) {
        var changed = false
        for s in seen {
            if let i = records.firstIndex(where: { $0.id == s.id }) {
                if records[i].rating == nil, let r = s.offer.rating {
                    records[i].rating = r
                    changed = true
                }
                if records[i].types.isEmpty && !s.offer.types.isEmpty {
                    records[i].types = s.offer.types
                    changed = true
                }
                if !records[i].hasLocation, let fix = location(s.seenAt) {
                    records[i].setLocation(fix)
                    changed = true
                }
            } else if isRepeat(s) {
                continue   // the same offer shown again (a screenshot, or the same card re-read later)
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

    /// True if an offer with exactly the same fare, pickup and trip was saved earlier.
    private func isRepeat(_ s: SeenOffer) -> Bool {
        records.contains { r in
            r.seenAt < s.seenAt.addingTimeInterval(-60)
                && s.seenAt.timeIntervalSince(r.seenAt) < repeatWindow
                && r.offer.sameNumbers(as: s.offer)
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

    /// One row per offer. The trip types are listed together ("Business + Comfort + Electric")
    /// and also given one yes/no column each, so a spreadsheet can count or filter by any type.
    private func writeExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TripCheck offers.csv")
        let typeColumns = TripType.all.map { "Type: " + $0 }.joined(separator: ",")
        var lines = ["Date,Time,Offer £,Minutes to pickup,Miles to pickup,Journey minutes,Journey miles,Passenger rating,Trip types,"
                     + typeColumns + ",Exclusive,Holiday pay £,Latitude,Longitude,Location accuracy m"]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func number(_ v: Double?, _ format: String) -> String { v.map { String(format: format, $0) } ?? "" }
        for r in records {
            var row = [
                day.string(from: r.seenAt), time.string(from: r.seenAt),
                String(format: "%.2f", r.fare),
                String(format: "%.0f", r.pickupMinutes), String(format: "%.1f", r.pickupMiles),
                String(format: "%.0f", r.tripMinutes), String(format: "%.1f", r.tripMiles),
                number(r.rating, "%.2f"), field(r.types.joined(separator: " + ")),
            ]
            row += TripType.all.map { r.types.contains($0) ? "yes" : "" }
            row += [
                r.exclusive ? "yes" : "no", number(r.holiday, "%.2f"),
                number(r.latitude, "%.6f"), number(r.longitude, "%.6f"), number(r.locationAccuracy, "%.0f"),
            ]
            lines.append(row.joined(separator: ","))
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
