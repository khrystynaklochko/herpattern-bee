import Foundation

struct WearableEvent: Codable, Identifiable {
    let event_id: String
    let source: String
    let kind: String
    let occurred_at: String
    let payload: [String: String]
    var id: String { event_id }

    init(kind: String, payload: [String: String]) {
        self.event_id = UUID().uuidString.lowercased()
        self.source = "watchos"
        self.kind = kind
        self.occurred_at = ISO8601DateFormatter().string(from: Date())
        self.payload = payload
    }
}

// Offline event outbox stays on-device in ThisDeviceOnly Keychain until the
// patient explicitly enables secure sync and a POST succeeds.
@MainActor final class WatchEventOutbox {
    static let shared = WatchEventOutbox()
    private let account = "wearable-event-outbox"
    private(set) var pending: [WearableEvent] = []
    init() { pending = (WatchSecureStore.read(account: account)).flatMap { try? JSONDecoder().decode([WearableEvent].self, from: $0) } ?? [] }
    func enqueue(_ event: WearableEvent) {
        pending.append(event)
        persist()
    }
    func clear() { pending = []; persist() }
    func flush() async throws {
        for event in pending {
            let encoded = try JSONEncoder().encode(event)
            let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
            _ = try await WatchAPI.shared.request("/wearables/events", method: "POST", payload: payload)
            pending.removeAll { $0.event_id == event.event_id }
            persist() // durable idempotent sync; never reassign event IDs
        }
    }
    private func persist() {
        if pending.isEmpty { WatchSecureStore.clear(account: account) }
        else if let data = try? JSONEncoder().encode(pending) { try? WatchSecureStore.save(data, account: account) }
    }
}
