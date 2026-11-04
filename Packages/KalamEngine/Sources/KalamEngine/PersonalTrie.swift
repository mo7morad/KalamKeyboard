/// Moe's known words in memory (SPEC 8.2): a trie over normalized keys, searched by the same beam
/// search as the base lexicon. Capped; over the cap the word with the lowest decayed count goes.
struct PersonalTrie: SearchTrie {
    struct Word {
        var display: String
        var hits: Hits
        let key: Int
    }

    private struct Node {
        let char: UInt16
        var children: [Int] = []
        var key: Int?
        var best = -Double.infinity  // max rank in the subtree; only grows, so removals leave an upper bound
    }

    let cap: Int
    let halfLife: Double
    private var nodes = [Node(char: 0)]
    private var keyIdents: [[String]] = []  // key id -> idents (variants share a key, e.g. انا and أنا)
    private(set) var words: [String: Word] = [:]

    init(cap: Int, halfLife: Double) {
        self.cap = cap
        self.halfLife = halfLife
    }

    func children(_ node: Int) -> [Int] { nodes[node].children }
    func char(_ node: Int) -> UInt16 { nodes[node].char }
    func key(_ node: Int) -> Int? { nodes[node].key }
    func bestLogProb(_ node: Int) -> Double { nodes[node].best }
    func keyLogProb(_ key: Int) -> Double? { keyIdents[key].compactMap { words[$0]?.hits.rank(halfLife: halfLife) }.max() }
    func idents(ofKey key: Int) -> [String] { keyIdents[key] }

    /// Inserts or updates a word.
    mutating func set(_ ident: String, norm: String, display: String, hits: Hits) {
        let rank = hits.rank(halfLife: halfLife)
        var node = 0
        nodes[0].best = max(nodes[0].best, rank)
        for unit in norm.utf16 {
            if let child = nodes[node].children.first(where: { nodes[$0].char == unit }) {
                node = child
            } else {
                nodes.append(Node(char: unit))
                nodes[node].children.append(nodes.count - 1)
                node = nodes.count - 1
            }
            nodes[node].best = max(nodes[node].best, rank)
        }
        let key = nodes[node].key ?? {
            keyIdents.append([])
            nodes[node].key = keyIdents.count - 1
            return keyIdents.count - 1
        }()
        if words[ident] == nil { keyIdents[key].append(ident) }
        words[ident] = Word(display: display, hits: hits, key: key)
        // ponytail: O(n) scan per insert at the cap (30k, ~0.1 ms); keep a heap if it shows up in profiles.
        if words.count > cap, let lowest = words.min(by: { $0.value.hits.rank(halfLife: halfLife) < $1.value.hits.rank(halfLife: halfLife) }) {
            remove(lowest.key)
        }
    }

    /// Removes a word. Its nodes stay (unreachable as a key); a rebuild at the next launch drops them.
    mutating func remove(_ ident: String) {
        guard let word = words.removeValue(forKey: ident) else { return }
        keyIdents[word.key].removeAll { $0 == ident }
    }
}
