/// Trie beam search with the spatial model and edits (SPEC 8.2).

struct SearchTap {
    let unit: UInt16  // normalized UTF-16 unit
    let point: Point?
}

/// A trie key reached by the search, with its cheapest path.
struct KeyMatch {
    let key: Int
    let spatial: Double
    let edits: Double
    let completion: Double
}

private struct State {
    let node: Int
    let edits: Int
    let spatial: Double
    let editCost: Double
    var cost: Double { spatial + editCost }

    func moved(to node: Int, spatial: Double = 0, edit: Double? = nil) -> State {
        State(node: node, edits: edits + (edit == nil ? 0 : 1), spatial: self.spatial + spatial, editCost: editCost + (edit ?? 0))
    }
}

private let hamza: UInt16 = 0x0621

extension Engine {
    func search(_ taps: [SearchTap], literalLength: Int, in lexicon: BaseLexicon) -> [KeyMatch] {
        let maxEdits = literalLength <= config.shortLiteralLength ? config.maxEditsShortLiteral : config.maxEdits
        let allowFar = literalLength > config.noFarSubstitutionLength
        var layers = [[Int: State]](repeating: [:], count: taps.count + 1)
        layers[0][BaseLexicon.root] = State(node: BaseLexicon.root, edits: 0, spatial: 0, editCost: 0)

        for i in 0...taps.count {
            addOmissions(&layers[i], maxEdits: maxEdits, lexicon)
            prune(&layers[i])
            guard i < taps.count else { break }
            for s in layers[i].values {
                if s.edits < maxEdits { relax(&layers[i + 1], s.moved(to: s.node, edit: config.insertionCost)) }
                for child in lexicon.children(s.node) {
                    let char = lexicon.char(child)
                    if let cost = matchCost(char, taps[i]) {
                        relax(&layers[i + 1], s.moved(to: child, spatial: cost))
                    } else if allowFar, s.edits < maxEdits {
                        relax(&layers[i + 1], s.moved(to: child, edit: config.farSubstitutionCost))
                    }
                    guard i + 1 < taps.count, s.edits < maxEdits, let first = matchCost(char, taps[i + 1]) else { continue }
                    for grandchild in lexicon.children(child) {
                        if let second = matchCost(lexicon.char(grandchild), taps[i]) {
                            relax(&layers[i + 2], s.moved(to: grandchild, spatial: first + second, edit: config.transpositionCost))
                        }
                    }
                }
            }
        }
        return matches(ending: layers[taps.count], lexicon)
    }

    /// Alpha-weighted spatial cost of matching a trie char to a tap, nil when it doesn't match.
    /// A point-less tap matches its exact char only, at cost 0; so does a tap whose char has no key on the page.
    private func matchCost(_ char: UInt16, _ tap: SearchTap) -> Double? {
        guard let point = tap.point else { return char == tap.unit ? 0 : nil }
        guard let d2 = spatial.distanceSquared(char, point) else { return char == tap.unit ? 0 : nil }  // key missing from the page
        guard d2 <= config.matchRadius * config.matchRadius else { return nil }
        return config.alpha * d2 / (2 * config.sigma * config.sigma)
    }

    /// Missed letters: descend without consuming a tap, up to the edit limit.
    private func addOmissions(_ layer: inout [Int: State], maxEdits: Int, _ lexicon: BaseLexicon) {
        var frontier = Array(layer.values)
        while !frontier.isEmpty {
            var added: [State] = []
            for s in frontier where s.edits < maxEdits {
                let previous = lexicon.char(s.node)
                for child in lexicon.children(s.node) {
                    let char = lexicon.char(child)
                    let cost = char == previous ? config.doubledOmissionCost : char == hamza ? config.hamzaOmissionCost : config.omissionCost
                    let next = s.moved(to: child, edit: cost)
                    if relax(&layer, next) { added.append(next) }
                }
            }
            frontier = Array(added.sorted { $0.cost < $1.cost }.prefix(config.beamWidth))
        }
    }

    private func prune(_ layer: inout [Int: State]) {
        guard layer.count > config.beamWidth else { return }
        let kept = layer.values.sorted { $0.cost < $1.cost }.prefix(config.beamWidth)
        layer = Dictionary(uniqueKeysWithValues: kept.map { ($0.node, $0) })
    }

    /// Dedupe on (node, i): keep the cheaper state. Returns whether the new one was kept.
    @discardableResult
    private func relax(_ layer: inout [Int: State], _ s: State) -> Bool {
        if let old = layer[s.node], old.cost <= s.cost { return false }
        layer[s.node] = s
        return true
    }

    /// Full words at the end states plus best-first completions below them.
    private func matches(ending end: [Int: State], _ lexicon: BaseLexicon) -> [KeyMatch] {
        var best: [Int: KeyMatch] = [:]
        for s in end.values {
            if let key = lexicon.key(s.node) { keep(key, s, completion: 0, in: &best) }
        }
        addCompletions(below: end, to: &best, lexicon)
        return Array(best.values)
    }

    /// Keeps the cheaper path to a key. Returns whether this one was kept.
    @discardableResult
    private func keep(_ key: Int, _ s: State, completion: Double, in best: inout [Int: KeyMatch]) -> Bool {
        if let old = best[key], old.spatial + old.edits + old.completion <= s.cost + completion { return false }
        best[key] = KeyMatch(key: key, spatial: s.spatial, edits: s.editCost, completion: completion)
        return true
    }

    /// Up to maxCompletions words strictly below the end states, found best-first on
    /// subtree log-prob minus path cost (the max-subtree score is an exact upper bound).
    private func addCompletions(below end: [Int: State], to best: inout [Int: KeyMatch], _ lexicon: BaseLexicon) {
        struct Item { let node: Int; let state: State; let isWord: Bool; let priority: Double }
        func subtree(_ node: Int, _ s: State) -> Item { Item(node: node, state: s, isWord: false, priority: lexicon.bestLogProb(node) - s.cost) }
        var frontier = end.values.flatMap { s in lexicon.children(s.node).map { subtree($0, s) } }
        var expanded: Set<Int> = []  // a node's first pop has its best priority; also bounds work on a corrupt trie
        var found = 0
        // ponytail: linear max scan over the frontier; use a heap if completions show up in profiles.
        while found < config.maxCompletions, let top = frontier.indices.max(by: { frontier[$0].priority < frontier[$1].priority }) {
            let item = frontier.remove(at: top)
            if item.isWord {
                if let key = lexicon.key(item.node), keep(key, item.state, completion: config.completionPenalty, in: &best) { found += 1 }
                continue
            }
            guard expanded.insert(item.node).inserted else { continue }
            if let key = lexicon.key(item.node), let first = lexicon.variants(ofKey: key).first {
                frontier.append(Item(node: item.node, state: item.state, isWord: true, priority: lexicon.logProb(first) - item.state.cost))
            }
            frontier += lexicon.children(item.node).map { subtree($0, item.state) }
        }
    }
}
