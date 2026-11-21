// Delivering what telemetry queued: the queue sent to the collector oldest
// first, each event dropped once the collector accepts it, and the outcome
// kept in `delivery.json` (docs/telemetry.md).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension WisentTelemetry {
    /// Send the queue on a detached task; `settled` runs when the attempt ends.
    public func flushInBackground(settled: @escaping @Sendable () -> Void = {}) {
        Task.detached(priority: .utility) { [self] in
            if let stopped = await self.flush().stopped { Self.say(stopped) }
            settled()
        }
    }

    /// What one flush did: how many went, how many wait, and why it stopped.
    public struct Delivered: Sendable {
        public let sent: Int
        public let remaining: Int
        public let stopped: String?
        public let skipped: String?
    }

    /// Send every queued event oldest first, dropping each the collector
    /// accepted; the first refusal or transport error stops it, and the
    /// outcome is kept in `delivery.json`.
    public func flush() async -> Delivered {
        let events: [[String: Any]]
        do { events = try queued() } catch { return Delivered(sent: 0, remaining: 0, stopped: "\(error)", skipped: nil) }
        if Self.doNotTrack { return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "DO_NOT_TRACK") }
        // A consent file telemetry did not write sends nothing, and the
        // flush says why instead of reading it as unanswered.
        let chosen: TelemetryLevel?
        do {
            chosen = try level()
        } catch {
            let delivered = Delivered(sent: 0, remaining: events.count, stopped: "\(error)", skipped: nil)
            keep(delivered)
            return delivered
        }
        switch chosen {
        case nil: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "unanswered")
        case .off?: return Delivered(sent: 0, remaining: events.count, stopped: nil, skipped: "off")
        default: break
        }
        let target: URL
        do {
            target = try collector().url
        } catch {
            let delivered = Delivered(sent: 0, remaining: events.count, stopped: "\(error)", skipped: nil)
            keep(delivered)
            return delivered
        }
        var sent = 0
        var stopped: String?
        for (index, event) in events.enumerated() {
            let eventID = event["eventId"] as? String ?? ""
            let waiting = events.count - index
            let values = [
                "event": eventID, "collector": target.absoluteString, "queued": String(waiting),
                "app": product.appID, "product": product.id, "accepted": "{\"ok\": true}",
            ]
            switch await post(event, to: target) {
            case .accepted:
                sent += 1
                guard let path = file("queue")?.appendingPathComponent("\(eventID).json") else { continue }
                do {
                    try remove(path, what: "the sent event \(eventID)")
                    continue
                } catch {
                    stopped = "\(error)"
                }
            case .refused(let status, let answer):
                stopped = OwnFailures.telemetryDeliverCollectorRefused.refusal(values.merging(["status": String(status), "answer": answer]) { $1 })
            case .failed(let status, let answer):
                stopped = OwnFailures.telemetryDeliverCollectorFailed.refusal(values.merging(["status": String(status), "answer": answer]) { $1 })
            case .notCollector(let status, let answer):
                stopped = OwnFailures.telemetryDeliverCollectorAnswerUnreadable.refusal(values.merging(["status": String(status), "answer": answer]) { $1 })
            case .unreachable(let cause):
                stopped = OwnFailures.telemetryDeliverCollectorUnreachable.refusal(values.merging(["why": cause]) { $1 })
            }
            break
        }
        let delivered = Delivered(sent: sent, remaining: events.count - sent, stopped: stopped, skipped: nil)
        keep(delivered)
        return delivered
    }

    private enum Answer {
        case accepted
        case refused(Int, String)
        case failed(Int, String)
        case notCollector(Int, String)
        case unreachable(String)
    }

    private func post(_ event: [String: Any], to url: URL) async -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: event)
        let session = self.session
        return await withCheckedContinuation { (answered: CheckedContinuation<Answer, Never>) in
            session.dataTask(with: request) { data, response, error in
                if let error { return answered.resume(returning: .unreachable(error.explained)) }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                if (200..<300).contains(status), object?["ok"] as? Bool == true {
                    return answered.resume(returning: .accepted)
                }
                // A server error is the collector's own failure, whatever its
                // body; below that, the collector refuses with a JSON object.
                if status >= 500 {
                    return answered.resume(returning: .failed(status, body))
                }
                if !(200..<300).contains(status), object != nil {
                    return answered.resume(returning: .refused(status, body))
                }
                answered.resume(returning: .notCollector(status, body))
            }.resume()
        }
    }

    private func keep(_ delivered: Delivered) {
        guard let path = file("delivery.json") else { return }
        let record: [String: Any] = [
            "at": Self.localNow(),
            "sent": delivered.sent,
            "remaining": delivered.remaining,
            "stopped": delivered.stopped.map { ["detail": $0] } as Any? ?? NSNull(),
            "skipped": delivered.skipped as Any? ?? NSNull(),
        ]
        do { try writeObject(record, to: path, what: "the last delivery") } catch { Self.say(error) }
    }
}
