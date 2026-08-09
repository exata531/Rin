// keeping claude code up to date
// it updates itself but only while a session is open so a week of not using this is a week behind

import AppKit
import Foundation

/// Keeps the claude CLI current.
///
/// Claude's native install already updates itself in the background, but only
/// while a session is actually running. A week of not opening the app is a week
/// of no updates, and nothing in the UI ever says which version is loaded. This
/// runs `claude update` on a weekly floor, on demand from the menu, and sweeps
/// the old copies the installer leaves behind (a quarter gigabyte each).
enum Updater {
    /// How long to wait between automatic checks.
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    /// Versions kept on disk, newest first, including the running one. Two is
    /// enough to roll back by hand; the rest are dead weight.
    private static let versionsKept = 2

    private static let lastCheckKey = "lastUpdateCheck"
    private static let autoUpdateKey = "autoUpdate"

    private static let versionsDirectory = NSHomeDirectory() + "/.local/share/claude/versions"

    /// Off is a real choice, so the absence of the key has to mean on.
    static var isEnabled: Bool {
        get { AppConfig.defaults.object(forKey: autoUpdateKey) as? Bool ?? true }
        set { AppConfig.defaults.set(newValue, forKey: autoUpdateKey) }
    }

    static var lastCheck: Date? {
        get { AppConfig.defaults.object(forKey: lastCheckKey) as? Date }
        set { AppConfig.defaults.set(newValue, forKey: lastCheckKey) }
    }

    /// Version the `claude` on PATH resolves to. The native install is a
    /// symlink onto a version-named binary, so this costs a stat instead of
    /// launching a 250MB executable just to print a string. A non-symlink
    /// install (npm, a shim) reports nothing rather than guessing.
    static var installedVersion: String? {
        let link = NSHomeDirectory() + "/.local/bin/claude"
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link)
        else { return nil }
        let name = (target as NSString).lastPathComponent
        return name.first?.isNumber == true ? name : nil
    }

    enum Outcome {
        case upToDate(String)
        case updated(from: String?, to: String)
        case failed(String)

        var message: String {
            switch self {
            case .upToDate(let version):
                return "Claude Code is up to date (\(version))."
            case .updated(let from, let to):
                let previous = from.map { " from \($0)" } ?? ""
                return "Updated\(previous) to \(to). Sessions already running keep the old version until you restart them."
            case .failed(let detail):
                return detail
            }
        }
    }

    private static var isRunning = false

    /// Run a check only if the weekly floor has passed. Safe to call on every
    /// launch and from a timer; it decides for itself whether anything is due.
    static func checkIfDue() {
        guard isEnabled else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < interval { return }
        check(force: false)
    }

    /// Run `claude update`. Never blocks the main thread, and never overlaps
    /// itself: a second call while one is in flight is dropped. `force` only
    /// bypasses the enabled switch, for the manual menu item.
    static func check(force: Bool, completion: ((Outcome) -> Void)? = nil) {
        guard !isRunning else { return }
        guard force || isEnabled else { return }
        isRunning = true

        DispatchQueue.global(qos: .utility).async {
            let before = installedVersion
            let outcome = runUpdate(previous: before)
            pruneOldVersions()

            DispatchQueue.main.async {
                isRunning = false
                // A failed run is not a completed check: leaving the stamp
                // alone means the next launch retries instead of waiting out
                // another week on a network blip.
                if case .failed = outcome {} else { lastCheck = Date() }
                if case .updated(_, let version) = outcome {
                    NSLog("claude updated to \(version)")
                }
                completion?(outcome)
            }
        }
    }

    private static func runUpdate(previous: String?) -> Outcome {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "claude update"]
        // Finder hands the app a minimal PATH, so claude's own location has to
        // be put back. The same helper the sessions use already does that, and
        // it also strips the CLAUDE_* markers that would make this look like a
        // nested session.
        task.environment = Dictionary(uniqueKeysWithValues: AppConfig.environment().compactMap { entry in
            guard let split = entry.firstIndex(of: "=") else { return nil }
            return (String(entry[entry.startIndex..<split]), String(entry[entry.index(after: split)...]))
        })
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return .failed("Could not run claude update: \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard task.terminationStatus == 0 else {
            let detail = output.isEmpty ? "exit code \(task.terminationStatus)" : output
            return .failed("Update failed: \(detail)")
        }

        // Trust the symlink over the wording of the output: what the binary
        // prints has changed between releases, where the link never lies.
        let after = installedVersion
        if let after, after != previous {
            return .updated(from: previous, to: after)
        }
        return .upToDate(after ?? previous ?? "unknown")
    }

    /// Each release leaves its whole binary behind, so the folder grows by a
    /// quarter gig a week. Keep the newest few and delete the rest. The
    /// running version is never a candidate even if the sort disagrees, and
    /// anything unparseable is left strictly alone.
    private static func pruneOldVersions() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: versionsDirectory) else { return }
        let current = installedVersion
        let versions = names
            .filter { $0.first?.isNumber == true }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        guard versions.count > versionsKept else { return }

        for name in versions.dropFirst(versionsKept) where name != current {
            try? manager.removeItem(atPath: versionsDirectory + "/" + name)
        }
    }
}
