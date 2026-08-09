// the kaomoji next to the icon in the menu bar
// the app only ever picks one out of a pool it never makes up a face
// the pool is the mood and the mood comes from whatever she was actually feeling not from a schedule

import AppKit
import Combine
import Foundation

/// The face the bar is wearing right now, observable so the panel's empty
/// state can wear the same expression the menu bar does. Fed by the app
/// delegate's face wiring; nobody else writes it.
final class FaceState: ObservableObject {
    static let shared = FaceState()
    @Published var current: String?
}

/// The face in the menu bar: a kaomoji beside the glyph, carrying the mood
/// the last session (or the nightly pass) left behind. Peter's call,
/// 2026-08-01: the face IS kaomoji, no drawn states, no art pipeline, and
/// never the same one worn for long.
///
/// Sessions write `Application Support/Rin/face.json`:
///   {"faces": [...], "morning": [...], "evening": [...], "night": [...],
///    "late": [...], "updatedAt": "..."}
/// The writer supplies faces that fit the CURRENT mood, the pool changes
/// when the mood does; the app only walks inside it so the bar never wears
/// one expression out. The five optional bands are the persona's own
/// delivery bands (wave five, 2026-08-03): morning 5-9, the plain pool 9-18,
/// evening 18-23, night 23-1, late 1-5. An omitted band falls back, night
/// to late, everything else to the day pool, so pools written before the
/// split stay valid. The app SELECTS; only writers compose (wave two,
/// 2026-08-01). A file nothing has refreshed for about a day and a half
/// clears the face: an expression nobody holds anymore is a mask.
///
/// EVERY POOL IS AN ARC, not a bag (wave five): written loudest first and
/// quietest last (a morning wakes up instead, sleepiest first), so the worn
/// face can WALK the order as time passes rather than teleporting around it.
/// A mood written at noon glows and then cools by evening with nobody
/// writing anything, and a band shapes itself across its own hours. The walk
/// picks a neighbourhood; the lazy rotation still picks inside it, so an
/// hour keeps variety while an evening keeps a shape.
///
/// Event-driven like `NudgeCenter`: the directory watch reacts to a mood
/// change the moment it is written; one timer covers the next rotation, the
/// next band boundary, or the staleness cutoff, whichever lands first.
final class FaceCenter {
    static let fileURL = NudgeCenter.supportDirectory.appendingPathComponent("face.json")

    private static let staleAfter: TimeInterval = 36 * 3600
    private static let rotateAfter: TimeInterval = 45 * 60
    /// How long the day pool takes to walk from its loud end to its quiet one.
    private static let driftSpan: TimeInterval = 6 * 3600
    /// The hours where the worn band can change.
    private static let bandBoundaries = [1, 5, 9, 18, 23]

    /// How long a state pool takes to walk its own arc, how long she can
    /// watch a session grind before the face has an opinion about it.
    private static let statePace: TimeInterval = 20 * 60
    private static let blinkGap: ClosedRange<TimeInterval> = 90...240
    private static let blinkHold: TimeInterval = 0.18

    /// Wired by the app delegate; nil means wear no face.
    var show: (String?) -> Void = { _ in }

    /// What the bar is reacting to right now (wave five, second pass): the
    /// mood is the baseline, but a session grinding away or a tab asking for
    /// him outranks it, because a face that ignores what is happening in
    /// front of it is decoration.
    enum Reacting {
        case nothing, working, attention
    }

    private struct FaceFile: Codable {
        let faces: [String]
        let morning: [String]?
        let evening: [String]?
        let night: [String]?
        let late: [String]?
        /// Reaction pools, all optional: worn while claude is mid-task, worn
        /// while a tab wants him, flashed when the panel drops open.
        let working: [String]?
        let attention: [String]?
        let greet: [String]?
        /// Blink frames: a worn face mapped to the frames it flickers
        /// through. The bar swaps for a breath and swaps back, rarely.
        let frames: [String: [String]]?
        let updatedAt: Date
    }

