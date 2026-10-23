import SwiftUI

@main struct HerPatternWatchApp: App {
    var body: some Scene { WindowGroup { WatchRootView() } }
}

private enum HPColors {
    static let violet = Color(red: 0.48, green: 0.40, blue: 0.85)
    static let lavender = Color(red: 0.84, green: 0.81, blue: 0.99)
}

struct WatchRootView: View {
    @StateObject private var model = WatchModel()
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Group {
            if model.signedIn { dashboard }
            else { login }
            }
        }
    }

    private var login: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Label("HerPattern", systemImage: "waveform.path.ecg")
                    .foregroundStyle(HPColors.lavender).font(.headline)
                Text("Sign in on your watch")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Button("Sign in") {
                    Task { await model.signIn(email: email, password: password); password = "" }
                }
                .disabled(model.loading || email.isEmpty || password.isEmpty)
                .tint(HPColors.violet)
                if model.loading { ProgressView() }
                if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption2) }
                Text("Uses your HerPattern account. The iPhone app is not required.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.vertical, 10)
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(HPColors.lavender)
                    Text("HerPattern").font(.headline)
                }
                Text(model.displayName.isEmpty ? "Your daily pattern" : "Hello, \(model.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    reading("Last check-in", model.lastBurden, "heart.text.square")
                    reading("Forecast", model.forecastBurden, "cloud.sun")
                }
                NavigationLink(destination: BeeImportsWatchView(model: model)) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(HPColors.lavender)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.beeCount) Bee items imported").font(.caption2)
                            Text("View synced Bee context").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HPColors.violet.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                Text(model.beeObservationSummary).font(.caption2)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                NavigationLink(destination: PocketWatchView(model: model)) { Text("Wearable intelligence") }
                    .tint(HPColors.violet)
                Text("How is your burden?").font(.footnote).fontWeight(.semibold)
                Text("\(model.burden) / 10").font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(HPColors.lavender)
                Slider(value: Binding(
                    get: { Double(model.burden) },
                    set: { model.burden = Int($0.rounded()); model.reviewed = false; model.saved = false }
                ), in: 0...10, step: 1).tint(HPColors.violet)
                if model.saved {
                    Label("Saved to HerPattern", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                } else if model.reviewed {
                    Text("Save burden \(model.burden)/10 for \(model.currentDay)?").font(.caption2)
                    Button("Confirm and save") { Task { await model.commit() } }.tint(HPColors.violet)
                } else {
                    Button("Review check-in") { model.review() }.tint(HPColors.violet)
                }
                if let error = model.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                if model.loading { ProgressView() }
                Button { Task { await model.reload() } } label: {
                    Label("Sync with HerPattern", systemImage: "arrow.clockwise").font(.caption2)
                }.buttonStyle(.plain).foregroundStyle(HPColors.lavender)
                Button("Sign out") { Task { await model.signOut() } }
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Forecasts are estimates, not medical advice.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.vertical, 10)
        }
        .refreshable { await model.reload() }
    }

    private func reading(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage).font(.caption).foregroundStyle(HPColors.lavender)
            Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
         .padding(9).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BeeImportsWatchView: View {
    @ObservedObject var model: WatchModel
    @State private var beeToken = ""
    @State private var confirmImport = false
    @State private var confirmSendPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Label("Bee + HerPattern", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(HPColors.lavender)
                if !model.beeConnected {
                    Text("Connect directly to Bee using your Developer Mode API token.")
                        .font(.caption)
                    SecureField("Bee developer token", text: $beeToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(model.beeLoading ? "Connecting…" : "Connect Bee") {
                        Task {
                            await model.connectBee(token: beeToken)
                            if model.beeConnected { beeToken = "" }
                        }
                    }
                    .disabled(model.beeLoading || beeToken.isEmpty)
                    .tint(HPColors.violet)
                } else {
                    Text("Direct Bee connection · token is stored only in this watch's Keychain.")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Button("Refresh Bee tasks") { Task { await model.refreshBeeDirect() } }
                        .disabled(model.beeLoading)
                    if model.beeTasks.isEmpty {
                        Text("No Bee tasks returned.").font(.caption)
                    } else {
                        Text("Select Bee tasks to import into HerPattern")
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(model.beeTasks) { task in
                            Button {
                                model.toggleBeeTask(task.id)
                            } label: {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: model.selectedBeeTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(HPColors.lavender)
                                    Text(task.text).font(.caption).lineLimit(3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Review import to HerPattern") { confirmImport = true }
                            .disabled(model.selectedBeeTaskIDs.isEmpty || model.beeLoading)
                            .tint(HPColors.violet)
                    }

                    Divider()
                    Text("Send a plan to Bee").font(.caption.bold())
                    if let reviewed = model.beeReviewedPlan {
                        Text("Bee will receive:").font(.caption2).foregroundStyle(.secondary)
                        Text(reviewed).font(.caption)
                        Button("Edit plan") { model.beeReviewedPlan = nil }
                        Button("Confirm and send to Bee") { confirmSendPlan = true }
                            .tint(HPColors.violet)
                    } else {
                        TextField("Write a task", text: $model.beeDraft, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Review plan") { model.reviewBeePlan() }
                            .disabled(model.beeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || model.beeDraft.count > 240)
                    }

                    Button("Disconnect Bee") { Task { await model.disconnectBee() } }
                        .font(.caption2).foregroundStyle(.orange)
                }

                Divider()
                Text("HerPattern imports").font(.caption.bold())
                Text("\(model.beeCount) previously imported items")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(model.beeObservationSummary)
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Refresh HerPattern imports") {
                    Task { await model.refreshBeeImports() }
                }
                .disabled(model.loading)
                if model.loading || model.beeLoading { ProgressView() }
                if let status = model.beeStatus {
                    Text(status).font(.caption2).foregroundStyle(.orange)
                }
                if let error = model.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                Text("Only selected Bee tasks are copied to HerPattern. A plan is sent to Bee only after you review and confirm it.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(9)
        }
        .navigationTitle("Bee")
        .confirmationDialog(
            "Import \(model.selectedBeeTaskIDs.count) selected Bee tasks into your HerPattern account?",
            isPresented: $confirmImport
        ) {
            Button("Confirm import") { Task { await model.importSelectedBeeTasks() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the selected task text and IDs are copied. Bee tasks are context, not health measurements.")
        }
        .confirmationDialog(
            "Send this exact plan to Bee?",
            isPresented: $confirmSendPlan
        ) {
            Button("Confirm and send") { Task { await model.sendReviewedBeePlan() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.beeReviewedPlan ?? "")
        }
    }
}


private struct PocketWatchView: View {
    @ObservedObject var model: WatchModel
    private var result: PocketResult? { model.pocketResult }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Personal baseline").font(.headline).foregroundStyle(HPColors.lavender)
                if let result {
                    Text(result.state == "insufficient_data" ? "Not enough data" :
                         result.state == "within_personal_pattern" ? "Within your pattern" : "Pattern changed")
                        .font(.title3).bold()
                    if let recovery = result.recovery {
                        HStack { Text("Recovery"); Spacer(); Text("\(recovery)/100").bold() }
                        HStack { Text("Stress"); Spacer(); Text("\(result.stress ?? 0)/100") }
                    }
                    Text("Confidence \(Int(result.confidence * 100))% · \(result.version)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if !result.contributors.isEmpty {
                        Text("What changed: \(result.contributors.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if !result.missing.isEmpty {
                        Text("Missing: \(result.missing.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if result.questionRequired && model.painAnswer == nil {
                        Text("Was your pelvic pain stronger today?").font(.footnote).bold()
                        ForEach(["No", "Mild", "Moderate", "Strong"], id: \.self) { option in
                            Button(option) { Task { await model.submitPain(option) } }
                        }
                    }
                } else {
                    Text("Read permitted HealthKit measurements to compare your last day with your earlier personal pattern.")
                        .font(.caption)
                }
                Group {
                    if let bpm = model.measured["hr"] { metric("Heart rate", bpm, "bpm") }
                    if let hrv = model.measured["hrv_sdnn_ms"] { metric("HRV · SDNN", hrv, "ms") }
                    if let rhr = model.measured["rhr_bpm"] { metric("Resting HR", rhr, "bpm") }
                    if let sleep = model.measured["sleep_minutes"] { metric("Sleep", sleep / 60, "hours") }
                    if let temp = model.measured["wrist_temp_c"] { metric("Wrist temp", temp, "°C") }
                }
                Button("Read HealthKit") { Task { await model.readSensors() } }
                    .tint(HPColors.violet)
                Toggle("Share approved summaries", isOn: Binding(
                    get: { model.syncConsent },
                    set: { choice in Task { await model.setSyncConsent(choice) } }
                )).font(.caption2)
                Text("Pending encrypted records: \(model.pendingCount)").font(.caption2)
                Button("Save continuity summary") { Task { await model.createContinuity() } }
                    .disabled(!model.syncConsent || result == nil)
                Button("Retry secure sync") { Task { await model.syncOutbox() } }
                    .disabled(!model.syncConsent)
                Button("Delete uploaded wearable history", role: .destructive) {
                    Task { await model.clearWearableCloudHistory() }
                }.font(.caption2)
                if let error = model.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                Text("Experimental self-understanding only. Not diagnosis, treatment advice or validated recovery prediction.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(9)
        }
    }
    private func metric(_ name: String, _ value: Double, _ unit: String) -> some View {
        HStack { Text(name).font(.caption); Spacer(); Text(String(format: "%.1f %@", value, unit)).font(.caption2) }
    }
}
