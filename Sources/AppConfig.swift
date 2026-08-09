// everything the app needs to know that is not code
// where your brain folder is what colors the terminal uses which conversation belongs to which tab
// the disk reads in here are cached on purpose they used to get asked for every tab every couple of seconds

import AppKit
import Foundation
import SwiftTerm

/// Colors matched to Peter's Terminal.app theme (dark slate + light gray).
/// The terminal stays dark in every system appearance, by request.
///
/// The 16-colour palette below is the app's own (2026-08-03). Before it,
/// SwiftTerm's default shipped untouched, and that default is Tango, the
/// GNOME palette from 2005. On this slate its red scored 2.44:1 against the
/// background, its blue 2.43, its magenta 2.19, all far under the 4.5 a
/// readable foreground needs, and claude draws its whole interface in these
/// sixteen slots. So the terminal Peter lives in was rendering a Linux
/// palette at unreadable contrast, purely because nobody had chosen.
///
/// This one is mixed off Xcode's dark theme, whose own background (#292A30)
/// is within a hair of this slate, so the hues are known to sit right on it:
/// the string coral, the number sand, the keyword pink, the type cyan, and
/// the comment slate that becomes bright-black, which is the slot claude
/// leans on hardest for everything it wants to de-emphasise. Every body
/// colour clears 5:1; only slot 0 (a recess, never text) and slot 8 (dim by
/// intent, 3.99:1) sit under, and both are deliberate.
enum TerminalTheme {
    static let background = NSColor(srgbRed: 0.141, green: 0.165, blue: 0.212, alpha: 1.0)
    static let foreground = NSColor(srgbRed: 0.866, green: 0.878, blue: 0.898, alpha: 1.0)

    /// The tab bar's fill when Reduce Transparency is on and the frost has to
    /// go. One step up from the slate, enough that the bar still reads as a
    /// layer above the terminal, not enough to become a second colour in an
    /// app that spends colour on alerts only.
    static let bar = NSColor(srgbRed: 0.180, green: 0.208, blue: 0.263, alpha: 1.0)

    /// The block caret: the foreground, with the slate showing through the
    /// character underneath. Terminal.app's inverted block, and it spends no
    /// hue, colour in this app means an alert, and a cursor is not one.
    static let caret = foreground
    /// Selection sits in the slate's own family rather than arriving as the
    /// system's accent blue, which is mixed for a white sheet of text.
    static let selection = NSColor(srgbRed: 0.220, green: 0.267, blue: 0.353, alpha: 1.0)

    private static func hex(_ value: Int) -> SwiftTerm.Color {
        func channel(_ shift: Int) -> UInt16 {
            let byte = UInt16((value >> shift) & 0xFF)
            return byte << 8 | byte
        }
        return SwiftTerm.Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    /// Contrast against the slate is in the comment beside each line, so a
    /// future edit to a hue has to argue with a number rather than a taste.
    static let palette: [SwiftTerm.Color] = [
        hex(0x21252E),  // 0  black, a recess under the slate, never text
        hex(0xFC6A5D),  // 1  red, Xcode's string coral          5.04:1
        hex(0x5CC98C),  // 2  green                              6.98:1
        hex(0xD0BF69),  // 3  yellow, Xcode's number sand        7.77:1
        hex(0x6DA8F7),  // 4  blue                               5.89:1
        hex(0xFC5FA3),  // 5  magenta, Xcode's keyword pink      5.01:1
        hex(0x5DD8FF),  // 6  cyan, Xcode's type blue            8.72:1
        hex(0xDDE0E5),  // 7  white, the foreground             10.87:1
        hex(0x7C8896),  // 8  bright black, dim ON PURPOSE       3.99:1
        hex(0xFF8A80),  // 9  bright red                         6.30:1
        hex(0x4EE38A),  // 10 bright green                       8.69:1
        hex(0xE8CF7E),  // 11 bright yellow                      9.36:1
        hex(0x8FC1FF),  // 12 bright blue                        7.70:1
        hex(0xFF87C0),  // 13 bright magenta                     6.49:1
        hex(0x8FE5FF),  // 14 bright cyan                       10.15:1
        hex(0xFFFFFF),  // 15 bright white                      14.39:1
    ]
}

enum AppConfig {
    /// The app's one settings store. A QA run (RIN_TEST_HOME set) gets its
    /// own suite, wiped clean at every launch so each rehearsal is a true
    /// first run. The reason this accessor exists: macOS keys preferences by
    /// USER, not by $HOME, so a scratch home isolates every file path while
    /// the settings stay shared, which is how a test copy once woke up
    /// wearing the real tab list and shot the live sessions out from under it
    /// (2026-08-02). File paths follow $HOME; settings follow this accessor;
    /// nothing in the app may read UserDefaults.standard directly.
    static let defaults: UserDefaults = {
        guard ProcessInfo.processInfo.environment["RIN_TEST_HOME"] != nil else {
            return .standard
        }
        let name = "com.petermei.rin.qa"
        let suite = UserDefaults(suiteName: name) ?? .standard
        suite.removePersistentDomain(forName: name)
        return suite
    }()

