// How the screen broadcast reader (a separate process) tells the app what it sees:
// it writes a small file into the shared "app group" folder, then rings a system-wide bell
// (a Darwin notification). The app also re-reads the file every second as a backup.

import Foundation

struct ReaderState: Codable, Equatable {
    var broadcasting: Bool = false
    var offer: Offer? = nil
    var unreadable: Bool = false
    var updated: Date = Date()
}

enum SharedChannel {
    static let notificationName = "uk.tripcheck.reader-changed"

    /// The shared folder. Tries the group named in Info.plist, then "group.<app bundle id>",
    /// in case the signing tool renamed things.
    static let containerURL: URL? = {
        var candidates: [String] = []
        if let named = Bundle.main.object(forInfoDictionaryKey: "TripCheckAppGroup") as? String {
            candidates.append(named)
        }
        if var id = Bundle.main.bundleIdentifier {
            if id.hasSuffix(".Broadcast") {
                id = String(id.dropLast(".Broadcast".count))
            }
            candidates.append("group." + id)
        }
        for group in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return url
            }
        }
        return nil
    }()

    /// False if the app and the reader can't share anything (the app group was lost when signing).
    static var isConnected: Bool { containerURL != nil }

    private static var stateURL: URL? {
        containerURL?.appendingPathComponent("reader-state.json")
    }

    static func write(_ state: ReaderState) {
        guard let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil, nil, true)
    }

    static func read() -> ReaderState? {
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReaderState.self, from: data)
    }
}
