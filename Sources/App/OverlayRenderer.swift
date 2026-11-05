// Draws the floating result window as a picture. The picture-in-picture window shows
// these pictures like a tiny video, so it floats over the driver app.
//
// The picture is always 600 wide. Its content is drawn at a size set by the driver
// (the "Text size" slider; 100% is half the size of the very first version). Smaller
// content also makes the picture shorter, so the floating window takes less room.

import UIKit

enum OverlayMode {
    case notReading
    case ready
    case unreadable
    case offer(Offer, Verdict)
}

enum OverlayRenderer {
    static let green = UIColor(red: 22 / 255, green: 163 / 255, blue: 74 / 255, alpha: 1)
    static let red = UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
    static let amber = UIColor(red: 217 / 255, green: 119 / 255, blue: 6 / 255, alpha: 1)
    static let greenText = UIColor(red: 74 / 255, green: 222 / 255, blue: 128 / 255, alpha: 1)
    static let redText = UIColor(red: 252 / 255, green: 120 / 255, blue: 120 / 255, alpha: 1)
    static let amberText = UIColor(red: 251 / 255, green: 191 / 255, blue: 36 / 255, alpha: 1)
    static let background = UIColor(red: 16 / 255, green: 18 / 255, blue: 24 / 255, alpha: 1)

    static let width: CGFloat = 600

    static func fillColour(_ c: Check) -> UIColor {
        switch c {
        case .pass: return green
        case .fail: return red
        case .unknown: return amber
        }
    }

    static func textColour(_ c: Check) -> UIColor {
        switch c {
        case .pass: return greenText
        case .fail: return redText
        case .unknown: return amberText
        }
    }

    static func word(_ c: Check) -> String {
        switch c {
        case .pass: return "MEETS"
        case .fail: return "BELOW"
        case .unknown: return "CHECK"
        }
    }

    /// Drawing scale: 0.5 at the default "100%" setting.
    static func scale(_ settings: TripSettings) -> CGFloat {
        CGFloat(0.5 * min(max(settings.overlayScale, 0.5), 2.0))
    }

    /// Height of the drawn content before it's placed in the picture.
    private static func contentHeight(compact: Bool, k: CGFloat) -> CGFloat {
        (compact ? 200 : 400) * k
    }

    /// The picture keeps one shape whatever it shows, so the window doesn't jump about.
    static func canvasSize(_ settings: TripSettings) -> CGSize {
        let k = scale(settings)
        let compact = settings.compactOverlay
        let minimum: CGFloat = compact ? 150 : 200   // keeps the window no wider than 4:1 / 3:1
        return CGSize(width: width, height: max(minimum, contentHeight(compact: compact, k: k)).rounded())
    }

