// The driver's minimums, the trip offer, and the checking rules.
// Same rules as the desktop prototype.

import Foundation

/// VAT flat rate scheme: the platform pays 20% VAT on top, then 10% of the takings goes to
/// HMRC, so the money kept is the offer × 1.2 × 0.9 (a £10.00 offer is worth £10.80).
let vatFlatRateFactor = 1.2 * 0.9

struct TripSettings: Codable, Equatable {
    /// Minimum fare per mile, in pounds.
    var minPerMile: Double = 1.20
    /// Minimum hourly rate (time for the drive to the pickup + the trip), in pounds.
    var minHourly: Double = 25.00
    /// Minimum passenger rating.
    var minRating: Double = 4.70
    /// Count the drive to the pickup in the miles too.
    var includePickupMiles: Bool = false
    /// Treat riders with no rating yet as meeting the rating minimum.
    var acceptUnrated: Bool = false
    /// Take the "est. holiday entitlement included" amount off the fare first.
    var excludeHolidayPay: Bool = false
    /// Adjust figures for the VAT flat rate scheme (minimums then include VAT).
    var vatFlatRate: Bool = false
    /// Smaller floating window: just the verdict, the price and three dots.
    var compactOverlay: Bool = false
    /// Size of the floating window's content: 1.0 is the normal size.
    var overlayScale: Double = 1.0

    init() {}

    // Read older saved settings even if a newer version added or renamed keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TripSettings()
        minPerMile = try c.decodeIfPresent(Double.self, forKey: .minPerMile) ?? d.minPerMile
        minHourly = try c.decodeIfPresent(Double.self, forKey: .minHourly) ?? d.minHourly
        minRating = try c.decodeIfPresent(Double.self, forKey: .minRating) ?? d.minRating
        includePickupMiles = try c.decodeIfPresent(Bool.self, forKey: .includePickupMiles) ?? d.includePickupMiles
        acceptUnrated = try c.decodeIfPresent(Bool.self, forKey: .acceptUnrated) ?? d.acceptUnrated
        excludeHolidayPay = try c.decodeIfPresent(Bool.self, forKey: .excludeHolidayPay) ?? d.excludeHolidayPay
        vatFlatRate = try c.decodeIfPresent(Bool.self, forKey: .vatFlatRate) ?? d.vatFlatRate
        compactOverlay = try c.decodeIfPresent(Bool.self, forKey: .compactOverlay) ?? d.compactOverlay
        overlayScale = try c.decodeIfPresent(Double.self, forKey: .overlayScale) ?? d.overlayScale
    }

    mutating func resetMinimums() {
        let d = TripSettings()
        minPerMile = d.minPerMile
        minHourly = d.minHourly
        minRating = d.minRating
        includePickupMiles = d.includePickupMiles
        acceptUnrated = d.acceptUnrated
        excludeHolidayPay = d.excludeHolidayPay
    }
}

/// A trip offer as shown on the driver app's offer card
/// (exclusive offers have a "Confirm" button, trip radar offers a "Match" button).
struct Offer: Codable, Equatable {
    var rideType: String
    var exclusive: Bool
    var fare: Double
    /// "£0.33 est. holiday entitlement included"
    var holiday: Double?
    var pickupMinutes: Double
    var pickupMiles: Double
    var tripMinutes: Double
    var tripMiles: Double
    var rating: Double?
    var pickupPlace: String
    var dropPlace: String

    static let samples: [Offer] = [
        Offer(rideType: "Standard", exclusive: true, fare: 11.85, holiday: 0.62, pickupMinutes: 6, pickupMiles: 1.9,
              tripMinutes: 21, tripMiles: 8.4, rating: 4.93, pickupPlace: "Station Road", dropPlace: "Retail Park"),
        Offer(rideType: "Standard", exclusive: false, fare: 16.19, holiday: 0.75, pickupMinutes: 10, pickupMiles: 2.6,
              tripMinutes: 32, tripMiles: 14.2, rating: 4.49, pickupPlace: "Mill Lane", dropPlace: "Barking"),
        Offer(rideType: "Comfort", exclusive: false, fare: 24.60, holiday: 1.12, pickupMinutes: 4, pickupMiles: 1.2,
              tripMinutes: 38, tripMiles: 18.5, rating: 4.62, pickupPlace: "High Street", dropPlace: "Airport"),
        Offer(rideType: "XL", exclusive: true, fare: 31.40, holiday: 1.45, pickupMinutes: 7, pickupMiles: 2.4,
              tripMinutes: 52, tripMiles: 23.0, rating: nil, pickupPlace: "Grand Hotel", dropPlace: "Services"),
    ]
}

enum Check: String, Codable {
    case pass, fail, unknown
}

struct Verdict {
    /// The fare the sums use (after the holiday pay and VAT settings).
    var fareUsed: Double
    var perMile: Double?
    var perHour: Double?
    var rating: Double?
    var mile: Check
    var hour: Check
    var ratingCheck: Check

    var checks: [Check] { [mile, hour, ratingCheck] }
    var met: Int { checks.filter { $0 == .pass }.count }
    var overall: Check {
        if checks.contains(.fail) { return .fail }
        if checks.contains(.unknown) { return .unknown }
        return .pass
    }
}

/// Compare at the precision shown on screen (pence / two decimals),
/// so a value shown as "£1.20" never shows red against a £1.20 minimum.
private func atLeast(_ value: Double, _ minimum: Double) -> Bool {
    (value * 100).rounded() >= (minimum * 100).rounded()
}

func evaluate(_ o: Offer, _ s: TripSettings) -> Verdict {
    let base = s.excludeHolidayPay ? o.fare - (o.holiday ?? 0) : o.fare
    let fare = s.vatFlatRate ? base * vatFlatRateFactor : base
    let miles = o.tripMiles + (s.includePickupMiles ? o.pickupMiles : 0)
    let minutes = o.pickupMinutes + o.tripMinutes
    let perMile: Double? = miles > 0 ? fare / miles : nil
    let perHour: Double? = minutes > 0 ? fare / minutes * 60 : nil

    func judge(_ v: Double?, _ min: Double) -> Check {
        guard let v = v else { return .unknown }
        return atLeast(v, min) ? .pass : .fail
    }

    let ratingCheck: Check
    if let r = o.rating {
        ratingCheck = atLeast(r, s.minRating) ? .pass : .fail
    } else {
        ratingCheck = s.acceptUnrated ? .pass : .unknown
    }

    return Verdict(fareUsed: fare, perMile: perMile, perHour: perHour, rating: o.rating,
                   mile: judge(perMile, s.minPerMile), hour: judge(perHour, s.minHourly),
                   ratingCheck: ratingCheck)
}
