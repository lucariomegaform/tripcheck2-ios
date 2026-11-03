// The "direct link": a private connection inside the phone (to 127.0.0.1, the phone talking
// to itself) from the screen broadcast reader to the app. It needs no special permission, so
// it still works when signing with a free Apple ID leaves out the shared app group.
// Each message is one line of JSON (a ReaderState).

import Foundation
import Network

enum LoopbackLink {
    static let port: NWEndpoint.Port = 47811
}

/// Used by the screen broadcast reader to send what it sees to the app.
final class LoopbackSender {
    private let queue = DispatchQueue(label: "uk.tripcheck.loopback.send")
    private var connection: NWConnection?

    func send(_ state: ReaderState) {
        guard var data = try? JSONEncoder().encode(state) else { return }
        data.append(0x0A)
        queue.async {
            let connection = self.currentConnection()
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.queue.async { self?.reset() }
                }
            })
        }
    }

    func close() {
        queue.async { self.reset() }
    }

    // Always called on `queue`.
    private func currentConnection() -> NWConnection {
        if let existing = connection { return existing }
        let c = NWConnection(host: "127.0.0.1", port: LoopbackLink.port, using: .tcp)
        c.stateUpdateHandler = { [weak self, weak c] state in
            switch state {
            case .failed, .cancelled, .waiting:
                // The app isn't listening right now. Drop this connection; the next
                // message (at least every few seconds) tries again.
                self?.queue.async {
                    if let c = c, self?.connection === c { self?.reset() }
                }
            default:
                break
            }
        }
        connection = c
        c.start(queue: queue)
        return c
    }

    private func reset() {
        connection?.cancel()
        connection = nil
    }
}
