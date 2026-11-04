/// Every engine tunable (SPEC 8 and 9). Change these only with a logged `kalam-cli eval` run.
public struct EngineConfig: Sendable {
    // 8.2 Spatial model and edits
    public var matchRadius = 1.5  // key units
    public var sigma = 0.45  // key units, same on both axes
    public var insertionCost = 5.0
    public var omissionCost = 3.0
    public var doubledOmissionCost = 1.5
    public var hamzaOmissionCost = 1.2
    public var transpositionCost = 2.0
    public var farSubstitutionCost = 5.0
    public var maxEdits = 2
    public var maxEditsShortLiteral = 1
    public var shortLiteralLength = 4  // literals this short get maxEditsShortLiteral
    public var noFarSubstitutionLength = 3  // literals this short get no far substitutions
    public var beamWidth = 64
    public var maxCompletions = 8
    public var completionPenalty = 1.0
    public var personalTrieCap = 30_000
    // AR is higher: its unknown words are often real dialect words missing from the MSA base (eval-log 2026-11-04).
    public var unknownLogProbEN = -21.0
    public var unknownLogProbAR = -15.5
    func unknownLogProb(_ lang: Lang) -> Double { lang == .en ? unknownLogProbEN : unknownLogProbAR }

    // 8.3 Scoring
    public var alpha = 1.0  // weight of the spatial cost
    public var trigramWeight = 0.5  // lambda3, when the personal trigram has evidence
    public var bigramShare = 0.7  // lambda2 : lambda1 = 0.7 : 0.3 of the remaining mass
    public var personalContextPrior = 3.0  // mu_b = Cu(b,.) / (Cu(b,.) + prior)
    public var personalCorpusPrior = 2000.0  // nu = Nu / (Nu + prior)
    public var correctionBoost = 3.0
    public var explicitCharBoost = 0.5  // 8.1: typed non-normalized char, e.g. a long-pressed hamza

    // 8.4 Decay
    public var decayHalfLifeDays = 60.0
    var halfLife: Double { decayHalfLifeDays * 86_400 }  // seconds

    // 8.5 Autocorrect
    public var autocorrectThresholdNormal = 2.5  // theta: score(c*) - score(literal)
    public var autocorrectThresholdGentle = 4.0
    public var autocorrectMinShare = 0.5  // c*'s softmax share among the candidates
    public var variantFixRatio = 5.0  // P_LM(c*) >= ratio * P_LM(literal)
    public var variantFixMaxKept = 2  // no variant fix once Moe kept the literal this often

    // 8.6 Predictions
    public var predictionPoolSize = 20  // candidates taken from each source before scoring

    // 9.2 Learning
    public var knownMinUses = 2  // typed uses, across...
    public var knownMinSessions = 2  // ...this many keyboard sessions
    public var knownMinImports = 2
    public var learnerFlushSeconds = 5.0
    public var manualCorrectionSeconds = 10.0
    public var manualCorrectionMaxDistance = 2
    public var storeBusyTimeoutMs = 200

    // 9.3 Import
    public var undatedImportAgeDays = 30.0  // t_last for a message whose date doesn't parse
    public var typoNeighbourRatio = 10.0  // an imported non-word is a likely typo of a word used this many times more

    public init() {}

    private static let doubles: [String: WritableKeyPath<EngineConfig, Double>] = [
        "matchRadius": \.matchRadius, "sigma": \.sigma, "insertionCost": \.insertionCost,
        "omissionCost": \.omissionCost, "doubledOmissionCost": \.doubledOmissionCost,
        "hamzaOmissionCost": \.hamzaOmissionCost, "transpositionCost": \.transpositionCost,
        "farSubstitutionCost": \.farSubstitutionCost, "completionPenalty": \.completionPenalty,
        "unknownLogProbEN": \.unknownLogProbEN, "unknownLogProbAR": \.unknownLogProbAR, "alpha": \.alpha, "trigramWeight": \.trigramWeight,
        "bigramShare": \.bigramShare, "personalContextPrior": \.personalContextPrior,
        "personalCorpusPrior": \.personalCorpusPrior, "correctionBoost": \.correctionBoost,
        "explicitCharBoost": \.explicitCharBoost, "decayHalfLifeDays": \.decayHalfLifeDays,
        "autocorrectThresholdNormal": \.autocorrectThresholdNormal, "autocorrectThresholdGentle": \.autocorrectThresholdGentle,
        "autocorrectMinShare": \.autocorrectMinShare, "variantFixRatio": \.variantFixRatio,
        "learnerFlushSeconds": \.learnerFlushSeconds, "manualCorrectionSeconds": \.manualCorrectionSeconds,
        "undatedImportAgeDays": \.undatedImportAgeDays, "typoNeighbourRatio": \.typoNeighbourRatio,
    ]
    private static let ints: [String: WritableKeyPath<EngineConfig, Int>] = [
        "maxEdits": \.maxEdits, "maxEditsShortLiteral": \.maxEditsShortLiteral,
        "shortLiteralLength": \.shortLiteralLength, "noFarSubstitutionLength": \.noFarSubstitutionLength,
        "beamWidth": \.beamWidth, "maxCompletions": \.maxCompletions, "personalTrieCap": \.personalTrieCap,
        "variantFixMaxKept": \.variantFixMaxKept, "predictionPoolSize": \.predictionPoolSize,
        "knownMinUses": \.knownMinUses, "knownMinSessions": \.knownMinSessions, "knownMinImports": \.knownMinImports,
        "manualCorrectionMaxDistance": \.manualCorrectionMaxDistance, "storeBusyTimeoutMs": \.storeBusyTimeoutMs,
    ]

    public static var names: [String] { (Array(doubles.keys) + Array(ints.keys)).sorted() }

    /// Sets a constant by name (for CLI tuning). Returns false for an unknown name or a bad value.
    public mutating func set(_ name: String, _ value: String) -> Bool {
        if let path = Self.doubles[name], let v = Double(value) {
            self[keyPath: path] = v
        } else if let path = Self.ints[name], let v = Int(value) {
            self[keyPath: path] = v
        } else {
            return false
        }
        return true
    }
}
