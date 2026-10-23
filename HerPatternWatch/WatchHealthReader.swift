import Foundation
import HealthKit

// Samples are obtained ONLY after the patient approves HealthKit access.
// Never starts a workout to force high-frequency heart rate; background HRV,
// wrist temperature and breathing measures are device/permission dependent.
actor WatchHealthReader {
    static let shared = WatchHealthReader()
    private let health = HKHealthStore()

    private var metrics: [(String, HKQuantityTypeIdentifier, HKUnit)] {
        [
            ("hr", .heartRate, HKUnit.count().unitDivided(by: .minute())),
            ("hrv_sdnn_ms", .heartRateVariabilitySDNN, .secondUnit(with: .milli)),
            ("rhr_bpm", .restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
            ("resp_brpm", .respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
            ("wrist_temp_c", .appleSleepingWristTemperature, .degreeCelsius()),
            ("steps", .stepCount, .count())
        ]
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw WatchAPIError(message: "Health data not available") }
        var read: Set<HKObjectType> = Set(metrics.map { HKObjectType.quantityType(forIdentifier: $0.1)! })
        read.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        try await health.requestAuthorization(toShare: [], read: read)
    }

    private func samples(_ type: HKSampleType, since: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictEndDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1500,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }

    func collect() async throws -> PocketReading {
        try await authorize()
        let now = Date()
        let recent = now.addingTimeInterval(-24 * 3600)
        let past = now.addingTimeInterval(-32 * 24 * 3600)
        let baselineEnd = now.addingTimeInterval(-2 * 24 * 3600)
        var measured: [String: Double] = [:]
        var features: [String: Double?] = [:]
        var sources: [String: String] = [:]
        for (name, identifier, unit) in metrics {
            let type = HKObjectType.quantityType(forIdentifier: identifier)!
            let rows = try await samples(type, since: past).compactMap { $0 as? HKQuantitySample }
            let latest = rows.filter { $0.endDate >= recent }
            let historical = rows.filter { $0.endDate < baselineEnd }
            let mean: ([HKQuantitySample]) -> Double? = { data in
                guard !data.isEmpty else { return nil }
                return data.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) } / Double(data.count)
            }
            if let current = mean(latest) {
                measured[name] = current
                sources[name] = "HealthKit · " + (latest.first?.sourceRevision.source.name ?? "unknown source")
            }
            guard let current = mean(latest), let base = mean(historical), abs(base) > 0.001 else { continue }
            switch name {
            case "hrv_sdnn_ms": features["hrv_delta"] = ((current / base) - 1) / 0.06
            case "rhr_bpm": features["rhr_delta"] = (current - base) / 2.5
            case "resp_brpm": features["resp_delta"] = (current - base) / 0.6
            case "wrist_temp_c": features["temp_delta"] = (current - base) / 0.25
            case "steps": features["activity_load"] = (current - base) / max(4000, base)
            default: break
            }
        }
        // Sleep intervals are not live streams. Compare last night against
        // completed historical nights, then derive a simple fragmentation gap.
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let rows = try await samples(sleepType, since: past).compactMap { $0 as? HKCategorySample }
        let sleep = rows.filter {
            $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
            $0.value != HKCategoryValueSleepAnalysis.awake.rawValue
        }
        let calendar = Calendar.current
        func night(_ day: Date) -> Date { calendar.startOfDay(for: day.addingTimeInterval(-12 * 3600)) }
        let nights = Dictionary(grouping: sleep, by: { night($0.endDate) })
        let totals = nights.mapValues { samples in samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60 }
        let recentNights = totals.filter { $0.key > now.addingTimeInterval(-2 * 24 * 3600) }
        let oldNights = totals.filter { $0.key < now.addingTimeInterval(-2 * 24 * 3600) }
        if let recentMinutes = recentNights.values.max(), oldNights.count >= 5 {
            let baseline = oldNights.values.reduce(0, +) / Double(oldNights.count)
            measured["sleep_minutes"] = recentMinutes
            sources["sleep_minutes"] = "HealthKit · sleep analysis"
            features["sleep_debt"] = (baseline - recentMinutes) / 50
            // Fragmentation counts repeated asleep-to-awake transitions only
            // where awake intervals are present. Do not infer it from HR.
            let awake = rows.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
            let relevant = awake.filter { $0.endDate >= recent && $0.endDate.timeIntervalSince($0.startDate) >= 60 }
            let baselineAwake = awake.filter { $0.endDate < baselineEnd && $0.endDate >= past }
            if !baselineAwake.isEmpty {
                features["sleep_fragmentation"] = (Double(relevant.count) - Double(baselineAwake.count) / 30) / 3
            }
        }
        return PocketReading(values: features, measured: measured, sources: sources, capturedAt: now)
    }
}
