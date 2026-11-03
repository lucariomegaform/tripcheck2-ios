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

    /// The shared folder's name and location, if signing kept one. Tries, in order: the groups
    /// the phone's install profile actually grants (signing tools sometimes rename them), the
    /// group named in Info.plist, then "group.<app bundle id>".
    static let container: (group: String, url: URL)? = {
        var candidates = provisionedGroups()
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
                return (group: group, url: url)
            }
        }
        return nil
    }()

    static var containerURL: URL? { container?.url }

    /// The shared folder's name, for the app's connection details.
    static var groupName: String? { container?.group }

    /// False if signing left out the shared folder. TripCheck then uses the direct link instead.
    static var isConnected: Bool { container != nil }

    /// The app groups listed in this bundle's install profile (embedded.mobileprovision).
    /// The profile is a signed file with a readable list of permissions inside it.
    static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex)
        else { return [] }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        // Prefer TripCheck's own group if there are several.
        return groups.sorted { a, b in
            a.lowercased().contains("tripcheck") && !b.lowercased().contains("tripcheck")
        }
    }

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
