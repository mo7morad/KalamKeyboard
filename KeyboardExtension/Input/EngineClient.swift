import Foundation
import KalamEngine
import os

/// Everything engine-side, confined to one serial queue (SPEC 4, D11): the mmapped base lexicons,
/// the personal store, model and learner, and one Engine per language. The main thread only sends
/// requests and learner events, and never waits on the queue except in `resultForCommit`.
/// Any store error degrades to base-only suggestions; nothing here throws or traps.
final class EngineClient {
    struct Request {
        var lang: Lang
        var context: [String]
        var taps: [Tap]  // empty: next-word predictions
        var traits: FieldTraits
        var settings: Settings
    }

    struct Result {
        let generation: Int
        let candidates: [Suggestion]  // ranked best first; predictions when the request had no taps
        let autocorrect: Suggestion?  // the commit's replacement for the literal, from the same list
        let latencyMs: Double
    }

    /// Called on main with each result that is still current.
    var onResult: ((Result) -> Void)?

    private let queue = DispatchQueue(label: "com.morad.kalam.engine", qos: .userInitiated)
    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "engine")

    // Main thread.
    private(set) var generation = 0
    private(set) var latest: Result?

    // Shared by main and the queue, under `lock`.
    private let lock = NSLock()
    private var requested = 0  // the newest generation main asked for
    private var ready: Result?  // the newest result the queue made
    private var waitingFor: Int?  // the generation main is blocked on in resultForCommit
    private let resultReady = DispatchSemaphore(value: 0)

    // Engine queue only.
    private var lexicons: [Lang: BaseLexicon] = [:]
    private var layouts: [Lang: Layout] = [:]
    private var engines: [Lang: Engine] = [:]
    private var store: PersonalStore?
    private var model: PersonalModel?
    private var learner: Learner?
    private var traits = FieldTraits()
    private var paused = false
    #if DEBUG
    private let signposter = OSSignposter(subsystem: "com.morad.kalam.keyboard", category: .pointsOfInterest)
    private var latencies: [Double] = []
    #endif

    // MARK: Requests (main)

    /// Starts a new generation and asks for its suggestions. Older requests still queued are skipped.
    func request(_ request: Request) {
        generation += 1
        let generation = generation
        lock.withLock { requested = generation }
        queue.async { [self] in
            guard lock.withLock({ requested == generation }) else { return }  // stale before it started
            let result = compute(request, generation: generation)
            lock.withLock {
                ready = result
                // Signalled here, not through main.async: main may be blocked waiting for it.
                if waitingFor == generation {
                    waitingFor = nil
                    resultReady.signal()
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, result.generation == self.generation else { return }  // stale on arrival
                latest = result
                onResult?(result)
            }
        }
    }

    /// The current generation's result for a commit (SPEC 8.5). This is the only place main waits
    /// on the engine, at most 20 ms; nil on a timeout, and the commit then skips the autocorrect.
    func resultForCommit() -> Result? {
        if let latest, latest.generation == generation { return latest }
        let generation = generation
        let found: Result? = lock.withLock {
            if let ready, ready.generation == generation { return ready }
            waitingFor = generation
            return nil
        }
        if let found { return found }
        let timedOut = resultReady.wait(timeout: .now() + .milliseconds(20)) == .timedOut
        return lock.withLock {
            if timedOut {
                if waitingFor == nil { resultReady.wait() }  // signalled just after the timeout: consume it
                waitingFor = nil
            }
            return ready?.generation == generation ? ready : nil
        }
    }

    private func compute(_ request: Request, generation: Int) -> Result {
        #if DEBUG
        let interval = signposter.beginInterval("suggest")
        defer { signposter.endInterval("suggest", interval) }
        #endif
        let start = DispatchTime.now().uptimeNanoseconds
        let engine = engine(request.lang)
        var candidates: [Suggestion], autocorrect: Suggestion?
        if request.taps.isEmpty {
            candidates = engine.predict(context: request.context)
        } else {
            let input = InputState(context: request.context, taps: request.taps)
            candidates = engine.candidates(input)
            autocorrect = engine.autocorrection(input, ranked: candidates, traits: request.traits, settings: request.settings)
        }
        let latency = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        #if DEBUG
        latencies.append(latency)
        #endif
        return Result(generation: generation, candidates: candidates, autocorrect: autocorrect, latencyMs: latency)
    }

    /// The engine for a language, built on first use. The lexicon is mapped once and kept.
    private func engine(_ lang: Lang) -> Engine {
        if let engine = engines[lang] { return engine }
        if lexicons[lang] == nil, let url = Bundle.main.url(forResource: lang.rawValue, withExtension: "klex") {
            lexicons[lang] = BaseLexicon(url: url)
            if lexicons[lang] == nil { Self.log.error("\(lang.rawValue, privacy: .public).klex failed to open, personal-only") }
        }
        if layouts[lang] == nil { layouts[lang] = Layout.bundled("\(lang.rawValue)-letters") }
        let engine = Engine(lang: lang, lexicon: lexicons[lang], layout: layouts[lang], personal: model)
        engines[lang] = engine
        return engine
    }

    // MARK: Store lifecycle (main)

    /// On appear (and when the host becomes active again): opens the store, which also picks up
    /// whatever the host app changed, and starts a learning session.
    func open() {
        queue.async { [self] in
            guard learner == nil else { return }
            if let url = PersonalStore.sharedURL {
                do {
                    store = try PersonalStore(url: url)
                } catch {
                    Self.log.error("store open failed, base-only: \(String(describing: error), privacy: .public)")
                }
            }
            model = PersonalModel(store: store)
            learner = Learner(store: store, model: model)
            learner?.traits = traits
            learner?.paused = paused
            learner?.startSession()
            engines = [:]
        }
    }

    /// On dismiss and when the host resigns or goes to the background: flushes the learner, then
    /// closes the store, because an open WAL connection keeps a lock on -shm even while idle
    /// (0xdead10cc). The expiring activity keeps the process awake until the queue is done.
    func close() {
        let done = DispatchSemaphore(value: 0)
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Kalam saves what it learned") { expired in
            if !expired { done.wait() }
        }
        queue.async { [self] in
            learner?.flush()
            (learner, model, store) = (nil, nil, nil)
            engines = [:]
            logSessionLatency()
            done.signal()
        }
    }

    // MARK: Learning (main)

    func setLearning(traits: FieldTraits, paused: Bool) {
        queue.async { [self] in
            (self.traits, self.paused) = (traits, paused)
            learner?.traits = traits
            learner?.paused = paused
        }
    }

    func commit(_ word: String, lang: Lang, context: [String], how: Learner.Commit) {
        queue.async { [self] in learner?.commit(word, lang: lang, context: context, how: how) }
    }

    func sentenceEnded() { queue.async { [self] in learner?.sentenceEnded() } }
    func backspaced(into word: String, lang: Lang) { queue.async { [self] in learner?.backspaced(into: word, lang: lang) } }
    func undoAutocorrect() { queue.async { [self] in learner?.undoAutocorrect() } }
    func writeIfDue() { queue.async { [self] in learner?.writeIfDue() } }
    func addLexiconEntries(_ entries: [String]) { queue.async { [self] in learner?.addLexiconEntries(entries) } }

    /// The bar's "Don't suggest" (SPEC 5.4).
    func block(_ ident: String, display: String, lang: Lang) {
        queue.async { [self] in model?.block(lang, ident, display: display) }
    }

    // MARK: Instrumentation

    private func logSessionLatency() {
        #if DEBUG
        guard !latencies.isEmpty else { return }
        let sorted = latencies.sorted()
        let p95 = sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
        Self.log.info("session: \(sorted.count) requests, p95 \(p95, format: .fixed(precision: 1)) ms")
        latencies = []
        #endif
    }
}
