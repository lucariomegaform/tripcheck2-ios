// Reads a trip offer from the words on screen (what text recognition gives back).
// Same reader as the desktop prototype, which is tested against both card layouts:
//
//   UberX  Exclusive
//   £4.63
//   £0.33 est. holiday entitlement included
//   4 min • 0.9 mi
//   20 Some Avenue, Enfield, EN1 4AE      (addresses are skipped, never kept)
//   ★ 4.80                       (the star may not be read, leaving "4.80")
//   6 mins • 2.0 mi
//   Some Road, Enfield, EN2 9DJ
//   Confirm                      ("Match" on trip radar offers)
//
// To avoid reading other screens as offers (the driver app's trip history, a screenshot in
// Photos while scrolling), a card only counts when its parts come in the card's order:
// the fare, then the drive to the pickup, then the trip, then the Accept / Confirm / Match
// button. The screen broadcast reader also waits until two reads in a row agree.

import Foundation

enum OfferReader {
    private static func rx(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed and known to be valid.
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let money = rx(#"£\s*(\d{1,4}(?:[.,]\d{1,2})?)"#)
    // The fare sits on a line of its own: just the amount, no words.
    static let fareOnly = rx(#"^[^A-Za-z]*£\s*(\d{1,4}(?:[.,]\d{1,2})?)[^A-Za-z]*$"#)
    // The rating pill: "★ 4.81", "4.81", "4.81 Verified" (the star is often not read).
    static let pillRating = rx(#"(?:^|[^\d£.,])([1-5])\.([0-9O]{2})(?:$|[^\d])"#)
    static let starRating = rx(#"(?:★|☆|\*)\s*([1-5][.,]\d{1,2})|([1-5][.,]\d{1,2})\s*(?:★|☆|\*)"#)
    static let bareRating = rx(#"^\s*([1-5][.,]\d{2})\s*$"#)
    // "4 min • 0.9 mi", "32 mins · 14.2 mi", "1 hr 5 mins • 30 mi", "6 min (1.9 mi) away"
    static let leg = rx(#"(?i)(?:(\d+)\s*(?:hours?|hrs?|h)\s*)?(\d+)\s*(?:minutes?|mins?|m)\b\s*[(•·∙●\-–,.]?\s*(\d+(?:[.,]\d+)?)\s*(?:miles?|mi)\b\s*\)?"#)

    // MARK: helpers

    private static func firstMatch(_ r: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        r.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s))
    }

    private static func allMatches(_ r: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        r.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }

    private static func isMatch(_ r: NSRegularExpression, _ s: String) -> Bool {
        firstMatch(r, s) != nil
    }

    private static func num(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func isExtraMoney(_ line: String) -> Bool {
        let l = line.lowercased()
        return ["holiday", "entitlement", "included", "tip", "boost", "surge", "promotion", "+£"].contains { l.contains($0) }
    }

    /// The card's button: "Accept", "Confirm" (exclusive) or "Match" (trip radar), on a short line.
    static func isButton(_ line: String) -> Bool {
        let l = line.lowercased()
        guard l.count <= 24 else { return false }
        return ["accept", "confirm", "match"].contains { l.contains($0) }
    }

    /// A rating on a short line such as the rating pill ("★ 4.81 Verified").
    private static func ratingInLine(_ line: String) -> Double? {
        guard !line.contains("£"), line.count <= 30,
              let m = firstMatch(pillRating, line),
              let whole = group(m, 1, line), let decimals = group(m, 2, line) else { return nil }
        let r = num(whole + "." + decimals.replacingOccurrences(of: "O", with: "0"))
        return (1.0...5.0).contains(r) ? r : nil
    }

    /// TripCheck's own floating window can sit over the screen; never read its words as the offer.
    static func isOwnOverlay(_ line: String) -> Bool {
        let l = line.lowercased()
        return ["per mile", "per hour", "per min", "tripcheck", "meets", "below", "rating", "can't read", "check this offer", "with vat", "nearly"]
            .contains { l.contains($0) }
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isOwnOverlay($0) }
    }

    /// True when the screen looks like it shows an offer card (a fare and the card's button),
    /// even if it couldn't be read fully.
    static func looksLikeOffer(_ text: String) -> Bool {
        let all = splitLines(text)
        guard let fareIndex = all.firstIndex(where: { !isExtraMoney($0) && isMatch(money, $0) }) else { return false }
        return all[(fareIndex + 1)...].contains(where: isButton)
            && all.contains(where: { isMatch(leg, $0) })
    }

    // MARK: reading

    fileprivate enum LegKind { case pickup, trip, unsure }

    fileprivate struct Leg {
        let kind: LegKind
        let minutes: Double
        let miles: Double
        let line: Int
    }

    /// The offer on screen, or nil if there isn't a complete card.
    static func parse(_ text: String) -> Offer? {
        let lines = splitLines(text)
        guard !lines.isEmpty else { return nil }

        // Fare: the first £ amount on a line of its own that isn't the holiday pay line.
        guard let fareIndex = lines.firstIndex(where: { !isExtraMoney($0) && isMatch(fareOnly, $0) })
                ?? lines.firstIndex(where: { !isExtraMoney($0) && isMatch(money, $0) }),
              let fareMatch = firstMatch(money, lines[fareIndex]),
              let fareText = group(fareMatch, 1, lines[fareIndex]) else { return nil }
        let fare = num(fareText)
        guard fare > 0 else { return nil }

        // The legs after the fare, in order.
        var legs: [Leg] = []
        for i in (fareIndex + 1)..<lines.count {
            let line = lines[i]
            let lower = line.lowercased()
            let kind: LegKind
            if lower.contains("away") || lower.contains("pickup") || lower.contains("pick-up") {
                kind = .pickup
            } else if lower.contains("trip") || lower.contains("journey") || lower.contains("drop") {
                kind = .trip
            } else {
                kind = .unsure
            }
            for m in allMatches(leg, line) {
                guard let mins = group(m, 2, line), let miles = group(m, 3, line) else { continue }
                let hours = group(m, 1, line).map { num($0) } ?? 0
                legs.append(Leg(kind: kind, minutes: hours * 60 + num(mins), miles: num(miles), line: i))
            }
        }
        // The pickup comes first and the trip second (unless the words say otherwise).
        guard legs.count >= 2 else { return nil }
        var pickup = legs[0], trip = legs[1]
        if pickup.kind == .trip && trip.kind == .pickup { swap(&pickup, &trip) }
        guard trip.miles > 0 || trip.minutes > 0 else { return nil }

        // The card ends with its button. Other screens (the trip history, a list of past
        // offers) have fares and distances but no Accept / Confirm / Match button after them.
        let lastLeg = max(pickup.line, trip.line)
        guard let buttonIndex = lines.indices.first(where: { $0 > lastLeg && isButton(lines[$0]) }) else { return nil }
        let card = Array(lines[fareIndex...buttonIndex])

        var holiday: Double? = nil
        if let line = lines[fareIndex...buttonIndex].first(where: { $0.lowercased().contains("holiday") || $0.lowercased().contains("entitlement") }),
           let m = firstMatch(money, line), let h = group(m, 1, line) {
            holiday = num(h)
        }

        // Rating: the pill under the pickup address (between the pickup and trip lines),
        // then anything with a star on the card, then a number on a line of its own.
        var rating: Double? = nil
        let from = min(pickup.line, trip.line), to = max(pickup.line, trip.line)
        if to > from + 1 {
            for line in lines[(from + 1)..<to] {
                if let r = ratingInLine(line) {
                    rating = r
                    break
                }
            }
        }
        if rating == nil {
            for line in card {
                if let m = firstMatch(starRating, line), let r = group(m, 1, line) ?? group(m, 2, line) {
                    rating = num(r)
                    break
                }
            }
        }
        if rating == nil {
            for line in card {
                if let m = firstMatch(bareRating, line), let r = group(m, 1, line) {
                    rating = num(r)
                    break
                }
            }
        }

        // Trip types: only from the top of the card (just above the fare, down to the drive to
        // the pickup), so an address can never be taken for one. A trip can have several.
        let header = lines[max(0, fareIndex - 3)..<min(pickup.line, trip.line)].filter { !isExtraMoney($0) }
        let types = TripType.find(in: header.joined(separator: "\n"))

        let headerText = header.joined(separator: " ").lowercased()
        let exclusive = headerText.contains("exclusive") || card.contains(where: { $0.lowercased().contains("confirm") })

        return Offer(types: types, exclusive: exclusive, fare: fare, holiday: holiday,
                     pickupMinutes: pickup.minutes, pickupMiles: pickup.miles,
                     tripMinutes: trip.minutes, tripMiles: trip.miles, rating: rating)
    }
}
