// The app's end of the direct link (see LoopbackLink.swift): listens on the phone's own
// private address for messages from the screen broadcast reader.

import Foundation
import Network

final class LoopbackReceiver {
    /// Called on the main thread with each message from the reader.
    var onState: ((ReaderState) -> Void)?

    private let queue = DispatchQueue(label: "uk.tripcheck.loopback.receive")
    private var listener: NWListener?

    /// Starts listening if it isn't already (safe to call often).
    func ensureRunning() {
        queue.async { self.startIfNeeded() }
    }

    // Always called on `queue`.
    private func startIfNeeded() {
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: parameters, on: LoopbackLink.port) else {
            restartSoon()
            return
        }
        l.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        l.stateUpdateHandler = { [weak self, weak l] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async {
                    if let l = l, self?.listener === l {
                        self?.listener = nil
                        self?.restartSoon()
                    }
                }
            default:
                break
            }
        }
        listener = l
        l.start(queue: queue)
    }

    private func restartSoon() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startIfNeeded()
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var pending = buffer
            if let data = data { pending.append(data) }
            // Each message ends with a new line.
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
                if let state = try? JSONDecoder().decode(ReaderState.self, from: line) {
                    DispatchQueue.main.async { self?.onState?(state) }
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self?.receive(on: connection, buffer: pending)
        }
    }
}
