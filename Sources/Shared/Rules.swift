// The driver's minimums, the trip offer, and the checking rules.
// Same rules as the desktop prototype.

import Foundation

/// VAT flat rate scheme: the platform pays 20% VAT on top, then 10% of the takings goes to
/// HMRC, so the money kept is the offer × 1.2 × 0.9 (a £10.00 offer is worth £10.80).
let vatFlatRateFactor = 1.2 * 0.9

/// The fare range slider's top end. A maximum fare set this high means "no maximum".
let fareRangeTop = 50.0

struct TripSettings: Codable, Equatable {
    /// Minimum fare per mile, in pounds.
    var minPerMile: Double = 1.20
    /// Minimum hourly rate, in pounds.
    var minHourly: Double = 25.00
    /// Minimum passenger rating.
    var minRating: Double = 4.70
    /// "Nearly" ranges below each minimum. An offer that misses a minimum by no more than
    /// this shows amber instead of red. 0 means the minimum is strict.
    var perMileThreshold: Double = 0
    var hourlyThreshold: Double = 0
    var ratingThreshold: Double = 0
    /// Fare range: offers outside it are shown in muted colours in the floating window.
    /// A maximum of £50 (the slider's top) means unlimited.
    var minFare: Double = 0
    var maxFare: Double = fareRangeTop
    /// Count the drive to the pickup in the analysis (both the miles and the time).
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
    /// Screenshot shortcut: also show the result as a notification banner (it slides away
    /// after a few seconds, even if the shortcut's own result panel is switched off).
    var shortcutBanner: Bool = true
    /// How long the shortcut's result banner stays before TripCheck takes it away, in seconds.
    var shortcutPopupSeconds: Double = 5

    init() {}

    // Read older saved settings even if a newer version added or renamed keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TripSettings()
        minPerMile = try c.decodeIfPresent(Double.self, forKey: .minPerMile) ?? d.minPerMile
        minHourly = try c.decodeIfPresent(Double.self, forKey: .minHourly) ?? d.minHourly
        minRating = try c.decodeIfPresent(Double.self, forKey: .minRating) ?? d.minRating
        perMileThreshold = try c.decodeIfPresent(Double.self, forKey: .perMileThreshold) ?? d.perMileThreshold
        hourlyThreshold = try c.decodeIfPresent(Double.self, forKey: .hourlyThreshold) ?? d.hourlyThreshold
        ratingThreshold = try c.decodeIfPresent(Double.self, forKey: .ratingThreshold) ?? d.ratingThreshold
        minFare = try c.decodeIfPresent(Double.self, forKey: .minFare) ?? d.minFare
        maxFare = try c.decodeIfPresent(Double.self, forKey: .maxFare) ?? d.maxFare
        includePickupMiles = try c.decodeIfPresent(Bool.self, forKey: .includePickupMiles) ?? d.includePickupMiles
        acceptUnrated = try c.decodeIfPresent(Bool.self, forKey: .acceptUnrated) ?? d.acceptUnrated
        excludeHolidayPay = try c.decodeIfPresent(Bool.self, forKey: .excludeHolidayPay) ?? d.excludeHolidayPay
        vatFlatRate = try c.decodeIfPresent(Bool.self, forKey: .vatFlatRate) ?? d.vatFlatRate
        compactOverlay = try c.decodeIfPresent(Bool.self, forKey: .compactOverlay) ?? d.compactOverlay
        overlayScale = try c.decodeIfPresent(Double.self, forKey: .overlayScale) ?? d.overlayScale
        shortcutBanner = try c.decodeIfPresent(Bool.self, forKey: .shortcutBanner) ?? d.shortcutBanner
        shortcutPopupSeconds = try c.decodeIfPresent(Double.self, forKey: .shortcutPopupSeconds) ?? d.shortcutPopupSeconds
    }

    mutating func resetMinimums() {
        let d = TripSettings()
        minPerMile = d.minPerMile
        minHourly = d.minHourly
        minRating = d.minRating
        perMileThreshold = d.perMileThreshold
        hourlyThreshold = d.hourlyThreshold
        ratingThreshold = d.ratingThreshold
        minFare = d.minFare
        maxFare = d.maxFare
        includePickupMiles = d.includePickupMiles
        acceptUnrated = d.acceptUnrated
        excludeHolidayPay = d.excludeHolidayPay
    }

    /// The same settings with no "nearly" ranges: each minimum is strict (the History tab).
    var strict: TripSettings {
        var s = self
        s.perMileThreshold = 0
        s.hourlyThreshold = 0
        s.ratingThreshold = 0
        return s
    }

    var hasNoMaximumFare: Bool { maxFare >= fareRangeTop - 0.001 }
}

/// The trip types the driver app shows at the top of the card. A trip can have several
/// (for example Business + Comfort + Electric).
enum TripType {
    static let all = ["UberX", "Electric", "Comfort", "Business", "Priority", "Teens", "Pet", "XL", "XXL", "Lux", "Assist"]

    // "UberX", "Uber X", "UberXL", "Uber Pet", "Comfort", "XXL"... as whole words.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z])(uber\s*)?(xxl|xl|x|electric|comfort|business|priority|teens?|pets?|lux|assist)(?![A-Za-z])"#,
        options: [])

    /// The trip types named in a piece of text, in the order of the list above.
    static func find(in text: String) -> [String] {
        var found = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for m in pattern.matches(in: text, options: [], range: range) {
            guard let r = Range(m.range(at: 2), in: text) else { continue }
            let word = text[r].lowercased()
            let hasUber = m.range(at: 1).location != NSNotFound
            switch word {
            case "x": if hasUber { found.insert("UberX") }   // a lone "X" isn't a trip type
            case "xl": found.insert("XL")
            case "xxl": found.insert("XXL")
            case "teen", "teens": found.insert("Teens")
            case "pet", "pets": found.insert("Pet")
            default: found.insert(word.prefix(1).uppercased() + String(word.dropFirst()))
            }
        }
        return all.filter { found.contains($0) }
    }
}