    /// Working directory each session starts in: the brain folder first run
    /// chose. The home-directory fallback is never used for a real session,
    /// sessions cannot exist before a folder has been picked, it only keeps
    /// the path lookups meaningful while first run is still on screen.
    static var workingDirectory: String {
        AppConfig.defaults.string(forKey: "workdir") ?? NSHomeDirectory()
    }

    /// Whether a brain folder has ever been chosen. Until it has, the panel
    /// shows first run instead of sessions: there is nothing to open a
    /// claude in.
    static var isConfigured: Bool {
        AppConfig.defaults.string(forKey: "workdir") != nil
    }

    static func setWorkingDirectory(_ path: String) {
        AppConfig.defaults.set(path, forKey: "workdir")
    }

    /// Command run inside the login shell for every new session.
    static var command: String {
        AppConfig.defaults.string(forKey: "command") ?? "exec claude"
    }

    /// Permission mode every session opens in, so a tab lands ready to work
    /// instead of asking for the first edit. Set the "permissionMode" default
    /// to another of claude's modes, or to an empty string to start plain.
    static var permissionMode: String {
        AppConfig.defaults.object(forKey: "permissionMode") as? String ?? "auto"
    }

    /// Root of claude's per-project transcript storage.
    static var projectsRoot: String {
        NSHomeDirectory() + "/.claude/projects"
    }

    /// Claude slugs the working directory into its folder name, and the rule
    /// has changed between versions: a "/", a ".", a space and a "~" have all
    /// been folded to "-" at one time or another. Comparing paths through
    /// this filter makes the lookup survive whichever rule is in force.
    private static func canonical(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// The folder holding this working directory's conversations. Prefers a
    /// folder that actually exists over the name we would compute, so a
    /// renaming in claude cannot silently break resume. Old naming rules
    /// leave look-alike folders behind, and where several match, the most
    /// recently written one wins.
    ///
    /// Recency, not the fattest folder, and the difference is the whole bug.
    /// Claude derives ONE folder from the working directory and looks nowhere
    /// else: measured 2026-07-28, a `--session-id` that already exists under
    /// another folder is accepted without a murmur, and `--resume` of a
    /// conversation sitting in another folder answers "No conversation found"
    /// and exits. So the only folder worth asking is the one claude is
    /// writing to NOW. Picking the one with the most conversations picks the
    /// folder claude USED to write to, which the day it renames is precisely
    /// the wrong answer, and every restored tab dies on launch again.
    ///
    /// Cached for half a minute, because the answer costs a walk of every
    /// project folder and every conversation inside the matching ones, and it
    /// is asked for each tab on every tick of the working light. Claude
    /// renames that folder about once a release, so half a minute of staleness
    /// is free and the walk was not.
    private static var directoryCache: (at: Date, path: String)?

    static var transcriptDirectory: String {
        if let cached = directoryCache, Date().timeIntervalSince(cached.at) < 30 {
            return cached.path
        }
        let want = canonical(workingDirectory)
        let root = URL(fileURLWithPath: projectsRoot)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        let matches = contents.filter { canonical($0.lastPathComponent) == want }
        let best = matches.max { lastActivity(in: $0) < lastActivity(in: $1) }
        let path = best?.path ?? root.appendingPathComponent(want).path
        directoryCache = (Date(), path)
        return path
    }

    /// Forget the cached folder. A tab that just died on a resume is the one
    /// case where a stale answer is expensive rather than free: the retry
    /// deserves a fresh look at where claude is writing now.
    static func forgetTranscriptDirectory() {
        directoryCache = nil
    }

    /// Newest conversation in a folder, falling back to the folder's own
    /// timestamp when it holds none. The files are the honest signal:
    /// resuming appends to one without touching the folder around it.
    private static func lastActivity(in directory: URL) -> Date {
        let key: URLResourceKey = .contentModificationDateKey
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [key])) ?? []
        let newest = files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { (try? $0.resourceValues(forKeys: [key]))?.contentModificationDate }
            .max()
        return newest
            ?? (try? directory.resourceValues(forKeys: [key]))?.contentModificationDate
            ?? .distantPast
    }

