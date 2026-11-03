/// Every engine tunable (SPEC 8.1 to 8.3). Change these only with a logged `kalam-cli eval` run.
public struct EngineConfig: Sendable {
    // 8.2 Spatial model and edits
    public var matchRadius = 1.5  // key units
    public var sigma = 0.55  // key units, same on both axes
    public var insertionCost = 3.0
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
    public var unknownLogProb = -14.0

    // 8.3 Scoring
    public var alpha = 1.0  // weight of the spatial cost
    public var trigramWeight = 0.5  // lambda3, when the personal trigram has evidence
    public var bigramShare = 0.7  // lambda2 : lambda1 = 0.7 : 0.3 of the remaining mass
    public var personalContextPrior = 3.0  // mu_b = Cu(b,.) / (Cu(b,.) + prior)
    public var personalCorpusPrior = 2000.0  // nu = Nu / (Nu + prior)
    public var correctionBoost = 3.0
    public var explicitCharBoost = 0.5  // 8.1: typed non-normalized char, e.g. a long-pressed hamza

    public init() {}

    private static let doubles: [String: WritableKeyPath<EngineConfig, Double>] = [
        "matchRadius": \.matchRadius, "sigma": \.sigma, "insertionCost": \.insertionCost,
        "omissionCost": \.omissionCost, "doubledOmissionCost": \.doubledOmissionCost,
        "hamzaOmissionCost": \.hamzaOmissionCost, "transpositionCost": \.transpositionCost,
        "farSubstitutionCost": \.farSubstitutionCost, "completionPenalty": \.completionPenalty,
        "unknownLogProb": \.unknownLogProb, "alpha": \.alpha, "trigramWeight": \.trigramWeight,
        "bigramShare": \.bigramShare, "personalContextPrior": \.personalContextPrior,
        "personalCorpusPrior": \.personalCorpusPrior, "correctionBoost": \.correctionBoost,
        "explicitCharBoost": \.explicitCharBoost,
    ]
    private static let ints: [String: WritableKeyPath<EngineConfig, Int>] = [
        "maxEdits": \.maxEdits, "maxEditsShortLiteral": \.maxEditsShortLiteral,
        "shortLiteralLength": \.shortLiteralLength, "noFarSubstitutionLength": \.noFarSubstitutionLength,
        "beamWidth": \.beamWidth, "maxCompletions": \.maxCompletions, "personalTrieCap": \.personalTrieCap,
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