/// A trip offer as shown on the driver app's offer card
/// (exclusive offers have a "Confirm" button, trip radar offers a "Match" button).
/// Addresses are deliberately not kept.
struct Offer: Codable, Equatable {
    /// Trip types from the top of the card ("UberX", or "Business", "Comfort", "Electric"...).
    var types: [String]
    var exclusive: Bool
    var fare: Double
    /// "£0.33 est. holiday entitlement included"
    var holiday: Double?
    var pickupMinutes: Double
    var pickupMiles: Double
    var tripMinutes: Double
    var tripMiles: Double
    var rating: Double?

    /// "Business + Comfort + Electric", or "Type not read".
    var typeText: String { types.isEmpty ? "Type not read" : types.joined(separator: " + ") }

    /// The same numbers as another offer: the same card (or a picture of it) seen again.
    func sameNumbers(as o: Offer) -> Bool {
        abs(fare - o.fare) < 0.005
            && abs(pickupMinutes - o.pickupMinutes) < 0.5 && abs(pickupMiles - o.pickupMiles) < 0.05
            && abs(tripMinutes - o.tripMinutes) < 0.5 && abs(tripMiles - o.tripMiles) < 0.05
    }

    static let samples: [Offer] = [
        Offer(types: ["UberX"], exclusive: true, fare: 11.85, holiday: 0.62, pickupMinutes: 6, pickupMiles: 1.9,
              tripMinutes: 21, tripMiles: 8.4, rating: 4.93),
        Offer(types: ["UberX"], exclusive: false, fare: 16.19, holiday: 0.75, pickupMinutes: 10, pickupMiles: 2.6,
              tripMinutes: 32, tripMiles: 14.2, rating: 4.49),
        Offer(types: ["Electric", "Comfort", "Business"], exclusive: false, fare: 24.60, holiday: 1.12, pickupMinutes: 4, pickupMiles: 1.2,
              tripMinutes: 38, tripMiles: 18.5, rating: 4.68),
        Offer(types: ["XL"], exclusive: true, fare: 31.40, holiday: 1.45, pickupMinutes: 7, pickupMiles: 2.4,
              tripMinutes: 52, tripMiles: 23.0, rating: nil),
    ]
}

enum Check: String, Codable {
    /// Meets the minimum (green).
    case pass
    /// Misses the minimum, but by no more than the driver's "nearly" range (amber).
    case near
    /// Below the minimum (red).
    case fail
    /// Couldn't tell, for example a new rider with no rating (amber).
    case unknown
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
    /// False when the offer's price is outside the driver's fare range (shown muted).
    var fareInRange: Bool = true

    var checks: [Check] { [mile, hour, ratingCheck] }
    var met: Int { checks.filter { $0 == .pass }.count }
    var overall: Check {
        if checks.contains(.fail) { return .fail }
        if checks.contains(.unknown) { return .unknown }
        if checks.contains(.near) { return .near }
        return .pass
    }
}

/// Compare at the precision shown on screen (pence / two decimals),
/// so a value shown as "£1.20" never shows red against a £1.20 minimum.
private func atLeast(_ value: Double, _ minimum: Double) -> Bool {
    (value * 100).rounded() >= (minimum * 100).rounded()
}

/// Green at or above the minimum; amber within `threshold` below it; red further below.
private func judge(_ value: Double, minimum: Double, threshold: Double) -> Check {
    if atLeast(value, minimum) { return .pass }
    if threshold > 0.0001 && atLeast(value, minimum - threshold) { return .near }
    return .fail
}

/// The price shown in the floating window (with VAT when the VAT flat rate scheme is on).
func shownPrice(_ o: Offer, _ s: TripSettings) -> Double {
    o.fare * (s.vatFlatRate ? vatFlatRateFactor : 1)
}

func evaluate(_ o: Offer, _ s: TripSettings) -> Verdict {
    let base = s.excludeHolidayPay ? o.fare - (o.holiday ?? 0) : o.fare
    let fare = s.vatFlatRate ? base * vatFlatRateFactor : base
    let miles = o.tripMiles + (s.includePickupMiles ? o.pickupMiles : 0)
    let minutes = o.tripMinutes + (s.includePickupMiles ? o.pickupMinutes : 0)
    let perMile: Double? = miles > 0 ? fare / miles : nil
    let perHour: Double? = minutes > 0 ? fare / minutes * 60 : nil

    let ratingCheck: Check
    if let r = o.rating {
        ratingCheck = judge(r, minimum: s.minRating, threshold: s.ratingThreshold)
    } else {
        ratingCheck = s.acceptUnrated ? .pass : .unknown
    }

    let price = shownPrice(o, s)
    let inRange = atLeast(price, s.minFare) && (s.hasNoMaximumFare || atLeast(s.maxFare, price))

    return Verdict(fareUsed: fare, perMile: perMile, perHour: perHour, rating: o.rating,
                   mile: perMile.map { judge($0, minimum: s.minPerMile, threshold: s.perMileThreshold) } ?? .unknown,
                   hour: perHour.map { judge($0, minimum: s.minHourly, threshold: s.hourlyThreshold) } ?? .unknown,
                   ratingCheck: ratingCheck, fareInRange: inRange)
}
