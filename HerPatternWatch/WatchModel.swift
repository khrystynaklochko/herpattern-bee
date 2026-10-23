import Combine
import Foundation

struct BeeImportSummary: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case createdAt = "created_at"
    }
}

/// Entirely local watch state. Each read/write goes to the *shared* HerPattern API.
/// Independent of iPhone runtime; all data comes from the shared HTTPS API.
@MainActor final class WatchModel: ObservableObject {
    @Published var signedIn = false
    @Published var loading = false
    @Published var error: String?
    @Published var displayName = ""
    @Published var lastBurden = "—"
    @Published var forecastBurden = "—"
    @Published var beeCount = 0
    @Published var beeImports: [BeeImportSummary] = []
    @Published var beeObservationSummary = "No confirmed Bee symptom observations"
    @Published var beeLastSyncedAt: Date?
    @Published var beeConnected = false
    @Published var beeTasks: [BeeWatchTask] = []
    @Published var selectedBeeTaskIDs: Set<String> = []
    @Published var beeConversations: [BeeWatchConversation] = []
    @Published var beeUtterances: [BeeWatchUtterance] = []
    @Published var selectedBeeUtterance: BeeWatchUtterance?
    @Published var beeOwnStatement = false
    @Published var beeNoteDraft = ""
    @Published var beeNotePreview: [String: Any]?
    @Published var beeDraft = ""
    @Published var beeReviewedPlan: String?
    @Published var beeStatus: String?
    @Published var beeLoading = false
    @Published var currentDay = ""
    @Published var burden = 5
    @Published var reviewed = false
    @Published var saved = false
    @Published var sensorState = "Not read"
    @Published var measured: [String: Double] = [:]
    @Published var pocketResult: PocketResult?
    @Published var pendingCount = 0
    @Published var syncConsent = false // explicitly opted in per device/session
    @Published var painAnswer: String?
    @Published var lastMeasuredAt: Date?


    init() { Task { await restore() } }

    func restore() async {
        signedIn = await WatchAPI.shared.hasSession()
        beeConnected = await BeeWatchAPI.shared.hasToken()
        if beeConnected { await refreshBeeDirect() }
        if signedIn { await reload() }
    }

