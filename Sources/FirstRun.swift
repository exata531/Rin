// the very first launch before there is a brain folder to talk to
// this only does the stuff an ai cannot do for you yet and then it gets out of the way
// the rest of setup is a conversation not a wizard that was the whole idea

import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted the moment first run hands over a brain folder, so the panel
    /// can grow back from its shrink-wrapped setup size.
    static let rinSetupComplete = Notification.Name("RinSetupComplete")
}

/// First run lives in the terminal, not in SwiftUI (Peter's call,
/// 2026-08-02: "embrace the terminal"). While no brain folder is configured,
/// every new tab runs the bundled `first-run.sh`: a TUI in Claude Code's own
/// visual register that finds or installs claude, asks where the brain lives,
/// seeds the skeleton, and execs into claude for login, style, and the setup
/// conversation, all in one tab. The app's whole part is watching for the
/// script's handoff file and adopting the folder it names.

/// Setup progress, observable by the panel. Complete means a brain folder has
/// been chosen and the tab bar may exist.
final class SetupState: ObservableObject {
    static let shared = SetupState()
    @Published var isComplete = AppConfig.isConfigured
}

/// Watches for the setup script's handoff file while the app is
/// unconfigured. The script writes the chosen folder there right before it
/// becomes the first conversation; this side adopts it and stands down.
final class FirstRunWatcher {
    static let shared = FirstRunWatcher()
    private var timer: Timer?

    private var handoffPath: String {
        NSHomeDirectory() + "/.config/rin/chosen-brain"
    }

    func startIfNeeded() {
        guard !AppConfig.isConfigured, timer == nil else { return }
        // A stale handoff from an abandoned run must not configure the app
        // behind the user's back at launch: consume it silently first.
        try? FileManager.default.removeItem(atPath: handoffPath)
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.check()
        }
        poll.tolerance = 0.3
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    private func check() {
        guard let raw = try? String(contentsOfFile: handoffPath, encoding: .utf8) else { return }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }
        try? FileManager.default.removeItem(atPath: handoffPath)
        AppConfig.setWorkingDirectory(path)
        // The last clause of the grant, honoured (2026-08-04). The first-run
        // press promised that Rin starts at login so the key always works, and
        // an app whose whole promise is "one keystroke, always there" that does
        // not survive a restart has broken it at the first opportunity. Stated
        // before the press, switchable from the menu, never silent.
        // A QA rehearsal is exempt: it runs the same bundle, so registering
        // from one would turn it on for the real copy.
        if ProcessInfo.processInfo.environment["RIN_TEST_HOME"] == nil {
            LoginItem.isEnabled = true
        }
        // The transcript lookup was answered for the old (home) directory;
        // the setup tab's conversation lives under the brain folder now.
        AppConfig.forgetTranscriptDirectory()
        SetupState.shared.isComplete = true
        timer?.invalidate()
        timer = nil
        Haptics.thunk()
        NotificationCenter.default.post(name: .rinSetupComplete, object: nil)
    }
}
