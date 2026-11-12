// The screenshot shortcut: a second way of capturing offers, alongside the screen broadcast.
//
// TripCheck adds a "Check Trip Offer" action to Apple's Shortcuts app. The driver makes a
// two-step shortcut (Take Screenshot, then Check Trip Offer) and puts it on the AssistiveTouch
// button (or Back Tap). When an offer appears, one tap takes a screenshot; TripCheck reads it
// with the same on-device text recognition and rules as the broadcast reader, saves it in
// History and shows the result at the top of the screen for a few seconds:
//   • as the shortcut's result panel (if "Show When Run" is on for the action): just the coloured box,
//     no text line above it (that repeated the same figures), and/or
//   • as a notification banner (Settings › "Show shortcut results as a banner"), which
//     TripCheck takes away after the driver's chosen number of seconds (default 5).
// iOS gives apps no way to close the result panel on a timer (it waits for Done), so for a
// popup that closes by itself, turn Show When Run off and use the banner.
// The screenshot is read and thrown away: it isn't saved anywhere.

import AppIntents
import SwiftUI
import UIKit
import UserNotifications
import CoreLocation

struct CheckTripOfferIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Trip Offer"
    static var description = IntentDescription(
        "Reads a trip offer from a screenshot and shows at a glance whether it meets your TripCheck minimums. Put it straight after Take Screenshot.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Screenshot", supportedTypeIdentifiers: ["public.image"],
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var screenshot: IntentFile?

    /// Alternative input: text from Apple's "Extract Text from Image" action.
    @Parameter(title: "Text")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check the trip offer in \(\.$screenshot)") {
            \.$text
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let words = await readWords()
        let settings = TripSettings.saved()
        let now = Date()

        guard let offer = OfferReader.parse(words) else {
            let looked = OfferReader.looksLikeOffer(words)
            let message = looked ? "Can't read this offer. Check it yourself." : "No trip offer found in this screenshot."
            if settings.shortcutBanner {
                await ShortcutBanner.post(title: "⚠️ CAN'T READ", body: message, closeAfter: settings.shortcutPopupSeconds)
            }
            let image = OverlayRenderer.render(.unreadable, settings: settings)
            return .result(view: OverlaySnippet(image: image, fallback: message))
        }

        let verdict = evaluate(offer, settings)
        HistoryStore.shared.addFromShortcut(offer, at: now, location: ShortcutLocation.current(near: now))
        AppModel.current?.showShortcutOffer(offer)

        let words2 = ShortcutBanner.words(offer, verdict, settings)
        if settings.shortcutBanner {
            await ShortcutBanner.post(title: words2.title, body: words2.body, closeAfter: settings.shortcutPopupSeconds)
        }
        let image = OverlayRenderer.render(.offer(offer, verdict), settings: settings)
        return .result(view: OverlaySnippet(image: image, fallback: words2.body))
    }

    /// The words on the screenshot (read on the phone), or the text passed in.
    private func readWords() async -> String {
        if let file = screenshot, let image = UIImage(data: file.data)?.cgImage {
            return await Task.detached(priority: .userInitiated) { ScreenText.read(image) }.value
        }
        return text ?? ""
    }
}

/// The result panel Shortcuts shows at the top of the screen: the same picture as the
/// floating window.
struct OverlaySnippet: View {
    let image: CGImage?
    let fallback: String

    var body: some View {
        if let image = image {
            Image(uiImage: UIImage(cgImage: image))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(6)
        } else {
            Text(fallback)
                .font(.headline)
                .padding()
        }
    }
}

/// Where the driver is: the app's own recent positions if it's running, otherwise the
/// iPhone's last known position if it's recent.
enum ShortcutLocation {
    @MainActor
    static func current(near date: Date) -> CLLocation? {
        if let fix = AppModel.current?.location.location(near: date) {
            return fix
        }
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
              let known = manager.location,
              abs(known.timestamp.timeIntervalSince(date)) <= 600,
              known.horizontalAccuracy >= 0, known.horizontalAccuracy <= 200 else { return nil }
        return known
    }
}

/// The notification banner: slides down for a few seconds, then away. Colour coded with
/// coloured circles, since a banner can't have coloured text.
enum ShortcutBanner {
    static let identifier = "tripcheck.shortcut.result"

    static func circle(_ c: Check) -> String {
        switch c {
        case .pass: return "🟢"
        case .near, .unknown: return "🟠"
        case .fail: return "🔴"
        }
    }

    static func words(_ o: Offer, _ v: Verdict, _ s: TripSettings) -> (title: String, body: String) {
        let price = String(format: "£%.2f", shownPrice(o, s))
        var title = "\(circle(v.overall)) \(OverlayRenderer.word(v.overall))  \(price)"
        if !v.fareInRange { title += "  (outside fare range)" }
        let mile = v.perMile.map { String(format: "£%.2f", $0) } ?? "?"
        let hour = v.perHour.map { String(format: "£%.2f", $0) } ?? "?"
        let rating = v.rating.map { String(format: "%.2f", $0) } ?? "new"
        let body = "\(circle(v.mile)) \(mile)/mile   \(circle(v.hour)) \(hour)/hour   \(circle(v.ratingCheck)) \(rating) rating"
        return (title, body)
    }

    /// Replaces the previous result, so they don't pile up in Notification Centre, and takes
    /// the banner away after `closeAfter` seconds.
    static func post(title: String, body: String, closeAfter: Double) async {
        let center = UNUserNotificationCenter.current()
        center.delegate = BannerPresenter.shared
        let permission = await center.notificationSettings()
        guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional
                || permission.authorizationStatus == .ephemeral else { return }
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "offers"
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
        await scheduleClose(after: closeAfter)
    }

    /// Each banner gets a number, so an older banner's timer can't close a newer one.
    /// Only used on the main thread.
    private static var closeToken = 0

    /// Removes the banner (from the screen and Notification Centre) after `seconds`. A short
    /// background task keeps TripCheck awake that long after the shortcut has finished, so the
    /// shortcut itself ends straight away and the button can be tapped again.
    @MainActor
    static func scheduleClose(after seconds: Double) {
        closeToken += 1
        let token = closeToken
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "TripCheck banner") {
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, seconds)) {
            if token == closeToken {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            }
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
        }
    }

    /// Asks once for permission to show banners (from the Shortcut section in the app).
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = BannerPresenter.shared
        return (try? await center.requestAuthorization(options: [.alert])) ?? false
    }
}

/// Shows the banner even when TripCheck itself is on screen.
final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BannerPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