    /// The pool a brand new install wears until a session writes a real one.
    ///
    /// The face is the most distinctive thing this app does, and until now it
    /// was invisible on day one: pools are written by sessions, a fresh Mac
    /// has none, so the bar wore a bare glyph until the assistant got round
    /// to composing one. Somebody could use Rin for an afternoon and never
    /// learn the feature existed.
    ///
    /// This does not break "the app SELECTS, writers COMPOSE". Nothing is
    /// invented at runtime: the pool ships beside the default persona, the
    /// same way that persona's voice does, and it is the opening expression
    /// of a character who has just arrived and does not know anybody yet.
    ///
    /// It retires for good the moment a real pool exists. A written pool that
    /// later goes STALE still clears the face rather than falling back here,
    /// stale means nobody holds that expression anymore, and answering that
    /// with a shipped default would be the app claiming a feeling it has no
    /// grounds for.
    private static let starter: FaceFile? = {
        guard let url = Bundle.main.url(forResource: "default-face", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(FaceFile.self, from: data) else { return nil }
        // Stamped at launch rather than at whatever date shipped in the file,
        // so the day pool walks its arc from HERE: bright on arrival, settled
        // a few hours later. That is the honest shape for a first meeting,
        // and a shipped timestamp would have read as stale on arrival.
        return FaceFile(
            faces: file.faces,
            morning: file.morning,
            evening: file.evening,
            night: file.night,
            late: file.late,
            working: file.working,
            attention: file.attention,
            greet: file.greet,
            frames: file.frames,
            updatedAt: Date()
        )
    }()

    /// The band the clock puts us in, with the window it spans. `night` wraps
    /// midnight, which is why the window is a pair of hours and not a range.
    private struct Band {
        let pools: [[String]?]
        let start: Int
        let end: Int
    }

    /// THE STABILITY LAW (wave five, third pass, Peter: "i really dont like
    /// it changeing expressions every time i click it"). The face never
    /// changes because he interacted with it. Feelings carry over from one
    /// moment to the next (emotional inertia); an expression that answers a
    /// glance is a slot machine, not a person. Concretely: a reaction state
    /// must PERSIST before the face follows it, leaving one returns to the
    /// face worn before, and a greeting marks an arrival, not a glance.
    /// How long each transition must hold before the face believes it:
    private static func settleTime(from old: Reacting, to new: Reacting) -> TimeInterval {
        switch (old, new) {
        // A bell is a real event; answering it should read promptly.
        case (_, .attention): return 3
        // The 10s transcript flicker between conversation turns must never
        // reach the face: only a real stretch of work counts as working.
        case (_, .working): return 45
        // He answered the bell; the excitement stands down quickly.
        case (.attention, .nothing): return 8
        // Work ending eases back to the mood instead of snapping.
        case (.working, .nothing): return 75
        case (.nothing, .nothing): return 0
        }
    }
    /// A hello marks an arrival. Opens closer together than this are the
    /// same visit, and the same visit is greeted once.
    private static let arrivalGap: TimeInterval = 90 * 60

    private var current: String?
    private var rotatedAt = Date.distantPast
    private var flashUntil = Date.distantPast
    private var nextTimer: Timer?
    private var flashTimer: Timer?
    private var blinkTimer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    private var wakeObserver: Any?
    private var reacting = Reacting.nothing
    private var reactingSince = Date()
    private var pending: Reacting?
    private var pendingSince = Date()
    /// The mood face worn before a reaction took over, so easing back is a
    /// return, not a reroll.
    private var heldFace: String?
    private var lastPanelOpen = Date.distantPast
    private var cached: FaceFile?

    func start() {
        watchDirectory()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tick() }
        tick()
    }

    /// The bar answers what is actually happening, not only what the day
    /// felt like, but only once the state has held long enough to be real.
    /// Called every poll tick, which is what makes the settle timing work:
    /// a state that keeps flickering keeps resetting its own clock.
    func react(_ state: Reacting) {
        if state == reacting {
            pending = nil
            return
        }
        if pending != state {
            pending = state
            pendingSince = Date()
        }
        guard Date().timeIntervalSince(pendingSince) >= Self.settleTime(from: reacting, to: state)
        else { return }
        if reacting == .nothing { heldFace = current }
        reacting = state
        reactingSince = Date()
        pending = nil
        if state == .nothing, let held = heldFace {
            // Continuity: come back wearing the face he left, if the mood
            // still holds it. tick() replaces it only when the arc moved on.
            wear(held)
        } else {
            current = nil
        }
        tick()
    }

    /// The panel just dropped open. A hello belongs to an ARRIVAL, the
    /// first open after a real absence, never to every glance; greeting
    /// each click is the observer effect this whole layer exists to avoid.
    func greet() {
        let gap = Date().timeIntervalSince(lastPanelOpen)
        lastPanelOpen = Date()
        guard gap > Self.arrivalGap else { return }
        guard let pool = cached?.greet, !pool.isEmpty else { return }
        flash(pool, duration: 3)
    }