    /// Whether a conversation was already recorded under this id.
    static func hasTranscript(for sessionID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: transcriptPath(for: sessionID))
    }

    /// Whether this session wrote to its conversation in the last few
    /// seconds. Claude appends a turn at a time, so a file being touched
    /// right now is the cheapest honest sign that one is in flight, and it
    /// costs a single stat rather than anything watching the process.
    static func isWorking(sessionID: UUID, within seconds: TimeInterval = 5) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: transcriptPath(for: sessionID))
        guard let modified = attributes?[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < seconds
    }

    static func transcriptPath(for sessionID: UUID) -> String {
        transcriptDirectory + "/" + sessionID.uuidString.lowercased() + ".jsonl"
    }

    /// Claude's retention sweep (cleanupPeriodDays in ~/.claude/settings.json,
    /// set to 1 on this machine) unlinks any conversation file it judges old,
    /// and the only thing it judges is mtime. It runs about daily from
    /// whatever long-lived claude happens to be around, and it cannot tell a
    /// dead conversation from one a saved tab still points at, which is how
    /// every tab came back empty on 2026-08-01: the files were reaped out
    /// from under the running app, and the loss only showed at the next
    /// restart. Claude appends by path and holds no open handle, so nothing
    /// downstream notices a touch. The app therefore stakes a claim on its
    /// own tabs in the one language the sweep reads: it keeps their files'
    /// mtime young. Backdated far enough that a claim can never light the
    /// working glyph, and skipped while a real write is fresh, so a claim
    /// never masks one either.
    static func claimTranscripts(for sessionIDs: [UUID]) {
        let manager = FileManager.default
        let recentlyWritten = Date(timeIntervalSinceNow: -60)
        for id in sessionIDs {
            let path = transcriptPath(for: id)
            guard let modified = (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  modified < recentlyWritten else { continue }
            try? manager.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -30)], ofItemAtPath: path)
        }
    }

    private static var lastClaim = Date.distantPast

    /// The claim, re-staked on the app's own slow tick. Hourly is plenty:
    /// the sweep's shortest fuse is a day, and a claim costs one stat per
    /// tab, so the poll can call this every beat and almost always pay
    /// nothing.
    static func claimTranscriptsIfDue(for sessionIDs: [UUID]) {
        guard Date().timeIntervalSince(lastClaim) > 60 * 60 else { return }
        lastClaim = Date()
        claimTranscripts(for: sessionIDs)
    }

    private static var taintedCache: (at: Date, ids: Set<UUID>) = (.distantPast, [])

    /// Sessions the vault's private mode has claimed. The privacy tool keeps
    /// its own ledger of them, and a session on it has its conversation
    /// purged from disk the moment it ends, so a tab wearing one of these
    /// ids is a tab that will not survive. Read on the same slow tick as the
    /// remote lights, cached for the same reason, and an unreadable or absent
    /// ledger just means nothing is private right now.
    static func taintedSessions() -> Set<UUID> {
        if Date().timeIntervalSince(taintedCache.at) < 1.5 { return taintedCache.ids }
        let path = NSHomeDirectory() + "/.config/rin-private/tainted-sessions.json"
        var ids: Set<UUID> = []
        if let data = FileManager.default.contents(atPath: path),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String] {
            ids = Set(list.compactMap(UUID.init(uuidString:)))
        }
        taintedCache = (Date(), ids)
        return ids
    }

    /// Claude's registry of live sessions: one small json per running claude,
    /// named for its pid, rewritten as the session's state changes.
    static var sessionsRoot: String {
        NSHomeDirectory() + "/.claude/sessions"
    }

    private static var remoteCache: (at: Date, ids: Set<UUID>) = (.distantPast, [])

    /// Sessions Remote Control is currently connected to. When the bridge
    /// comes up claude writes its bridge id into that session's file, and
    /// clears the field again the moment the bridge drops, so the presence of
    /// that one string is the whole signal: it covers a session started with
    /// the flag and one switched on halfway through, and it goes out by
    /// itself when the phone loses the session.
    ///
    /// The pid is checked as well, because a claude that died without cleaning
    /// up leaves its file behind, and a stale green light is worse than none.
    /// Read on the main thread only, and cached for a beat: every visible chip
    /// asks on the same tick.
    static func remoteControlledSessions() -> Set<UUID> {
        if Date().timeIntervalSince(remoteCache.at) < 1.5 { return remoteCache.ids }
        let dir = URL(fileURLWithPath: sessionsRoot)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        var ids: Set<UUID> = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = object["sessionId"] as? String,
                  let id = UUID(uuidString: session),
                  let pid = object["pid"] as? Int, isAlive(pid_t(pid))
            else { continue }
            if let bridge = object["bridgeSessionId"] as? String, !bridge.isEmpty {
                ids.insert(id)
            }
        }
        remoteCache = (Date(), ids)
        return ids
    }

    /// A signal-0 probe, with "running but not mine" counted as running: the
    /// call fails that way for another user's process, and a pid number can be
    /// reused by one. Reading that as dead would put out a light that is real.
    private static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// The bundled first-run TUI, and the skeleton it seeds from.
    static var setupScript: String? {
        Bundle.main.path(forResource: "first-run", ofType: "sh")
    }

    static var skeletonPath: String? {
        Bundle.main.url(forResource: "skeleton", withExtension: nil)?.path
    }

    /// The about card, which opens as a tab rather than a window.
    static var aboutScript: String? {
        Bundle.main.path(forResource: "about", ofType: "sh")
    }

    /// The keyboard shortcuts card, the second tab-shaped screen.
    static var shortcutsScript: String? {
        Bundle.main.path(forResource: "shortcuts", ofType: "sh")
    }

    /// The card behind the red bead: what a refused launch means and what to
    /// try, in words a stranger can use.
    static var helpScript: String? {
        Bundle.main.path(forResource: "wont-start", ofType: "sh")
    }

    /// The welcome tour, the card that teaches the glyph, the pin, the held
    /// closes and the face in one screen.
    static var tourScript: String? {
        Bundle.main.path(forResource: "tour", ofType: "sh")
    }

    /// A prepared opening for a new session: a title on the menu and the
    /// prompt the tab speaks first.
    struct SessionStarter: Decodable {
        let title: String
        let prompt: String
    }

    /// Prepared openings offered on the new-session button, read from the
    /// brain (`_meta/starters.json`) at the moment the menu opens. The
    /// standing rule holds: the app SELECTS, writers COMPOSE. Sessions or
    /// the shipped skeleton write this file; the app never invents a word of
    /// it, and no file just means the button stays a plain plus.
    static func sessionStarters() -> [SessionStarter] {
        let url = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("_meta/starters.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SessionStarter].self, from: data)
        else { return [] }
        return Array(list.prefix(8))
    }

    /// This app's own version, which until 2026-08-04 appeared nowhere a person
    /// could see. The menu carried the ENGINE's version and not Rin's, so the
    /// one question a tester actually asks ("which build am I looking at") had
    /// no answer inside the app.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Command for one tab. Every session is spawned under an id the app
    /// chose, so the same tab can resume its own conversation after a
    /// restart. A tab that never got a transcript just starts fresh.
    /// Getting this wrong is fatal rather than cosmetic: claude refuses a
    /// --session-id that is already on disk, so the tab would die on launch.
    /// A custom command is left untouched: the flags are claude's.
    static func command(for sessionID: UUID) -> String {
        command(for: sessionID, resume: hasTranscript(for: sessionID))
    }

    /// The same command with the choice forced, so a tab that just died on
    /// claude refusing one flag can be relaunched with the other.
    static func command(for sessionID: UUID, resume: Bool) -> String {
        // No brain folder yet: the tab IS the setup. The script execs into
        // claude itself (carrying the session id via RIN_SESSION_ID), so
        // this path adds none of the flags below.
        if !isConfigured, let script = setupScript {
            return "exec /bin/zsh \"\(script)\""
        }
        let base = command
        guard base.contains("claude") else { return base }
        let id = sessionID.uuidString.lowercased()
        let mode = permissionMode.trimmingCharacters(in: .whitespaces)
        let modeFlag = mode.isEmpty ? "" : " --permission-mode \(mode)"
        return base + (resume ? " --resume \(id)" : " --session-id \(id)") + modeFlag
    }

    /// The same command carrying an opening prompt (a scheduled nudge's
    /// line), single-quoted for the shell so claude receives it verbatim.
    static func command(for sessionID: UUID, resume: Bool, prompt: String?) -> String {
        let base = command(for: sessionID, resume: resume)
        guard let prompt, !prompt.isEmpty, base.contains("claude") else { return base }
        let quoted = "'" + prompt.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return base + " " + quoted
    }

    /// Clear a claude a previous run left behind. Both the pid and the
    /// session id in its arguments have to match: pids get recycled, and
    /// killing whatever inherited the number would be unforgivable.
    static func killOrphan(pid: pid_t, sessionID: UUID) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier, kill(pid, 0) == 0 else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "command=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).lowercased()
        task.waitUntilExit()
        guard output.contains("claude"), output.contains(sessionID.uuidString.lowercased()) else { return }
        kill(pid, SIGKILL)
    }

    /// A past conversation in this working directory, newest first.
    struct RecentSession: Identifiable {
        let id: UUID
        let label: String
        let modified: Date
    }

    /// Conversations on disk that the app can reopen, including ones started
    /// before it kept a tab list. Labelled with the first thing Peter typed,
    /// because a bare uuid tells him nothing about which session it was.
    static func recentSessions(limit: Int = 12) -> [RecentSession] {
        let dir = URL(fileURLWithPath: transcriptDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> RecentSession? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return RecentSession(id: id, label: firstPrompt(in: url) ?? "untitled", modified: date)
            }
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }

    /// First real user turn in a transcript. Hook output and tool results are
    /// user-role too, so anything bracketed or oversized is skipped.
    private static func firstPrompt(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any]
            else { continue }
            var text: String?
            if let string = message["content"] as? String {
                text = string
            } else if let parts = message["content"] as? [[String: Any]] {
                text = parts.compactMap { $0["text"] as? String }.first
            }
            guard var prompt = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prompt.isEmpty, !prompt.hasPrefix("<"), !prompt.hasPrefix("Caveat:")
            else { continue }
            prompt = prompt.replacingOccurrences(of: "\n", with: " ")
            return prompt.count > 48 ? String(prompt.prefix(48)) + "..." : prompt
        }
        return nil
    }

    /// Terminal text size; the View menu adjusts it live and Cmd-0 comes back
    /// here.
    static let defaultFontSize: CGFloat = 11.5

    static var fontSize: CGFloat {
        let stored = AppConfig.defaults.double(forKey: "fontSize")
        return stored > 0 ? CGFloat(stored) : defaultFontSize
    }

    /// Environment for spawned sessions. The app inherits Finder's minimal
    /// PATH, so the usual CLI locations are prepended explicitly.
    static func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        // If the app was launched from inside a Claude Code session, its
        // markers leak into ours and claude treats sessions as children
        // (disables transcript saving). Sessions must start clean.
        for key in env.keys where key.hasPrefix("CLAUDE") {
            env.removeValue(forKey: key)
        }
        // What the first-run script needs: where the skeleton ships, and
        // which permission mode real sessions open with. Harmless baggage
        // for every other spawn.
        if let skeleton = skeletonPath { env["RIN_SKELETON"] = skeleton }
        let mode = permissionMode.trimmingCharacters(in: .whitespaces)
        if !mode.isEmpty { env["RIN_PERMISSION_MODE"] = mode }
        return env.map { "\($0.key)=\($0.value)" }
    }
}
