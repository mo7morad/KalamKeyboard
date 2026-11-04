/// Wrong-layout rescue (SPEC 5.4, 8.2): a word typed on one letters page whose taps, at the same
/// physical spots on the other page, type a word of the other language.

extension Layout {
    /// The same physical spot on another page. Both pages span the same width with the same side
    /// insets and share the row pitch, so y stays and x scales by the widest rows (EN 10, AR 11).
    func mapped(_ point: Point, to other: Layout) -> Point {
        Point(x: point.x * other.widestRow / widestRow, y: point.y)
    }
}

/// The taps at the same spots on `other`, each typing that page's nearest char key; nil when a tap
/// has no point (it can't be placed).
func mappedTaps(_ taps: [Tap], from layout: Layout, to other: Layout) -> [Tap]? {
    let centers = other.keyCenters().sorted { $0.key < $1.key }  // ties go the same way every run
    var mapped: [Tap] = []
    for tap in taps {
        guard let point = tap.point.map({ layout.mapped($0, to: other) }) else { return nil }
        func d2(_ c: Point) -> Double { (c.x - point.x) * (c.x - point.x) + (c.y - point.y) * (c.y - point.y) }
        guard let nearest = centers.min(by: { d2($0.value) < d2($1.value) }) else { return nil }
        mapped.append(Tap(nearest.key, at: point))
    }
    return mapped
}

extension Engine {
    /// SPEC 8.2: when the literal has 3+ letters, isn't a word here (valid base, known, an AR clitic
    /// form) nor the start of one (no edit-free candidate in `ranked` whose key starts with the
    /// literal's: a same-key variant or a completion, so a word being typed is left alone) and nothing
    /// autocorrects it, the other language's top candidate for the same spots, if it's a word there and
    /// a slip at most (edit cost within gentleMaxEditCost, no completion). One extra search, only when
    /// the condition holds.
    public func wrongLayoutRescue(_ input: InputState, ranked: [Suggestion], autocorrect: Suggestion?, other: Engine) -> Suggestion? {
        let literal = input.literal
        let literalIdent = ident(literal, kind: kind), literalKey = normalize(literal, lang: lang)
        guard autocorrect == nil, other.lang != lang, literal.filter(\.isLetter).count >= 3,
              !isValidBaseWord(literalIdent), personal?.isKnown(lang, literalIdent) != true, !isCliticForm(literalIdent),
              !ranked.contains(where: { !$0.isLiteral && $0.edits == 0 && normalize($0.ident, lang: lang).hasPrefix(literalKey) }),
              let layout, let otherLayout = other.layout,
              let taps = mappedTaps(input.taps, from: layout, to: otherLayout),
              let top = other.candidates(InputState(context: input.context, taps: taps)).first,
              top.completion == 0, top.edits <= config.gentleMaxEditCost,
              other.isValidBaseWord(top.ident) || other.personal?.isKnown(other.lang, top.ident) == true
        else { return nil }
        return top
    }
}