    /// A nudge just fired: wear its reaction for a few seconds, then let the
    /// mood pool resume. The change IS the animation, the bar swaps, holds,
    /// and swaps back; nothing slides or shimmers (the whisper rule), which
    /// also makes Reduce Motion the same experience by construction.
    func flash(_ candidates: [String], duration: TimeInterval = 6) {
        let pool = candidates.filter { !$0.isEmpty && $0.count <= 14 }
        guard let face = pool.randomElement() else { return }
        flashUntil = Date().addingTimeInterval(duration)
        show(face)
        flashTimer?.invalidate()
        let timer = Timer(fire: flashUntil.addingTimeInterval(0.1), interval: 0, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            // A flash is a moment, not a mood change: the face worn before
            // it comes back, and tick() only replaces it if the arc moved.
            if let held = self.current { self.show(held) }
            self.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        flashTimer = timer
    }

    /// Same rationale as `NudgeCenter`: the writer replaces the file
    /// atomically, so the directory is what stays watchable.
    private func watchDirectory() {
        let fd = open(NudgeCenter.supportDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in self?.tick() }
        source.setCancelHandler { close(fd) }
        source.activate()
        dirSource = source
    }

    /// The persona's clock layer, worn on the face: barely-on before 9, the
    /// mood at full through the working day, loosest in the evening, quieter
    /// past 23:00, clipped past 1am.
    private func band(of file: FaceFile, at date: Date) -> Band {
        switch Calendar.current.component(.hour, from: date) {
        case 5...8:   return Band(pools: [file.morning], start: 5, end: 9)
        case 9...17:  return Band(pools: [], start: 9, end: 18)
        case 18...22: return Band(pools: [file.evening], start: 18, end: 23)
        case 23, 0:   return Band(pools: [file.night, file.late], start: 23, end: 1)
        default:      return Band(pools: [file.late], start: 1, end: 5)
        }
    }

    /// Deduped and width-checked, because the walk assumes a pool of two
    /// means two DIFFERENT faces, a writer pasting the same face twice must
    /// not be able to spin it. Order is preserved: the pool IS the arc, and
    /// a face wider than the bar deserves is skipped, never squeezed.
    private func clean(_ pool: [String]) -> [String] {
        var seen = Set<String>()
        return pool.filter { !$0.isEmpty && $0.count <= 14 && seen.insert($0).inserted }
    }

    private func activePool(of file: FaceFile, band: Band) -> [String] {
        clean(band.pools.compactMap { $0 }.first { !$0.isEmpty } ?? file.faces)
    }

    /// What to wear and how far along its arc: a reaction pool if something
    /// is actually happening, otherwise the clock's band, otherwise the day.
    private func wearing(file: FaceFile, now: Date) -> (pool: [String], walk: Double) {
        let reactionPool: [String]?
        switch reacting {
        case .attention: reactionPool = file.attention
        case .working: reactionPool = file.working
        case .nothing: reactionPool = nil
        }
        if let reactionPool, !clean(reactionPool).isEmpty {
            // A state walks its own arc: the longer a session grinds, the
            // further down the pool the face gets.
            let walk = min(max(now.timeIntervalSince(reactingSince) / Self.statePace, 0), 1)
            return (clean(reactionPool), walk)
        }
        let worn = band(of: file, at: now)
        return (activePool(of: file, band: worn), progress(in: worn, file: file, now: now))
    }

    /// How far through the arc we are, 0 at its loud end and 1 at its quiet
    /// one. A band walks across its own hours; the day pool walks from when
    /// it was written, so a mood set at noon has cooled by dinner.
    private func progress(in band: Band, file: FaceFile, now: Date) -> Double {
        if band.pools.compactMap({ $0 }).first(where: { !$0.isEmpty }) == nil {
            return min(max(now.timeIntervalSince(file.updatedAt) / Self.driftSpan, 0), 1)
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let clock = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        var elapsed = clock - Double(band.start)
        if elapsed < 0 { elapsed += 24 }
        var length = Double(band.end - band.start)
        if length <= 0 { length += 24 }
        return min(max(elapsed / length, 0), 1)
    }

    /// The faces eligible right now: where the walk has reached, plus its
    /// immediate neighbours so the rotation still has somewhere to go.
    private func neighbourhood(of pool: [String], at progress: Double) -> [String] {
        guard pool.count > 1 else { return pool }
        let index = Int((Double(pool.count - 1) * progress).rounded())
        let lower = max(0, index - 1)
        let upper = min(pool.count - 1, index + 1)
        return Array(pool[lower...upper])
    }

    /// The next moment the worn band can change, so the one timer can cover
    /// it alongside rotation and staleness.
    private func nextBandBoundary() -> Date {
        let calendar = Calendar.current
        let upcoming = Self.bandBoundaries.compactMap {
            calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: $0, minute: 0),
                matchingPolicy: .nextTime
            )
        }
        return upcoming.min() ?? Date().addingTimeInterval(24 * 3600)
    }