    static func render(_ mode: OverlayMode, settings: TripSettings) -> CGImage? {
        let size = canvasSize(settings)
        let k = scale(settings)
        let compact = settings.compactOverlay
        // The content area, centred top to bottom.
        let h = contentHeight(compact: compact, k: k)
        let area = CGRect(x: 0, y: ((size.height - h) / 2).rounded(), width: size.width, height: h)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let all = CGRect(origin: .zero, size: size)
            background.setFill()
            context.fill(all)
            switch mode {
            case .notReading:
                drawMessage(all, area, k, dot: .gray, title: "Not reading", subtitle: "Open TripCheck and tap Start", band: nil)
            case .ready:
                drawMessage(all, area, k, dot: green, title: "TripCheck ready", subtitle: "Waiting for a trip offer", band: nil)
            case .unreadable:
                drawMessage(all, area, k, dot: nil, title: "CAN'T READ", subtitle: "Check this offer yourself", band: amber)
            case .offer(let offer, let verdict):
                // The offer's price; with the VAT flat rate scheme on, the price with VAT (× 1.2 × 0.9).
                let price = String(format: "£%.2f", offer.fare * (settings.vatFlatRate ? vatFlatRateFactor : 1))
                if compact {
                    drawCompact(all, area, k, price, verdict)
                } else {
                    drawFull(all, area, k, price, verdict)
                }
            }
        }
        return image.cgImage
    }

    // MARK: layouts

    private static func drawFull(_ all: CGRect, _ area: CGRect, _ k: CGFloat, _ price: String, _ v: Verdict) {
        let overall = v.overall
        let margin = 30 * k
        let header = CGRect(x: 0, y: 0, width: all.width, height: area.minY + 112 * k)
        fillColour(overall).setFill()
        UIRectFill(header)
        let headerMid = CGRect(x: 0, y: area.minY, width: all.width, height: 112 * k)
        drawIcon(overall, center: CGPoint(x: 56 * k, y: headerMid.midY), size: 40 * k, colour: .white)
        drawText(word(overall), CGRect(x: 100 * k, y: headerMid.minY, width: 330 * k, height: headerMid.height), 64 * k, .heavy, .white)

        // The trip price.
        let priceBox = CGRect(x: all.width / 2, y: headerMid.minY, width: all.width / 2 - margin, height: headerMid.height)
        drawText(price, priceBox, 56 * k, .heavy, .white, .right)

        let rows: [(String, String, Check)] = [
            ("per mile", v.perMile.map { String(format: "£%.2f", $0) } ?? "?", v.mile),
            ("per hour", v.perHour.map { String(format: "£%.2f", $0) } ?? "?", v.hour),
            ("rating", v.rating.map { String(format: "%.2f", $0) } ?? "new", v.ratingCheck),
        ]
        let rowHeight = 96 * k
        for (i, row) in rows.enumerated() {
            let y = headerMid.maxY + CGFloat(i) * rowHeight
            let r = CGRect(x: 0, y: y, width: all.width, height: rowHeight)
            if i > 0 {
                UIColor(white: 1, alpha: 0.08).setFill()
                UIRectFill(CGRect(x: 24 * k, y: y, width: all.width - 48 * k, height: max(1, 2 * k)))
            }
            let iconCenter = CGPoint(x: 56 * k, y: r.midY)
            let radius = 26 * k
            fillColour(row.2).setFill()
            UIBezierPath(ovalIn: CGRect(x: iconCenter.x - radius, y: iconCenter.y - radius, width: radius * 2, height: radius * 2)).fill()
            drawIcon(row.2, center: iconCenter, size: 24 * k, colour: .white)
            drawText(row.0, CGRect(x: 100 * k, y: r.minY, width: 240 * k, height: r.height), 38 * k, .medium, UIColor(white: 0.78, alpha: 1))
            drawText(row.1, CGRect(x: all.width / 2, y: r.minY, width: all.width / 2 - margin, height: r.height),
                     64 * k, .bold, textColour(row.2), .right)
        }
    }

    private static func drawCompact(_ all: CGRect, _ area: CGRect, _ k: CGFloat, _ price: String, _ v: Verdict) {
        let overall = v.overall
        let margin = 30 * k
        let block = CGRect(x: 0, y: 0, width: 420 * k, height: all.height)
        fillColour(overall).setFill()
        UIRectFill(block)
        drawIcon(overall, center: CGPoint(x: 70 * k, y: area.midY), size: 56 * k, colour: .white)
        drawText(word(overall), CGRect(x: 120 * k, y: area.minY, width: 300 * k, height: area.height), 80 * k, .heavy, .white)

        // Three dots on the right, the price between the verdict and the dots.
        let dotRadius = 20 * k
        let dotGap = 52 * k
        let firstDotX = all.width - margin - dotRadius - 2 * dotGap
        for (i, check) in v.checks.enumerated() {
            let center = CGPoint(x: firstDotX + CGFloat(i) * dotGap, y: area.midY)
            textColour(check).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)).fill()
        }
        let priceBox = CGRect(x: block.maxX, y: area.minY, width: firstDotX - dotRadius - block.maxX, height: area.height)
        drawText(price, priceBox, 60 * k, .heavy, .white, .center)
    }

    private static func drawMessage(_ all: CGRect, _ area: CGRect, _ k: CGFloat, dot: UIColor?, title: String, subtitle: String, band: UIColor?) {
        if let band = band {
            band.setFill()
            UIRectFill(all)
        }
        let titleRect = CGRect(x: 30 * k, y: area.midY - 70 * k, width: all.width - 60 * k, height: 80 * k)
        var titleArea = titleRect
        if let dot = dot {
            dot.setFill()
            UIBezierPath(ovalIn: CGRect(x: 40 * k, y: titleRect.midY - 14 * k, width: 28 * k, height: 28 * k)).fill()
            titleArea = CGRect(x: 86 * k, y: titleRect.minY, width: titleRect.width - 56 * k, height: titleRect.height)
        }
        drawText(title, titleArea, 60 * k, .heavy, .white, dot == nil ? .center : .left)
        drawText(subtitle, CGRect(x: 30 * k, y: titleRect.maxY, width: all.width - 60 * k, height: 60 * k),
                 34 * k, .medium, UIColor(white: band == nil ? 0.72 : 1, alpha: 1), dot == nil ? .center : .left)
    }

    // MARK: drawing helpers

    private static func drawText(_ s: String, _ rect: CGRect, _ size: CGFloat, _ weight: UIFont.Weight,
                                 _ colour: UIColor, _ align: NSTextAlignment = .left) {
        let font = UIFont.systemFont(ofSize: max(size, 6), weight: weight)
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .paragraphStyle: para]
        let h = font.lineHeight
        let r = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        (s as NSString).draw(in: r, withAttributes: attributes)
    }

    private static func drawIcon(_ c: Check, center: CGPoint, size: CGFloat, colour: UIColor) {
        let path = UIBezierPath()
        path.lineWidth = max(2, size * 0.22)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        colour.setStroke()
        colour.setFill()
        switch c {
        case .pass:
            path.move(to: CGPoint(x: center.x - size * 0.5, y: center.y))
            path.addLine(to: CGPoint(x: center.x - size * 0.15, y: center.y + size * 0.38))
            path.addLine(to: CGPoint(x: center.x + size * 0.5, y: center.y - size * 0.42))
            path.stroke()
        case .fail:
            let d = size * 0.42
            path.move(to: CGPoint(x: center.x - d, y: center.y - d))
            path.addLine(to: CGPoint(x: center.x + d, y: center.y + d))
            path.move(to: CGPoint(x: center.x - d, y: center.y + d))
            path.addLine(to: CGPoint(x: center.x + d, y: center.y - d))
            path.stroke()
        case .unknown:
            path.move(to: CGPoint(x: center.x, y: center.y - size * 0.55))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size * 0.15))
            path.stroke()
            let r = size * 0.13
            UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y + size * 0.42 - r, width: r * 2, height: r * 2)).fill()
        }
    }
}
