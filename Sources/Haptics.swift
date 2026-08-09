// sound is off by default a laptop going off in class is worse than one you have to feel

import AppKit

/// Whether the attention bell makes a noise. Off by default: the haptic is
/// the notification, and a laptop that chirps in a classroom is worse than
/// one Peter has to feel. Toggled from the menu bar's right-click menu.
enum AlertSound {
    private static let key = "alertSoundEnabled"
    private static let soundKey = "bellSound"

    static var isEnabled: Bool {
        get { AppConfig.defaults.bool(forKey: key) }
        set { AppConfig.defaults.set(newValue, forKey: key) }
    }

    /// Which system sound the bell plays when it is allowed to make noise.
    /// One home for the fallback, so the menu and the bell can never
    /// disagree about what "unset" sounds like.
    static var bellSound: String {
        get { AppConfig.defaults.string(forKey: soundKey) ?? "Purr" }
        set { AppConfig.defaults.set(newValue, forKey: soundKey) }
    }

    /// The chimes macOS ships, read off the disk rather than hardcoded, so
    /// the picker survives Apple renaming one.
    static var availableSounds: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds"))?
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted() ?? []
        return names.isEmpty ? [bellSound] : names
    }

}

/// Small taps for small moments. Only felt on a Force Touch trackpad,
/// and only while a finger is on it, which is exactly when they matter.
enum Haptics {
    /// Light tick: hover-adjacent actions, switches, size steps.
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Firmer knock: something was created, destroyed, or committed.
    static func thunk() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// The felt "no": the action was heard and refused. A rail, a guard,
    /// a cmd-W on a session that still has claude behind it.
    static func deny() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// "Come look at me": a session needs Peter. Replaces the bell sound, so
    /// it has to be felt rather than noticed, hence a repeated pattern
    /// instead of one knock. A trackpad only delivers a tap while a finger
    /// rests on it, so the knocks are spread out to catch a hand landing
    /// mid-pattern. Silence when no hand is there is the intended behaviour.
    /// Every knock speaks the same word: the pattern used to end on the
    /// deny sensation, and a summons whose last beat is the refusal word
    /// muddles the one grammar the fingers can read.
    static func alert() {
        let performer = NSHapticFeedbackManager.defaultPerformer
        for delay in [0.0, 0.14, 0.28, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
