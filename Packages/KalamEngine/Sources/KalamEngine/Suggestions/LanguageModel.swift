import Foundation

/// What the LM needs about the context of one request, gathered once.
struct LMContext {
    let idents: [String]  // ≤ 2, oldest first, starting with <s> at a sentence start
    let previous: Int?  // base word id of b
    let personal: ContextCounts
    let corpusSize: Double  // Nu
}

extension Engine {
    func lmContext(_ context: [String]) -> LMContext {
        let words = context.suffix(2).map { ident($0, kind: kind) }
        let idents = words.isEmpty ? [sentenceStart] : Array(words)
        return LMContext(idents: idents, previous: lexicon?.wordID(ident: idents[idents.count - 1]),
                         personal: personal?.context(lang, idents) ?? ContextCounts(), corpusSize: personal?.corpusSize(lang) ?? 0)
    }

    /// Interpolated LM (SPEC 8.3):
    /// P(w|a,b) = λ3·Pu(w|a,b) + λ2·[μb·Pu(w|b) + (1−μb)·PB(w|b)] + λ1·[ν·Pu(w) + (1−ν)·PB(w)]
    /// With no personal data it is bigramShare·PB(w|b) + (1 − bigramShare)·PB(w).
    /// After <s>, the base bigram's part of λ2 uses sentenceStartBigramShare instead and the unigram
    /// takes the rest; Moe's own bigram keeps bigramShare·μb.
    func lmLogProb(_ ident: String, word: Int?, _ context: LMContext) -> Double {
        let baseUnigram = word.flatMap { lexicon?.logProb($0) }.map(exp) ?? 0
        let baseBigram = word.flatMap { w in context.previous.flatMap { lexicon?.bigramLogProb($0, w) } }.map(exp) ?? 0
        let counts = context.personal
        let trigram = counts.trigramTotal > 0 ? (counts.trigram[ident] ?? 0) / counts.trigramTotal : 0
        let bigram = counts.bigramTotal > 0 ? (counts.bigram[ident] ?? 0) / counts.bigramTotal : 0
        let unigram = context.corpusSize > 0 ? (personal?.count(lang, ident) ?? 0) / context.corpusSize : 0
        let mu = counts.bigramTotal / (counts.bigramTotal + config.personalContextPrior)
        let nu = context.corpusSize / (context.corpusSize + config.personalCorpusPrior)
        let lambda3 = counts.trigramTotal > 0 ? config.trigramWeight : 0
        let baseShare = context.idents.last == sentenceStart ? config.sentenceStartBigramShare : config.bigramShare
        let personalBigram = config.bigramShare * mu, baseBigramWeight = baseShare * (1 - mu)
        let p = lambda3 * trigram
            + (1 - lambda3) * (personalBigram * bigram + baseBigramWeight * baseBigram
                + (1 - personalBigram - baseBigramWeight) * (nu * unigram + (1 - nu) * baseUnigram))
        return p > 0 ? log(p) : config.unknownLogProb(lang)
    }
}
