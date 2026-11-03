// Reads a trip offer from the words on screen (what text recognition gives back).
// Same reader as the desktop prototype, which is tested against both card layouts:
//
//   UberX  Exclusive
//   £4.63
//   £0.33 est. holiday entitlement included
//   4 min • 0.9 mi
//   20 Some Avenue, Enfield, EN1 4AE
//   ★ 4.80                       (the star may not be read, leaving "4.80")
//   6 mins • 2.0 mi
//   Some Road, Enfield, EN2 9DJ
//   Confirm                      ("Match" on trip radar offers)

import Foundation

enum OfferReader {
    private static func rx(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed and known to be valid.
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let money = rx(#"£\s*(\d{1,4}(?:[.,]\d{1,2})?)"#)
    static let starRating = rx(#"(?i)(?:★|☆|\*|rating[:\s]*)\s*([1-5][.,]\d{1,2})|([1-5][.,]\d{1,2})\s*(?:★|☆|\*)"#)
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

    private static func isButtonOrTag(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces).lowercased()
        return ["accept", "confirm", "match", "exclusive", "new rider"].contains(l)
    }

    private static func isData(_ line: String) -> Bool {
        isMatch(money, line) || isMatch(leg, line) || isMatch(starRating, line) || isMatch(bareRating, line)
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True when the screen looks like it shows an offer card, even if it couldn't be read fully.
    static func looksLikeOffer(_ text: String) -> Bool {
        let all = splitLines(text)
        let lower = text.lowercased()
        if lower.contains("holiday entitlement") { return true }
        if all.contains(where: { ["confirm", "match"].contains($0.lowercased()) }) { return true }
        return all.contains(where: { isMatch(money, $0) }) && all.contains(where: { isMatch(leg, $0) })
    }

    // MARK: reading

    fileprivate enum LegKind { case pickup, trip, unsure }

    fileprivate struct Leg {
        let kind: LegKind
        let minutes: Double
        let miles: Double
        let line: Int
    }

    /// The offer on screen, or nil if there isn't a complete one.
    static func parse(_ text: String) -> Offer? {
        let lines = splitLines(text)
        guard !lines.isEmpty else { return nil }

        // Fare: the first £ amount that isn't the holiday pay line.
        guard let fareLine = lines.first(where: { !isExtraMoney($0) && isMatch(money, $0) }),
              let fareMatch = firstMatch(money, fareLine),
              let fareText = group(fareMatch, 1, fareLine) else { return nil }
        let fare = num(fareText)

        var holiday: Double? = nil
        if let line = lines.first(where: { $0.lowercased().contains("holiday") || $0.lowercased().contains("entitlement") }),
           let m = firstMatch(money, line), let h = group(m, 1, line) {
            holiday = num(h)
        }

        var rating: Double? = nil
        if let m = firstMatch(starRating, text), let r = group(m, 1, text) ?? group(m, 2, text) {
            rating = num(r)
        }
        if rating == nil {
            for line in lines {
                if let m = firstMatch(bareRating, line), let r = group(m, 1, line) {
                    rating = num(r)
                    break
                }
            }
        }

        var legs: [Leg] = []
        for (i, line) in lines.enumerated() {
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

        var used = Array(repeating: false, count: legs.count)
        func take(_ want: LegKind) -> Leg? {
            var index = legs.indices.first(where: { !used[$0] && legs[$0].kind == want })
            if index == nil {
                index = legs.indices.first(where: { !used[$0] && legs[$0].kind == .unsure })
            }
            guard let i = index else { return nil }
            used[i] = true
            return legs[i]
        }
        guard let pickup = take(.pickup), let trip = take(.trip) else { return nil }

        // Addresses can wrap onto more than one line: take lines until the next piece of data.
        func placeAfter(_ index: Int) -> String {
            var parts: [String] = []
            var j = index + 1
            while j < lines.count && !isData(lines[j]) && !isButtonOrTag(lines[j]) {
                parts.append(lines[j])
                j += 1
            }
            return parts.joined(separator: " ")
        }

        var rideType = "Trip"
        for line in lines {
            if isMatch(money, line) { break }
            if !isButtonOrTag(line) && !isData(line) {
                rideType = line
                break
            }
        }
        rideType = rideType.replacingOccurrences(of: "Exclusive", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if rideType.isEmpty { rideType = "Trip" }

        let exclusive = text.lowercased().contains("exclusive")
            || lines.contains(where: { $0.lowercased() == "confirm" })

        return Offer(rideType: rideType, exclusive: exclusive, fare: fare, holiday: holiday,
                     pickupMinutes: pickup.minutes, pickupMiles: pickup.miles,
                     tripMinutes: trip.minutes, tripMiles: trip.miles, rating: rating,
                     pickupPlace: placeAfter(pickup.line), dropPlace: placeAfter(trip.line))
    }
}
