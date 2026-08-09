// pings that outlive the session that asked for them
// a tab can schedule one and then die and the app still remembers to fire it
// there are rungs so it can be a quiet dot or the whole panel dropping depending on how much it matters

import AppKit
import Foundation

/// A scheduled nudge: any claude session writes one entry into the queue and
/// can die, tab closed, Mac asleep, whatever. The app owns the clock. At
/// fire time the nudge climbs its rung of the ladder: a dot on the glyph, the
/// come-look haptic, or the panel itself dropping down with a fresh session
/// that says the line.
struct Nudge: Codable, Identifiable {
    enum Ladder: String, Codable { case dot, tap, bubble, panel }
    let id: String
    let fireAt: Date
    /// Kept as the raw string so a rung this build does not know survives a
    /// re-save intact instead of being rewritten as something it is not.
    let ladder: String
    /// The claude prompt a panel nudge opens its tab with. On a bubble it is
    /// optional: tapping the bubble opens the panel on it, so a line can be
    /// the opening of an actual conversation. The scheduling session writes
    /// every word; the app never composes one.
    let prompt: String?
    /// A nudge that could not fire in time dies instead of arriving stale,
    /// a bedtime line delivered at breakfast is worse than none. Minutes past
    /// fireAt before it is dropped unfired.
    let expiresMinutes: Int?
    /// Kaomoji the bar flashes for a few seconds at fire time, chosen by the
    /// session that queued the nudge, the moment's feeling belongs to the
    /// writer, the app only wears it (wave two, 2026-08-01).
    let react: [String]?
    /// The line a bubble shows, pre-written like everything else (wave
    /// three, 2026-08-01).
    let text: String?

    /// An unknown rung from a newer writer lands as a dot instead of making
    /// the whole queue unreadable, before this, one new word in the file
    /// left the app deaf to every nudge in it, tonight's included.
    var rung: Ladder { Ladder(rawValue: ladder) ?? .dot }
}

/// The nudge diary: one line per decision, appended beside the queue itself.
/// Unified logging proved useless in practice, the 08-02 test bubble
/// vanished and the system log had nothing sayable about it, so the app
/// writes its own receipts where a session can actually read them. The app
/// never reads this back; it only confesses.
enum NudgeLog {
    static let url = NudgeCenter.supportDirectory.appendingPathComponent("nudge.log")

    static func line(_ text: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = Data("\(stamp) \(text)\n".utf8)
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(entry)
        } else {
            try? entry.write(to: url)
        }
    }
}

/// Delivers what is due, without polling: the support directory is watched
/// for writes, one timer is armed for the next fire time, and a wake from
/// sleep re-checks. Between events this costs nothing, which is what a
/// menu-bar resident owes the battery.
///
/// The app is deliberately dumb here: no policy, no phrasing, no budget.
/// Whether a nudge was worth Peter's attention was decided by the session
/// that wrote it; this is only the part that survives that session.
final class NudgeCenter {
    /// One well-known home, shared with the vault's `scripts/nudge.py`.
    static let supportDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let queueURL = supportDirectory.appendingPathComponent("nudges.json")

    /// Wired by the app delegate; the center cannot see the panel itself.
    var raiseDot: () -> Void = {}
    var openPanel: (String?) -> Void = { _ in }
    var flashFace: ([String]) -> Void = { _ in }
    var showBubble: (String, String?) -> Void = { _, _ in }
    var isAtMac: () -> Bool = { true }

    private var fireTimer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    private var wakeObserver: Any?

    func start() {
        watchDirectory()
        // Scheduled timers sit out system sleep; a nudge that came due with
        // the lid closed fires on this instead, or expires honestly.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() }
        check()
    }

    /// The writer replaces the file atomically (a rename into the directory),
    /// so the directory is the thing to watch, a source holding the old
    /// file's descriptor would go quiet after the first replace.
    private func watchDirectory() {
        let fd = open(Self.supportDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in self?.check() }
        source.setCancelHandler { close(fd) }
        source.activate()
        dirSource = source
    }

    private func check() {
        fireTimer?.invalidate()
        fireTimer = nil

        guard let data = try? Data(contentsOf: Self.queueURL), !data.isEmpty else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let queue = try? decoder.decode([Nudge].self, from: data) else {
            // A malformed queue is left in place for a human to read, never
            // clobbered by an empty save.
            NudgeLog.line("queue unreadable, left alone")
            return
        }

        let now = Date()
        var keep: [Nudge] = []
        for nudge in queue {
            if nudge.fireAt > now { keep.append(nudge); continue }
            let grace = TimeInterval((nudge.expiresMinutes ?? 180) * 60)
            if now.timeIntervalSince(nudge.fireAt) > grace {
                NudgeLog.line("\(nudge.id) expired unfired")
                continue
            }
            fire(nudge)
        }
        if keep.count != queue.count { save(keep) }

        // Arm exactly one timer, for the soonest pending nudge. No pending
        // nudges, no timer, no wake-ups.
        if let next = keep.map(\.fireAt).min() {
            let timer = Timer(fire: next.addingTimeInterval(1), interval: 0, repeats: false) {
                [weak self] _ in self?.check()
            }
            timer.tolerance = 15
            RunLoop.main.add(timer, forMode: .common)
            fireTimer = timer
        }
    }

    private func fire(_ nudge: Nudge) {
        NudgeLog.line("fire \(nudge.id) rung \(nudge.rung.rawValue)")
        if let react = nudge.react, !react.isEmpty { flashFace(react) }
        switch nudge.rung {
        case .dot:
            raiseDot()
        case .tap:
            raiseDot()
            Haptics.alert()
        case .bubble:
            guard let text = nudge.text, !text.isEmpty else {
                // A bubble with nothing to say is a tap.
                NudgeLog.line("\(nudge.id) had no text, dot and haptic instead")
                raiseDot()
                Haptics.alert()
                return
            }
            // A locked screen or an empty chair gets the dot, which waits,
            // instead of the line, which cannot. An open panel is NOT a
            // reason to hide: the post-it lands on top of it (the stay-home
            // rule ate the very first live bubble on 08-02, unseen).
            guard isAtMac() else {
                NudgeLog.line("\(nudge.id) found nobody home, dot instead")
                raiseDot()
                return
            }
            NudgeLog.line("\(nudge.id) bubble out: \(text.prefix(30))")
            Haptics.alert()
            showBubble(text, nudge.prompt)
        case .panel:
            raiseDot()
            Haptics.alert()
            openPanel(nudge.prompt)
        }
    }

    private func save(_ queue: [Nudge]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(queue) {
            try? data.write(to: Self.queueURL, options: .atomic)
        }
    }
}