    private func tick() {
        // A flash owns the bar until it ends; its own timer re-enters here,
        // so a skipped tick is never the last one.
        guard Date() >= flashUntil else { return }
        nextTimer?.invalidate()
        nextTimer = nil

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let written = (try? Data(contentsOf: Self.fileURL))
            .flatMap { try? decoder.decode(FaceFile.self, from: $0) }

        let file: FaceFile
        if let written {
            let age = Date().timeIntervalSince(written.updatedAt)
            guard age < Self.staleAfter else {
                clear()
                return
            }
            file = written
        } else if !FileManager.default.fileExists(atPath: Self.fileURL.path),
                  let starter = Self.starter {
            // Nothing has ever been written here, so this is a new install.
            // A pool that EXISTS and will not parse takes the other branch
            // and clears, so a broken file can never hide behind the default.
            file = starter
        } else {
            clear()
            return
        }
        cached = file
        let (pool, walk) = wearing(file: file, now: Date())
        guard !pool.isEmpty else {
            clear()
            return
        }
        // Where the arc has walked to by now, and the faces around it.
        let here = neighbourhood(of: pool, at: walk)

        // Rotate on a mood, band, or drift change immediately, otherwise on a
        // lazy cadence, an expression should linger, not flicker.
        let rotationDue = Date().timeIntervalSince(rotatedAt) > Self.rotateAfter
        // Nothing on yet, or what is on has fallen outside the arc's reach.
        let wornIsStale = current.map { !here.contains($0) } ?? true
        if wornIsStale || rotationDue {
            // Pick from the ones that are not already on, rather than
            // re-rolling until the roll differs. The re-roll could not always
            // finish: a pool holding the same face twice makes `count > 1`
            // true while every candidate equals the worn one, and the loop
            // spins the main thread with the whole menu bar frozen behind it.
            // The writing script refuses a duplicate, but the pool is plain
            // json in somebody's own folder and that script is not the only
            // thing that can put it there.
            if let next = here.filter({ $0 != current }).randomElement() ?? here.first {
                rotatedAt = Date()
                wear(next)
            }
        }

        // One timer for whichever comes first: the next rotation (only worth
        // waking for when there is something new to rotate to), the next
        // band boundary, or the moment the pool goes stale.
        var wakeAt = min(
            file.updatedAt.addingTimeInterval(Self.staleAfter + 1),
            nextBandBoundary().addingTimeInterval(1)
        )
        if pool.count > 1 {
            wakeAt = min(wakeAt, rotatedAt.addingTimeInterval(Self.rotateAfter + 1))
            // A reaction arc is short, so it needs a finer wake than the
            // lazy rotation gives, otherwise the whole state is over before
            // the face reaches the end of its own pool.
            if reacting != .nothing {
                wakeAt = min(wakeAt, Date().addingTimeInterval(Self.statePace / Double(pool.count)))
            }
        }
        let timer = Timer(fire: wakeAt, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        nextTimer = timer
    }

    /// The one way a face goes on. Everything that changes the worn face
    /// comes through here, so the blink timer can never be left behind by a
    /// path that forgot to rearm it, which is exactly what happened to the
    /// continuity path when it was written as a bare show().
    private func wear(_ face: String) {
        current = face
        show(face)
        scheduleBlink()
    }

    /// The blink: the worn face swaps to one of its own frames for a breath
    /// and swaps back. Rare and jittered on purpose, a bar that moves on a
    /// schedule is a bar you stop seeing, which is the whole argument the
    /// motion route lost the first time. Reduce Motion turns it off, and a
    /// face with no frames written simply never blinks.
    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard !Motion.reduced, let face = current,
              let frames = cached?.frames?[face].map(clean), !frames.isEmpty
        else { return }
        let wait = TimeInterval.random(in: Self.blinkGap)
        let timer = Timer(fire: Date().addingTimeInterval(wait), interval: 0, repeats: false) {
            [weak self] _ in
            guard let self, self.current == face, Date() >= self.flashUntil else { return }
            self.show(frames.randomElement()!)
            let back = Timer(
                fire: Date().addingTimeInterval(Self.blinkHold), interval: 0, repeats: false
            ) { [weak self] _ in
                guard let self, self.current == face else { return }
                self.show(face)
                self.scheduleBlink()
            }
            RunLoop.main.add(back, forMode: .common)
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func clear() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard current != nil else { return }
        current = nil
        show(nil)
    }
}
