// the app telling sessions that it is alive and whether i am actually at the mac
// a session cannot see the app from inside the sandbox so it gets told instead of guessing

import AppKit
import Foundation
import IOKit.ps

/// The app's side of a handshake with sessions: a small state file beside
/// the nudge queue, so a session can know whether its landlord is alive,
/// whether Peter is at the Mac, and when the panel last dropped, without
/// walking process trees the sandbox cannot see (twice on the record a
/// session called this app dead while Peter typed through one of its tabs).
///
/// Presence is BANDS, not a trail: "atMac" or "away", derived from input
/// idle age and the lock state. No app names, no window titles, no
/// documents, what Peter is DOING stays unrecorded on purpose (the
/// screen-awareness ban, Peter's July call). This file answers "is anyone
/// home", and nothing else.
final class StateCenter {
    static let fileURL = NudgeCenter.supportDirectory.appendingPathComponent("state.json")

    /// Input older than this counts as away. Coarse on purpose: the reader
    /// needs a door choice, not a keystroke clock.
    private static let idleCutoff: TimeInterval = 5 * 60
    /// Rewritten this often even with nothing happening, so readers can
    /// treat a stale `updatedAt` as "the app is gone" without guessing.
    private static let heartbeat: TimeInterval = 5 * 60

    private var panelLastOpened: Date?
    private var screenLocked = false
    private var timer: Timer?
    private var observers: [(NotificationCenter, Any)] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.write() }))

        // Lock state only arrives by notification, so it is tracked, not
        // polled. Locked always reads as away: a lit screen nobody can see
        // is not presence.
        let dist = DistributedNotificationCenter.default()
        observers.append((dist, dist.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenLocked = true
            self?.write()
        }))
        observers.append((dist, dist.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenLocked = false
            self?.write()
        }))

        let beat = Timer(timeInterval: Self.heartbeat, repeats: true) { [weak self] _ in
            self?.write()
        }
        beat.tolerance = 60
        RunLoop.main.add(beat, forMode: .common)
        timer = beat
        write()
    }

    /// The one question a bubble asks at fire time: is anyone looking.
    /// Locked always reads as away, same as the file reports.
    var isAtMac: Bool { presence() == "atMac" }

    /// Called by the delegate whenever the panel drops, whoever asked.
    func panelOpened() {
        panelLastOpened = Date()
        write()
    }

    /// A clean quit says goodbye. A crash cannot, and leaves `updatedAt` to
    /// go stale instead, the same answer, arriving more slowly.
    func shutdown() {
        write(alive: false)
    }

    private func write(alive: Bool = true) {
        let formatter = ISO8601DateFormatter()
        var state: [String: Any] = [
            "alive": alive,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "updatedAt": formatter.string(from: Date()),
            "presence": presence(),
            "screenLocked": screenLocked,
            "onBattery": onBattery(),
        ]
        if let opened = panelLastOpened {
            state["panelLastOpened"] = formatter.string(from: opened)
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private func presence() -> String {
        guard !screenLocked else { return "away" }
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: anyInput
        )
        return idle < Self.idleCutoff ? "atMac" : "away"
    }

    private func onBattery() -> Bool {
        guard let source = IOPSGetProvidingPowerSourceType(nil)?
            .takeUnretainedValue() as String?
        else { return false }
        return source != kIOPMACPowerKey
    }
}
