// Apple's screen broadcast button. Apps can't start a screen broadcast themselves; they can
// only show Apple's "Screen Broadcast" sheet. TripCheck keeps Apple's button hidden and
// presses it when the driver taps the big "Start reading offers" button.

import ReplayKit
import SwiftUI
import UIKit

final class BroadcastPicker {
    static let shared = BroadcastPicker()

    let view: RPSystemBroadcastPickerView

    private init() {
        view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.showsMicrophoneButton = false
        // Pre-select TripCheck's reader in Apple's sheet.
        view.preferredExtension = BroadcastPicker.readerBundleID()
    }

    /// Finds the reader's ID inside the app, so it still works if the signing tool renamed it.
    private static func readerBundleID() -> String? {
        guard let folder = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return nil }
        for item in items where item.pathExtension == "appex" {
            guard let bundle = Bundle(url: item),
                  let ext = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
                  (ext["NSExtensionPointIdentifier"] as? String) == "com.apple.broadcast-services-upload"
            else { continue }
            return bundle.bundleIdentifier
        }
        return nil
    }

    /// Opens Apple's Screen Broadcast sheet (it shows "Start Broadcast" or "Stop Broadcast").
    func open(attempt: Int = 0) {
        // Apple's button can only open its sheet while it's part of the screen. Just after
        // switching tabs or coming back to TripCheck it may not be yet, so try again briefly.
        guard view.window != nil, let button = BroadcastPicker.findButton(in: view) else {
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.open(attempt: attempt + 1) }
            }
            return
        }
        button.sendActions(for: .allTouchEvents)
    }

    private static func findButton(in v: UIView) -> UIButton? {
        if let button = v as? UIButton { return button }
        for sub in v.subviews {
            if let button = findButton(in: sub) { return button }
        }
        return nil
    }
}

/// Puts Apple's (hidden) button into the screen, which it needs to be able to open its sheet.
struct BroadcastPickerHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        holder.addSubview(BroadcastPicker.shared.view)
        holder.clipsToBounds = true
        return holder
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
