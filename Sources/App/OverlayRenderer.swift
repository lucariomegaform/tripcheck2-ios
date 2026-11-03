// Draws the floating result window as a picture. The picture-in-picture window shows
// these pictures like a tiny video, so it floats over the driver app.

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

    /// The window keeps one shape whatever it shows, so it doesn't jump about.
    static func canvasSize(compact: Bool) -> CGSize {
        compact ? CGSize(width: 600, height: 200) : CGSize(width: 600, height: 400)
    }

    static func render(_ mode: OverlayMode, compact: Bool) -> CGImage? {
        let size = canvasSize(compact: compact)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            background.setFill()
            context.fill(rect)
            switch mode {
            case .notReading:
                drawMessage(rect, dot: .gray, title: "Not reading", subtitle: "Open TripCheck and tap Start", band: nil)
            case .ready:
                drawMessage(rect, dot: green, title: "TripCheck ready", subtitle: "Waiting for a trip offer", band: nil)
            case .unreadable:
                drawMessage(rect, dot: nil, title: "CAN'T READ", subtitle: "Check this offer yourself", band: amber)
            case .offer(_, let verdict):
                if compact {
                    drawCompact(rect, verdict)
                } else {
                    drawFull(rect, verdict)
                }
            }
        }
        return image.cgImage
    }

    // MARK: layouts

    private static func drawFull(_ rect: CGRect, _ v: Verdict) {
        let overall = v.overall
        let header = CGRect(x: 0, y: 0, width: rect.width, height: 112)
        fillColour(overall).setFill()
        UIRectFill(header)
        drawIcon(overall, center: CGPoint(x: 56, y: header.midY), size: 40, colour: .white)
        drawText(word(overall), CGRect(x: 100, y: 0, width: 330, height: header.height), 64, .heavy, .white)
        drawText("\(v.met)/3", CGRect(x: 400, y: 0, width: 170, height: header.height), 48, .semibold, .white, .right)

        let rows: [(String, String, Check)] = [
            ("per mile", v.perMile.map { String(format: "£%.2f", $0) } ?? "?", v.mile),
            ("per min", v.perMinute.map { String(format: "£%.2f", $0) } ?? "?", v.minute),
            ("rating", v.rating.map { String(format: "%.2f", $0) } ?? "new", v.ratingCheck),
        ]
        let rowHeight = (rect.height - header.height) / 3
        for (i, row) in rows.enumerated() {
            let y = header.maxY + CGFloat(i) * rowHeight
            let r = CGRect(x: 0, y: y, width: rect.width, height: rowHeight)
            if i > 0 {
                UIColor(white: 1, alpha: 0.08).setFill()
                UIRectFill(CGRect(x: 24, y: y, width: rect.width - 48, height: 2))
            }
            let iconCenter = CGPoint(x: 56, y: r.midY)
            fillColour(row.2).setFill()
            UIBezierPath(ovalIn: CGRect(x: iconCenter.x - 26, y: iconCenter.y - 26, width: 52, height: 52)).fill()
            drawIcon(row.2, center: iconCenter, size: 24, colour: .white)
            drawText(row.0, CGRect(x: 100, y: r.minY, width: 220, height: r.height), 38, .medium, UIColor(white: 0.78, alpha: 1))
            drawText(row.1, CGRect(x: 300, y: r.minY, width: 270, height: r.height), 64, .bold, textColour(row.2), .right)
        }
    }

    private static func drawCompact(_ rect: CGRect, _ v: Verdict) {
        let overall = v.overall
        let left = CGRect(x: 0, y: 0, width: 420, height: rect.height)
        fillColour(overall).setFill()
        UIRectFill(left)
        drawIcon(overall, center: CGPoint(x: 70, y: left.midY), size: 56, colour: .white)
        drawText(word(overall), CGRect(x: 120, y: 0, width: 300, height: rect.height), 80, .heavy, .white)
        for (i, check) in v.checks.enumerated() {
            let center = CGPoint(x: 460 + CGFloat(i) * 52, y: rect.midY)
            textColour(check).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)).fill()
        }
    }

    private static func drawMessage(_ rect: CGRect, dot: UIColor?, title: String, subtitle: String, band: UIColor?) {
        if let band = band {
            band.setFill()
            UIRectFill(rect)
        }
        let big = rect.height >= 400
        let titleSize: CGFloat = big ? 60 : 52
        let subtitleSize: CGFloat = big ? 34 : 28
        let titleRect = CGRect(x: 30, y: rect.midY - (big ? 70 : 54), width: rect.width - 60, height: big ? 80 : 64)
        var titleX = titleRect
        if let dot = dot {
            dot.setFill()
            UIBezierPath(ovalIn: CGRect(x: 40, y: titleRect.midY - 14, width: 28, height: 28)).fill()
            titleX = CGRect(x: 86, y: titleRect.minY, width: titleRect.width - 56, height: titleRect.height)
        }
        drawText(title, titleX, titleSize, .heavy, .white, dot == nil ? .center : .left)
        drawText(subtitle, CGRect(x: 30, y: titleRect.maxY, width: rect.width - 60, height: big ? 70 : 50),
                 subtitleSize, .medium, UIColor(white: band == nil ? 0.72 : 1, alpha: 1), dot == nil ? .center : .left)
    }

    // MARK: drawing helpers

    private static func drawText(_ s: String, _ rect: CGRect, _ size: CGFloat, _ weight: UIFont.Weight,
                                 _ colour: UIColor, _ align: NSTextAlignment = .left) {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
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
        path.lineWidth = max(3, size * 0.22)
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
