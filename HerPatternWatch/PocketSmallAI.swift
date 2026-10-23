import Foundation

// Direct port of the uploaded HerPatternPocketPCA v0.1.0 demo's math and
// artifact. This is an experimental baseline comparison, not a diagnosis or
// the patient's next-day clinical burden forecast.
struct PocketReading {
    let values: [String: Double?]
    let measured: [String: Double]
    let sources: [String: String]
    let capturedAt: Date
}

struct PocketResult {
    let state: String
    let recovery: Int?
    let stress: Int?
    let anomaly: Double?
    let confidence: Double
    let contributors: [String]
    let missing: [String]
    let version: String = "HerPatternPocketPCA/0.1.0"
    var questionRequired: Bool { (state == "changed" || state == "strongly_changed") }
}

enum PocketSmallAI {
    static let features = ["hrv_delta", "rhr_delta", "sleep_debt", "sleep_fragmentation", "activity_load", "temp_delta", "resp_delta"]
    private static let mean = [-0.02585492, 0.01366517, 0.13331769, 0.20375764, 0.0140284, -0.00658185, -0.03875145]
    private static let std = [0.4953594, 0.50998599, 0.40092852, 0.3483197, 0.52207318, 0.37202139, 0.41210065]
    private static let pcs = [
        [-0.06076108, 0.46141707, -0.45212685, -0.40112068, 0.1854213, 0.56616642, -0.25131739],
        [-0.70514364, 0.2644153, 0.35935507, 0.05509873, -0.44889125, 0.04338892, -0.31192805],
        [0.28663706, -0.5222036, -0.15764876, -0.19414583, -0.51075268, 0.11348919, -0.55574164]
    ]
    private static let weights = [1.2, 1.0, 1.3, 1.0, 0.5, 0.8, 0.7]
    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-max(-30, min(30, x)))) }
    private static func clip(_ x: Double) -> Double { max(0, min(1, x)) }

    static func infer(_ reading: PocketReading) -> PocketResult {
        let inputs: [Double?] = features.map { reading.values[$0] ?? nil }
        let missing = features.enumerated().compactMap { inputs[$0.offset] == nil ? $0.element : nil }
        let coverage = 1 - Double(missing.count) / Double(features.count)
        // Demo artifact was trained on normalized *deltas*. Missing inputs are
        // imputed with the original training means, but we refuse to score if
        // availability is below 45%. Never synthesize missing sensor samples.
        guard coverage >= 0.45 else {
            return PocketResult(state: "insufficient_data", recovery: nil, stress: nil,
                                anomaly: nil, confidence: coverage, contributors: [], missing: missing)
        }
        let z = inputs.enumerated().map { i, v in ((v ?? mean[i]) - mean[i]) / max(0.00000001, std[i]) }
        let latent = pcs.map { row in zip(row, z).reduce(0.0) { $0 + $1.0 * $1.1 } }
        let recon = (0..<7).map { j in pcs.enumerated().reduce(0.0) { $0 + $1.element[j] * latent[$1.offset] } }
        let err = (0..<7).reduce(0.0) { $0 + pow(z[$1] - recon[$1], 2) } / 7
        let distance = z.reduce(0.0) { $0 + $1 * $1 } / 7
        let anomaly = clip(0.25 * sigmoid((err - 1.3168175203174426) / 0.3679995960261228) + 0.75 * sigmoid((distance - 1.5) / 0.55))
        let contributions = [max(0, -z[0]), max(0, z[1]), max(0, z[2]),
                             max(0, z[3]), abs(z[4]) * 0.5, abs(z[5]), abs(z[6])]
            .enumerated().map { $0.element * weights[$0.offset] }
        let stress = Int((100 * (1 - exp(-contributions.reduce(0, +) / 5))).rounded())
        let state = anomaly >= 0.75 ? "strongly_changed" : anomaly >= 0.58 ? "changed" : "within_personal_pattern"
        let ranked = features.indices.sorted { contributions[$0] > contributions[$1] }
            .filter { contributions[$0] > 0 }.prefix(3).map { features[$0] }
        let confidence = clip(0.45 + 0.45 * coverage + 0.1 * abs(anomaly - 0.5) * 2)
        return PocketResult(state: state, recovery: 100 - stress, stress: stress,
                            anomaly: anomaly, confidence: confidence,
                            contributors: ranked, missing: missing)
    }
}