    func connectBee(token: String) async {
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            try await BeeWatchAPI.shared.connect(token: token)
            beeConnected = true
            try await loadBeeTasks()
            beeStatus = "Bee connected on this watch."
        } catch { beeStatus = error.localizedDescription }
    }

    func disconnectBee() async {
        await BeeWatchAPI.shared.disconnect()
        beeConnected = false
        beeTasks = []
        selectedBeeTaskIDs = []
        beeStatus = "Bee disconnected from this watch."
    }

    func refreshBeeDirect() async {
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            try await loadBeeTasks()
            beeConnected = true
            beeStatus = "Loaded \(beeTasks.count) Bee tasks."
        } catch { beeStatus = error.localizedDescription }
    }

    private func loadBeeTasks() async throws {
        beeTasks = try await BeeWatchAPI.shared.tasks()
        selectedBeeTaskIDs = selectedBeeTaskIDs.intersection(Set(beeTasks.map(\.id)))
    }

    func toggleBeeTask(_ id: String) {
        if selectedBeeTaskIDs.contains(id) { selectedBeeTaskIDs.remove(id) }
        else { selectedBeeTaskIDs.insert(id) }
    }

    func loadBeeConversations() async {
        beeLoading = true
        beeStatus = nil
        beeConversations = []
        beeUtterances = []
        selectedBeeUtterance = nil
        defer { beeLoading = false }
        do {
            beeConversations = try await BeeWatchAPI.shared.conversations()
            if beeConversations.isEmpty { beeStatus = "No Bee conversations were returned." }
        } catch { beeStatus = error.localizedDescription }
    }

    func loadBeeUtterances(conversationID: String) async {
        beeLoading = true
        beeStatus = nil
        beeUtterances = []
        selectedBeeUtterance = nil
        beeNoteDraft = ""
        beeOwnStatement = false
        beeNotePreview = nil
        defer { beeLoading = false }
        do { beeUtterances = try await BeeWatchAPI.shared.utterances(conversationID: conversationID) }
        catch { beeStatus = error.localizedDescription }
    }

    func selectBeeUtterance(_ utterance: BeeWatchUtterance) {
        selectedBeeUtterance = utterance
        beeNoteDraft = ""
        beeOwnStatement = false
        beeNotePreview = nil
    }

    func prepareBeeDailyNote() async {
        let text = beeNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard beeOwnStatement, selectedBeeUtterance != nil,
              !text.isEmpty, text.count <= 240, !currentDay.isEmpty else {
            beeStatus = "Confirm this is your statement and enter a short note (up to 240 characters)."
            return
        }
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            let result = try await WatchAPI.shared.request(
                "/assistant/actions",
                method: "POST",
                payload: [
                    "action": "save_note",
                    "args": ["date": currentDay, "text": text],
                    "confirm": false
                ]
            )
            guard let data = result as? [String: Any],
                  let preview = data["preview"] as? [String: Any],
                  !String(describing: preview["summary"] ?? "").isEmpty else {
                throw WatchAPIError(message: "HerPattern could not prepare a daily-note preview.")
            }
            beeNotePreview = preview
        } catch { beeStatus = error.localizedDescription }
    }

    func confirmBeeDailyNote() async {
        guard let preview = beeNotePreview, let args = preview["args"] else { return }
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            let result = try await WatchAPI.shared.request(
                "/assistant/actions",
                method: "POST",
                payload: ["action": "save_note", "args": args, "confirm": true]
            )
            guard let data = result as? [String: Any], data["saved"] as? Bool == true else {
                throw WatchAPIError(message: "HerPattern did not confirm that the note was saved.")
            }
            beeNotePreview = nil
            beeNoteDraft = ""
            selectedBeeUtterance = nil
            beeOwnStatement = false
            beeStatus = "Your note was added to today's HerPattern daily log."
        } catch { beeStatus = error.localizedDescription }
    }

    func importSelectedBeeTasks() async {
        let selected = beeTasks.filter { selectedBeeTaskIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            let items: [[String: Any]] = selected.map {
                ["source_id": $0.id, "kind": "todo", "title": $0.text, "body": ""]
            }
            let result = try await WatchAPI.shared.request(
                "/bee", method: "POST", payload: ["consent": true, "items": items]
            )
            guard let data = result as? [String: Any],
                  let imported = data["imported"] as? Int else {
                throw WatchAPIError(message: "HerPattern did not confirm the Bee import.")
            }
            beeStatus = "Imported \(imported) selected Bee tasks into HerPattern."
            selectedBeeTaskIDs = []
            try await loadBeeData()
        } catch { beeStatus = error.localizedDescription }
    }

    func reviewBeePlan() {
        let text = beeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 240 else {
            beeStatus = "Task text must be between 1 and 240 characters."
            return
        }
        beeReviewedPlan = text
        beeStatus = nil
    }

    func sendReviewedBeePlan() async {
        guard let text = beeReviewedPlan else { return }
        beeLoading = true
        beeStatus = nil
        defer { beeLoading = false }
        do {
            try await BeeWatchAPI.shared.createTask(text: text)
            beeDraft = ""
            beeReviewedPlan = nil
            try await loadBeeTasks()
            beeStatus = "Task sent to Bee."
        } catch { beeStatus = error.localizedDescription }
    }

    func signIn(email: String, password: String) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            try await WatchAPI.shared.signIn(email: email, password: password)
            signedIn = true
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    func signOut() async {
        await WatchAPI.shared.signOut()
        signedIn = false
        displayName = ""; lastBurden = "—"; forecastBurden = "—"
        beeCount = 0; beeImports = []; beeObservationSummary = "No confirmed Bee symptom observations"
        beeLastSyncedAt = nil; currentDay = ""; reviewed = false; saved = false
        error = nil
        pocketResult = nil; measured = [:]; syncConsent = false; painAnswer = nil
        WatchEventOutbox.shared.clear()
    }

    func reload() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let value = try await WatchAPI.shared.request("/assistant/context")
            guard let context = value as? [String: Any],
                  let date = context["today"] as? String else {
                throw WatchAPIError(message: "Invalid context returned")
            }
            currentDay = date
            displayName = context["name"] as? String ?? ""
            let days = context["recent_days"] as? [[String: Any]] ?? []
            if let last = days.first, let score = last["burden"] as? NSNumber {
                lastBurden = String(format: "%.1f/10", score.doubleValue)
            } else { lastBurden = "—" }
            let forecast = context["forecast"] as? [[String: Any]] ?? []
            if let tomorrow = forecast.first(where: { ($0["date"] as? String ?? "") > date }),
               let score = tomorrow["burden"] as? NSNumber {
                forecastBurden = String(format: "%.1f/10", score.doubleValue)
            } else { forecastBurden = "—" }
            try await loadBeeData()
        } catch { self.error = error.localizedDescription }
    }

    func refreshBeeImports() async {
        loading = true; error = nil
        defer { loading = false }
        do { try await loadBeeData() }
        catch { self.error = error.localizedDescription }
    }

    private func loadBeeData() async throws {
        // Bee is connected on iPhone; the watch reads only owner-authorized
        // imports from HerPattern, never Bee credentials or raw conversations.
        guard let items = try await WatchAPI.shared.request("/bee") as? [[String: Any]] else {
            throw WatchAPIError(message: "Unexpected Bee import response")
        }
        let data = try JSONSerialization.data(withJSONObject: items)
        beeImports = try JSONDecoder().decode([BeeImportSummary].self, from: data)
        beeCount = beeImports.count
        beeLastSyncedAt = Date()

        // The watch gets confirmed short observations only, never Bee transcripts.
        if let observations = try? await WatchAPI.shared.request("/bee/observations") as? [[String: Any]],
           let first = observations.first {
            let day = first["local_date"] as? String ?? ""
            let label = (first["symptom"] as? String ?? "symptom").replacingOccurrences(of: "_", with: " ")
            beeObservationSummary = "\(day): \(label) · self-reported"
        } else { beeObservationSummary = "No confirmed Bee symptom observations" }
    }


    func readSensors() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let values = try await WatchHealthReader.shared.collect()
            measured = values.measured
            lastMeasuredAt = values.capturedAt
            pocketResult = PocketSmallAI.infer(values)
            sensorState = "HealthKit · readings with historical baseline"
            if syncConsent {
                let features = values.values.compactMapValues { $0 }
                let payload = features.mapValues { String($0) }
                WatchEventOutbox.shared.enqueue(WearableEvent(kind: "sensor_summary", payload: payload))
                if let result = pocketResult {
                    WatchEventOutbox.shared.enqueue(WearableEvent(kind: "inference", payload: [
                        "state": result.state, "recovery": result.recovery.map(String.init) ?? "",
                        "confidence": String(result.confidence), "model": result.version,
                        "missing": result.missing.joined(separator: ",")
                    ]))
                }
                await syncOutbox()
            }
        } catch { sensorState = "HealthKit unavailable"; self.error = error.localizedDescription }
    }

    func submitPain(_ answer: String) async {
        guard ["No", "Mild", "Moderate", "Strong"].contains(answer) else { return }
        painAnswer = answer
        if syncConsent {
            WatchEventOutbox.shared.enqueue(WearableEvent(kind: "pain_context", payload: [
                "question": "pelvic_pain_today", "answer": answer
            ]))
            await syncOutbox()
        }
    }

    func syncOutbox() async {
        guard syncConsent else { return }
        do { try await WatchEventOutbox.shared.flush() }
        catch { self.error = "Offline — wearable records remain encrypted on this watch" }
        pendingCount = WatchEventOutbox.shared.pending.count
    }

    func createContinuity() async {
        guard let r = pocketResult, let when = lastMeasuredAt else { return }
        // Minimal evidence bundle, not a 72-hour raw-data export. Model version,
        // observed timestamp, missingness and patient response remain explicit.
        let payload: [String: String] = [
            "model": r.version, "state": r.state,
            "recovery": r.recovery.map(String.init) ?? "",
            "confidence": String(r.confidence),
            "measured_at": ISO8601DateFormatter().string(from: when),
            "missing": r.missing.joined(separator: ","),
            "contributors": r.contributors.joined(separator: ","),
            "pain": painAnswer ?? "not_reported"
        ]
        guard syncConsent else {
            error = "Enable sharing to send this short continuity summary"
            return
        }
        WatchEventOutbox.shared.enqueue(WearableEvent(kind: "continuity_record", payload: payload))
        await syncOutbox()
    }

    func setSyncConsent(_ enabled: Bool) async {
        syncConsent = enabled
        if enabled { await syncOutbox() }
        // Turning off stops future exports; records already uploaded can be
        // removed from the privacy screen via the authenticated DELETE endpoint.
    }

    func clearWearableCloudHistory() async {
        do {
            _ = try await WatchAPI.shared.request("/wearables/events", method: "DELETE")
            WatchEventOutbox.shared.clear()
            pendingCount = 0
        } catch { self.error = error.localizedDescription }
    }

    func review() {
        reviewed = true
        saved = false
        error = nil
    }

    func commit() async {
        guard reviewed, (0...10).contains(burden), !currentDay.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            // Patches only the burden score; other daily symptoms/treatments/notes remain untouched.
            _ = try await WatchAPI.shared.request("/checkins/\(currentDay)/burden", method: "PATCH", payload: [
                "overall_burden": burden
            ])
            saved = true
            reviewed = false
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}
