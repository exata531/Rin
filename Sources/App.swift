// this is the app itself the menu bar icon and the window that falls out of it
// most of what is in here is stopping macos from treating this like a normal window
// a dropdown should not be draggable or zoomable or wander off its icon and by default it does all three

import AppKit
import SwiftUI

final class DropPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// A dropdown hangs off its icon. It does not go anywhere, and it does not
    /// become a full-height window because a click landed twice.
    ///
    /// The panel is `.titled` for the resize edges and the rounded corners,
    /// and a titlebar carries behaviour along with them even when it is
    /// invisible: the top strip drags the window, and a double click there
    /// zooms or minimises it depending on a system setting. Both were live in
    /// the strip the tab bar sits in. Dragging moved the panel off its anchor
    /// until the next open snapped it back, and a stray double click could
    /// throw it to the full height of the screen. Neither is a thing a
    /// dropdown does, so neither happens here.
    override func zoom(_ sender: Any?) {}
    override func miniaturize(_ sender: Any?) {}

    /// Hover must never act like a click. Claude turns on any-motion mouse
    /// tracking, and SwiftTerm answers a bare move with a motion report
    /// carrying the release marker, which claude reads as a click on the cell
    /// under the pointer: sliding across a menu answered it. SwiftTerm's
    /// mouseMoved is public but not open, so a subclass cannot silence it, and
    /// a local event monitor was the next try and leaked, because the terminal
    /// takes its moves from a tracking area of its own. The window is the one
    /// gate every one of them passes through. Moves over the terminal stop
    /// here; moves anywhere else carry on, so the tab bar keeps its hover.
    /// Buttons are untouched, so clicking a menu choice and dragging out a
    /// selection both still work.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved, isOverTerminal(event) { return }
        super.sendEvent(event)
    }

    /// The terminal currently in the panel, remembered between moves.
    ///
    /// This question used to be answered by hit-testing the whole content
    /// view and then walking back up the superview chain, on EVERY mouse
    /// move, and a move over a terminal is not a rare event, because claude
    /// keeps any-motion tracking switched on the entire time it is running.
    /// A recursive walk of the view tree, hundreds of times a second, to
    /// re-learn a fact that changes when a tab is switched.
    ///
    /// Only one terminal is ever in the panel at a time, so it is found once
    /// and kept. The reference is weak and re-checked against the window, so
    /// a closed tab or a switched one falls out by itself.
    private weak var terminalInPanel: RinTerminalView?

    private func isOverTerminal(_ event: NSEvent) -> Bool {
        if terminalInPanel?.window !== self {
            terminalInPanel = Self.findTerminal(in: contentView)
        }
        guard let terminal = terminalInPanel else { return false }
        // Containment rather than a hit test. Equivalent here because nothing
        // in this panel is ever drawn ON TOP of the terminal, the bar sits
        // above it in a stack, and the caret is its own child, and if that
        // ever stops being true, this is the line that has to change.
        return terminal.bounds.contains(terminal.convert(event.locationInWindow, from: nil))
    }

    private static func findTerminal(in view: NSView?) -> RinTerminalView? {
        guard let view else { return nil }
        if let terminal = view as? RinTerminalView { return terminal }
        for child in view.subviews {
            if let found = findTerminal(in: child) { return found }
        }
        return nil
    }
}

/// Invisible drag catcher sitting over the menu bar icon. NSStatusBarButton
/// does no drag handling of its own, so a file carried at the icon had
/// nowhere to land. This springs the panel open mid-drag, the way Finder
/// springs a folder open, and takes a drop straight onto the icon too.
/// Mouse clicks are handed back to the button underneath, so the icon still
/// toggles and still opens its menu.
final class StatusDropView: NSView {
    var onDragEnter: (() -> Void)?
    var onDrop: (([String]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(dropPaths(sender.draggingPasteboard)) ?? false
    }

    private func dropPaths(_ pasteboard: NSPasteboard) -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return [] }
        return urls.map(\.path)
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private static var shared: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var panel: DropPanel!
    private let store = SessionStore()
    private let nudges = NudgeCenter()
    private let faces = FaceCenter()
    private let state = StateCenter()
    private let bubble = BubbleCenter()
    private var clickMonitor: Any?
    private var dragMonitors: [Any] = []
    private var pendingHide: DispatchWorkItem?
    private var mouseUpWatcher: Timer?
    private var isDismissPending = false
    private var isDragInFlight = false
    private var didAcceptDrop = false
    private var hiddenAt = Date.distantPast
    private var needsAttention = false {
        didSet {
            guard needsAttention != oldValue else { return }
            statusItem.button?.image = Self.statusImage(attention: needsAttention)
            // "Come look" and "leave it, it's cooking" cannot share the icon:
            // attention silences the breath until it has been answered.
            if needsAttention { setIconBreathing(false) }
        }
    }

    private var workingPoll: Timer?

    /// The glyph itself breathes while any tab has a claude mid-task, so a
    /// glance at the menu bar answers "is it still going" with the panel
    /// closed. The animation runs on the render server; the app's only cost
    /// is this look at the conversation files.
    ///
    /// The cadence ADAPTS, because this used to be a flat 2-second repeat
    /// that ran for the life of the app and did real disk work every time,
    /// thirty rounds a minute, forever, on a laptop, most of it for a panel
    /// nobody was looking at (found in the 2026-08-03 audit). Three bands
    /// now: quick while the panel is on screen and the numbers are being
    /// read, slower when it is hidden but something is still running, and
    /// slowest when the app is genuinely idle. Opening or closing the panel
    /// re-pitches it immediately, so the fast band starts the moment it is
    /// worth paying for.
    private func watchForWork() { scheduleWorkPoll() }

    private func workPollInterval() -> TimeInterval {
        if panel.isVisible { return 2 }
        return store.sessions.contains(where: \.isRunning) ? 6 : 15
    }

    /// Re-pitch the poll. Cheap enough to call on every panel transition.
    private func scheduleWorkPoll() {
        workingPoll?.invalidate()
        let interval = workPollInterval()
        let poll = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.pollWork()
            self?.scheduleWorkPoll()
        }
        // A generous tolerance lets the system coalesce this with whatever
        // else is waking the CPU, which is the whole trick to a background
        // timer being cheap rather than merely infrequent.
        poll.tolerance = interval / 4
        RunLoop.main.add(poll, forMode: .common)
        workingPoll = poll
    }

    private func pollWork() {
        store.refreshWork()
        let working = !needsAttention && store.sessions.contains { $0.isWorking }
        setIconBreathing(working)
        // The face answers the same two events the glyph does: a tab asking
        // for him outranks a tab grinding away, and neither is re-announced
        // while it holds (wave five, second pass).
        faces.react(needsAttention ? .attention : (working ? .working : .nothing))

        // Tab colours and the scrollbar are panel furniture. Reading two
        // ledgers off disk and touching every terminal view to style a
        // scroller nobody can see is work with no viewer, so it waits.
        if panel.isVisible {
            let connected = AppConfig.remoteControlledSessions()
            let tainted = AppConfig.taintedSessions()
            for session in store.sessions {
                session.refresh(remote: connected, tainted: tainted)
                (session.terminalView as? RinTerminalView)?.syncScroller()
            }
        }

        // The hourly claim that keeps claude's retention sweep off
        // conversations these tabs still own. Its own guard makes this a
        // date comparison on all but one tick an hour.
        AppConfig.claimTranscriptsIfDue(for: store.sessions.map(\.id))

        // Midnight is the private tabs' curfew: on the first tick of a new
        // day, every tab the private section claimed is hung up and taken
        // off the bar. The stamp seeds silently on first run so an update
        // installed mid-afternoon cannot reap that same morning.
        let dayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let stamped = AppConfig.defaults.double(forKey: "privateReapDay")
        if stamped == 0 || dayStart > stamped {
            if stamped != 0 { store.reapPrivateTabs() }
            AppConfig.defaults.set(dayStart, forKey: "privateReapDay")
        }
    }

    private func setIconBreathing(_ on: Bool) {
        guard let button = statusItem.button else { return }
        // Reduce Motion stills the glyph; the panel's status dot still says
        // working, so no information is lost, only the movement. The gate
        // sits here rather than at the callers so a setting flipped mid-run
        // is honoured on the next tick of the work watcher.
        if on, !Motion.reduced {
            guard button.layer?.animation(forKey: "rinBreath") == nil else { return }
            button.wantsLayer = true
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 1.0
            breath.toValue = 0.45
            breath.duration = Motion.breatheDuration
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(breath, forKey: "rinBreath")
        } else {
            button.layer?.removeAnimation(forKey: "rinBreath")
        }
    }

    /// Menu bar glyph, with an optional attention dot bottom-right.
    /// Template image so it adapts to menu bar appearance.
    private static func statusImage(attention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
            let glyph = NSAttributedString(string: "凛", attributes: attrs)
            let size = glyph.size()
            glyph.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            if attention {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5.5, y: 0.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would restore the same tabs and put two claudes on
        // one conversation. Bow out before touching the saved tab list, and
        // with exit() rather than terminate() so the quit path (which writes
        // that list) never runs from a copy that owns no sessions.
        // RIN_TEST_HOME opts out, for QA runs under a scratch HOME: a QA twin
        // runs on its own wiped settings suite (see AppConfig.defaults), so it
        // shares no tab list and the guard's reason does not apply to it.
        if ProcessInfo.processInfo.environment["RIN_TEST_HOME"] == nil {
            let mine = ProcessInfo.processInfo.processIdentifier
            let twins = NSRunningApplication
                .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != mine }
            if let original = twins.first {
                original.activate()
                exit(0)
            }
        }

        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        installSignalHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.statusImage(attention: false)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Rin"
            button.imagePosition = .imageLeading
            // The face is expressive to the eye and noise to a screen
            // reader; the item stays "Rin" to VoiceOver whatever it wears.
            button.setAccessibilityLabel("Rin")

            let catcher = StatusDropView(frame: button.bounds)
            catcher.autoresizingMask = [.width, .height]
            catcher.onDragEnter = { [weak self] in self?.springOpenForDrag() }
            catcher.onDrop = { [weak self] paths in self?.deliverDrop(paths) ?? false }
            button.addSubview(catcher)
        }

        NotificationCenter.default.addObserver(
            forName: .rinDidAcceptDrop, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // The drop lands before the mouse-up is noticed, so a flag has to
            // carry the news forward; cancelling a dismissal that has not
            // been scheduled yet cancels nothing.
            self.didAcceptDrop = true
            self.isDragInFlight = false
            self.cancelPendingHide()
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }

        NotificationCenter.default.addObserver(
            forName: .rinNeedsAttention, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.panel.isVisible else { return }
            self.needsAttention = true
            // The away rung, opt-in: the dot and the trackpad tap are exactly
            // right at the Mac and reach nobody away from it, and the
            // presence tracking already knows which is true. AwayNotice
            // itself refuses when the switch is off, so this costs nothing
            // for everyone who never opted in.
            guard AwayNotice.isEnabled, !self.state.isAtMac else { return }
            let session = self.store.sessions.first {
                $0 === note.object as? TerminalSession
                    || $0.terminalView === note.object as? NSView
            }
            AwayNotice.post(
                title: session.map { "\($0.displayTitle) wants you" } ?? "A session wants you")
        }

        buildPanel()
        store.isPanelVisible = { [weak self] in self?.panel.isVisible ?? false }
        // Until a brain folder exists, the first tab runs the setup TUI and
        // this watcher waits for the folder it chooses. When it lands, the
        // shrink-wrapped setup panel grows back to its working size.
        FirstRunWatcher.shared.startIfNeeded()
        NotificationCenter.default.addObserver(
            forName: .rinSetupComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.growPanelAfterSetup()
            // The tour, once, the moment there is a brain to tour. It lands
            // on the bar WITHOUT stealing the tab, because the tab he is in
            // is the setup conversation itself: a chip named "tour" is the
            // invitation, and the menus keep it reachable forever after.
            if !AppConfig.defaults.bool(forKey: "tourShown") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Stamped when the card actually lands, not when it is
                    // promised: a quit inside this delay used to spend the
                    // one showing on a tour nobody saw.
                    AppConfig.defaults.set(true, forKey: "tourShown")
                    self?.store.openTour(activate: false)
                }
            }
        }
        watchForWork()
        // Bring back last run's tabs, each resuming its own conversation,
        // and pre-warm so the first click drops into a live claude. The
        // panel stays closed (a login launch should be silent).
        store.restore()
        scheduleUpdateChecks()

        // Scheduled nudges: sessions write the queue, this app is the clock
        // that survives them. Policy and phrasing live with the writer.
        nudges.raiseDot = { [weak self] in
            guard let self, !self.panel.isVisible else { return }
            self.needsAttention = true
        }
        nudges.openPanel = { [weak self] prompt in
            guard let self else { return }
            self.store.newSession(prompt: prompt)
            if !self.panel.isVisible { self.showPanel(activate: false) }
        }
        nudges.flashFace = { [weak self] reactions in self?.faces.flash(reactions) }
        // The bubble rung: one pre-written line in a post-it under the
        // glyph, wearing whatever face the bar already wears. Tapping it
        // opens the real panel, on the nudge's prompt when it carries one,
        // so a line can start an actual conversation.
        nudges.isAtMac = { [weak self] in self?.state.isAtMac ?? true }
        nudges.showBubble = { [weak self] text, prompt in
            self?.bubble.show(text: text, face: FaceState.shared.current, prompt: prompt)
        }
        bubble.anchor = { [weak self] in self?.statusAnchorRect() }
        bubble.onTap = { [weak self] prompt in
            guard let self else { return }
            if let prompt, !prompt.isEmpty { self.store.newSession(prompt: prompt) }
            self.showPanel()
        }
        nudges.start()

        // The kaomoji face beside the glyph: sessions write the pool for the
        // current mood, the app wears one and rotates so nothing wears out.
        // Menu-bar font and a thin space keep the face and the glyph from
        // touching; the panel's empty state mirrors it through FaceState.
        faces.show = { [weak self] face in
            FaceState.shared.current = face
            guard let button = self?.statusItem.button else { return }
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.title = face.map { "\u{2009}" + $0 } ?? ""
        }
        faces.start()

        // The state file: presence, panel opens, alive, the app's half of
        // the handshake with sessions, so nudges can pick a door honestly
        // and nobody has to guess whether the landlord is alive.
        state.start()

        // The bell's opt-in away route. Tapping the notification lands in
        // the panel; the notification center itself is only ever touched
        // when the switch is actually on.
        AwayNotice.openPanel = { [weak self] in self?.showPanel() }
        AwayNotice.activate()

        HotkeyManager.shared.register { [weak self] in
            guard let self else { return }
            if self.panel.isVisible {
                self.hidePanel()
            } else {
                self.showPanel()
            }
        }

        // The terminal view's scrollWheel is not overridable, so every scroll
        // over the terminal is caught here and handed to the view, which
        // spends it in pixels rather than in the jumps SwiftTerm would make.
        // Only scrolls actually ON the terminal are taken; the rest of the
        // panel keeps its own.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === self.panel,
                  let view = self.store.active?.terminalView as? RinTerminalView,
                  view.window === self.panel,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else { return event }
            return view.handleScroll(event) ? nil : event
        }

        // Typing snaps the terminal back to the live line, so the pixels the
        // scroll was holding onto have to go back with it.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            (self.store.active?.terminalView as? RinTerminalView)?.clearSubLine()
            return event
        }

    }

    /// The menu bar this app never shows.
    ///
    /// An accessory app has no menu on screen, and this one had no menu AT
    /// ALL, which is a different thing: the main menu is where macOS routes
    /// every command keystroke before anything else sees it. Without one,
    /// Copy, Paste and Select All worked only if the terminal happened to
    /// catch them itself, Cmd-0 did not exist, and Services and the standard
    /// text shortcuts had nowhere to hook. The items point at nothing on
    /// purpose: a nil target sends each one down the responder chain, which
    /// ends at whichever terminal is on screen.
    private func installMainMenu() {
        let main = NSMenu()

        let app = NSMenuItem()
        app.submenu = NSMenu(title: "Rin")
        app.submenu?.addItem(
            withTitle: "Quit Rin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(app)

        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // The one table-stakes terminal feature the panel lacked: finding
        // something said earlier meant scrolling and squinting. On the key
        // every Mac app keeps it under.
        let find = editMenu.addItem(
            withTitle: "Find", action: #selector(findInSession), keyEquivalent: "f")
        find.target = self
        edit.submenu = editMenu
        main.addItem(edit)

        let view = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let bigger = viewMenu.addItem(
            withTitle: "Bigger Text", action: #selector(textBigger), keyEquivalent: "+")
        bigger.target = self
        // Cmd-plus is typed without the shift on most keyboards, so the
        // equals key carries the same command the way every Mac app does it.
        let biggerAlias = viewMenu.addItem(
            withTitle: "Bigger Text", action: #selector(textBigger), keyEquivalent: "=")
        biggerAlias.target = self
        biggerAlias.isAlternate = true
        biggerAlias.isHidden = true
        let smaller = viewMenu.addItem(
            withTitle: "Smaller Text", action: #selector(textSmaller), keyEquivalent: "-")
        smaller.target = self
        // The missing third of the pair. Every Mac app with Cmd-plus and
        // Cmd-minus has Cmd-0, and this one just did not.
        let actual = viewMenu.addItem(
            withTitle: "Actual Size", action: #selector(textActualSize), keyEquivalent: "0")
        actual.target = self
        viewMenu.addItem(.separator())
        // Jump to a tab by typing a few letters of its name. Starts earning
        // its keep at five or more tabs, which the tab restore actively
        // encourages.
        let jump = viewMenu.addItem(
            withTitle: "Jump to Tab…", action: #selector(jumpToTab), keyEquivalent: "k")
        jump.target = self
        view.submenu = viewMenu
        main.addItem(view)

        // Where a Mac app keeps its cheat sheet, on the key the apps that have
        // one all use (2026-08-08). Nine bindings had accumulated and the only
        // place any of them were written down was the source. Cmd-1 through
        // Cmd-9 were the worst of it: a shortcut nobody can discover is a
        // shortcut nobody presses.
        let help = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let keys = helpMenu.addItem(
            withTitle: "Keyboard Shortcuts", action: #selector(showShortcuts), keyEquivalent: "/")
        keys.target = self
        let tour = helpMenu.addItem(
            withTitle: "Welcome Tour", action: #selector(showTour), keyEquivalent: "")
        tour.target = self
        help.submenu = helpMenu
        main.addItem(help)

        NSApp.mainMenu = main
    }

    @objc private func textBigger() { store.adjustFont(by: 1) }
    @objc private func textSmaller() { store.adjustFont(by: -1) }
    @objc private func textActualSize() { store.resetFont() }

    /// Actual Size greys out at actual size, the way it does in every Mac
    /// View menu: a command that can do nothing should say so before the
    /// click, not answer it with the felt no. Bigger and Smaller keep their
    /// rail on purpose, the ends refuse out loud (the 2026-08-04 call).
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(textActualSize) {
            return AppConfig.fontSize != AppConfig.defaultFontSize
        }
        return true
    }

    private var updateTimer: Timer?

    /// Weekly floor under claude's own updater. Checked shortly after launch
    /// (delayed so it never competes with restoring the tabs) and again every
    /// few hours, because this app is meant to sit in the menu bar for weeks
    /// and a launch-only check would never fire on a Mac that is not rebooted.
    private func scheduleUpdateChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { Updater.checkIfDue() }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { _ in
            Updater.checkIfDue()
        }
        timer.tolerance = 30 * 60
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private var signalSources: [DispatchSourceSignal] = []

    /// A kill from the terminal, or a logout, never reaches the app delegate,
    /// so the sessions would be left running with no window attached. Watch
    /// for it and hang up properly. SIGTERM only, deliberately: a disposition
    /// set to ignore survives into the children, and sessions that ignored
    /// SIGINT would swallow ctrl-C in every tab.
    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            // The kill path skips applicationWillTerminate, so the state
            // file says goodbye here too, otherwise a clean kill reads as
            // a crash until the heartbeat goes stale.
            self?.state.shutdown()
            self?.store.shutdownAll()
            exit(0)
        }
        source.activate()
        signalSources.append(source)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
        store.shutdownAll()
    }

    /// The setup TUI is a few short lines; a full-size panel around it reads
    /// as an empty room. First run opens shrink-wrapped and the panel grows
    /// to its normal size the moment a brain folder is chosen.
    private static let setupPanelSize = NSSize(width: 560, height: 360)

    private func buildPanel() {
        let defaults = AppConfig.defaults
        var width = defaults.object(forKey: "panelW") as? Double ?? 760
        var height = defaults.object(forKey: "panelH") as? Double ?? 500
        if !AppConfig.isConfigured {
            width = Self.setupPanelSize.width
            height = Self.setupPanelSize.height
        }
        panel = DropPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        // Floating, not status-bar level. An input method draws its candidate
        // list in a window of its own, and that window sits BELOW the status
        // bar level: at .statusBar this panel covered it, so typing Chinese or
        // Japanese meant picking from a list nobody could see. Floating still
        // sits above every ordinary window of every app, which is all a
        // dropdown needs, and it lets the candidates land on top where they
        // belong.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Clear, so the navigation layer can actually lens (2026-08-03). The
        // window used to be painted opaque slate edge to edge, which meant
        // the tab bar's behind-window material had nothing behind it to
        // blur: the app asked for glass and got flat paint. The terminal
        // region paints its own opaque slate, so only the bar goes see
        // through, which is where Apple puts glass and nowhere else.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: DropdownView(store: store))
        hosting.safeAreaRegions = []
        panel.contentView = hosting
    }

    @objc private func statusItemClicked() {
        // Control-click IS a right-click, everywhere on the Mac since one
        // button was all a mouse had. A status item wired by hand has to keep
        // that promise itself, or the menu is unreachable from a mouse with
        // no second button and a hand that never learned the other gesture.
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
            return
        }
        if panel.isVisible {
            hidePanel()
        } else if Date().timeIntervalSince(hiddenAt) < 0.35 {
            // The same click that just auto-hid the panel; swallowing it
            // makes icon-click a true toggle instead of hide-then-reshow.
            return
        } else {
            showPanel()
        }
    }

    /// The menu row's half of the toggle. The status-item click keeps its
    /// own path above because it also swallows the click that just auto-hid
    /// the panel; a menu row cannot race that hide, so the plain flip is
    /// the whole job here.
    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        // Identity first, the way About sits at the top of an app menu, and it
        // carries the version rather than hiding it behind another click: the
        // question a tester actually asks is "which build is this", and until
        // 2026-08-04 the only version in this menu belonged to Claude Code.
        // Pressing it opens the card as a TAB, per the standing call that a
        // screen needing room is a tab and not a window.
        let about = NSMenuItem(title: "Rin \(AppConfig.appVersion)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.toolTip = "What this is, which build, and where your brain lives. Opens in a tab."
        menu.addItem(about)
        // Sits with identity rather than with the settings block: it is
        // reference, not a thing to change. This menu is the one surface
        // somebody finds without knowing anything, so the cheat sheet has to
        // be reachable from here as well as from Cmd-slash, a shortcut is a
        // poor way to advertise the list of shortcuts.
        let keys = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(showShortcuts), keyEquivalent: "")
        keys.target = self
        keys.toolTip = "Every key this app answers to. Opens in a tab."
        menu.addItem(keys)
        // Reference too, beside the cheat sheet: this menu is the one surface
        // somebody finds without knowing anything, which is exactly who the
        // tour is for.
        let tour = NSMenuItem(title: "Welcome Tour", action: #selector(showTour), keyEquivalent: "")
        tour.target = self
        tour.toolTip = "The lay of the land in one screen. Opens in a tab."
        menu.addItem(tour)
        menu.addItem(.separator())
        // Identity, then ONE settings door, then the rows a person acts on,
        // then the destructive block (shortened 2026-08-08, Peter: the menu
        // had grown past what a glance takes in). The toggles used to lead
        // at top level because a switch is what somebody flips, but the pin
        // now sits permanently on the tab bar and login is set once, so
        // everything a person SETS lives behind Settings and the top level
        // keeps only what a person DOES. The engine's version line moved
        // into Settings with its own controls; the about card carries it
        // too.
        menu.addItem(buildSettingsItem())
        // The panel's own row, with its key printed where a Mac prints keys:
        // beside the thing it does (Peter, 2026-08-09, moving the shortcut
        // off the about card — that card is an authenticity plate, and a
        // how-to line was the one row on it that wasn't identity). The
        // global hotkey already answers from any app; this row is the same
        // door with the address on it, and the second key, control comma,
        // stays on the shortcuts card with the rest of the list.
        let panelRow = NSMenuItem(
            title: panel.isVisible ? "Hide Panel" : "Show Panel",
            action: #selector(togglePanel), keyEquivalent: "`")
        panelRow.keyEquivalentModifierMask = [.control]
        panelRow.target = self
        menu.addItem(panelRow)
        menu.addItem(buildReopenItem())
        if let sweep = buildCloseDeadItem() { menu.addItem(sweep) }
        menu.addItem(.separator())
        // Everything below here ends something, so everything below here is
        // HELD rather than clicked (2026-08-08, Peter's ask). The tab bar
        // settled this argument already: a live session does not close on a
        // click, you hold the x. These three end every session at once, or the
        // app, and they were one slipped pointer away from happening.
        //
        // The queued restart says so here, and this is where it gets called
        // off, the menu is the only surface a pending background action can
        // honestly live on in a menu-bar app. Cancelling is not destructive, so
        // it stays an ordinary row: making somebody hold a button down to STOP
        // a thing from happening is the wrong way round.
        if restartPending {
            let cancel = NSMenuItem(
                title: "Cancel Restart", action: #selector(restartApp), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
            let waiting = NSMenuItem(
                title: "Waiting for sessions to finish…", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
            menu.addItem(waiting)
        } else {
            menu.addHoldItem(title: "Restart Rin") { [weak self] in self?.restartApp() }
        }
        // ⌘Q keeps working on the main menu and is deliberately left alone: a
        // Mac where the standard quit key does nothing is a broken Mac, and the
        // hold is here to stop the POINTER slipping, not to take the keyboard
        // away.
        menu.addHoldItem(title: "Quit Rin", hint: "⌘Q") { NSApp.terminate(nil) }
        // Uninstall is last, under its own rule, as far from anything routine
        // as the menu can put it, and it is the only row that wears red. It is
        // also by far the longest hold, three full seconds against the one
        // second everything else asks (lengthened 2026-08-08, Peter's call):
        // this one does not come back, so charging it should feel like a
        // decision being made, not a click that ran long.
        menu.addItem(.separator())
        menu.addHoldItem(
            title: "Uninstall Rin…", destructive: true, holdTime: 3.0
        ) { [weak self] in
            self?.uninstallApp()
        }
        // Anchored by SCREEN coordinates, the same way the bubble hangs off
        // the glyph (2026-08-08, third try, and the working one). The first
        // recipe handed the menu to the status item and sent a synthetic
        // click, which opened it far to the right of the glyph. The second
        // named the button as the anchor view and gave a point in its
        // coordinates, and that landed off in the bar AND half above the
        // screen with a scroll chevron, view-space maths at popup time,
        // mid-click, inside the status bar's own window, is a conversion
        // AppKit gets to reinterpret. Screen space is the one system nobody
        // converts: the glyph's rect is already computed for the bubble, the
        // bubble has never once missed, and with no view given the point IS
        // the menu's top-left on screen. Just under the bar, left edges
        // lined up.
        guard let anchor = statusAnchorRect() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.minY - 4), in: nil)
    }

    /// Past conversations in this folder, openable as tabs. Covers the ones
    /// started before the app kept a tab list, and any tab closed by hand.
    private func buildReopenItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Reopen Conversation", action: nil, keyEquivalent: "")
        let recents = AppConfig.recentSessions()
        guard !recents.isEmpty else {
            item.isEnabled = false
            return item
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let submenu = NSMenu()
        for recent in recents {
            let entry = NSMenuItem(
                title: "\(formatter.string(from: recent.modified))  \(recent.label)",
                action: #selector(reopenSession(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = recent.id
            entry.state = store.sessions.contains { $0.id == recent.id } ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    /// The one settings door: the two switches, the bell, and the engine's
    /// updater. Three groups inside, separated, so the door opens onto a
    /// menu with the same one-glance shape the top level keeps.
    private func buildSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        submenu.addItem(login)
        // Also on the tab bar as the pin, permanently since 2026-08-08; this
        // copy is for the person who looks for a setting where settings live.
        let pin = NSMenuItem(title: "Keep Panel Open", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.state = store.isPinned ? .on : .off
        pin.toolTip = "On: the panel stays up when you click into another app."
        submenu.addItem(pin)
        submenu.addItem(.separator())
        submenu.addItem(buildSoundItem())
        // The bell's away half. At the Mac the bell is a dot and a trackpad
        // tap, exactly right and invisible from anywhere else; this closes
        // the away gap through Notification Center, opt-in, for people who
        // want it closed. The silent-in-class default is untouched.
        let away = NSMenuItem(
            title: "Notify When Away", action: #selector(toggleAwayNotice), keyEquivalent: "")
        away.target = self
        away.state = AwayNotice.isEnabled ? .on : .off
        away.toolTip = "A Notification Center alert when a session rings while you are away from the Mac."
        submenu.addItem(away)
        submenu.addItem(.separator())

        // The engine's updater. Claude updates itself only while a session
        // runs, so the weekly floor covers the weeks nobody opens one, and
        // the disabled line answers "which claude, checked when" at a glance.
        let auto = NSMenuItem(
            title: "Update Claude Code Weekly", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        auto.target = self
        auto.state = Updater.isEnabled ? .on : .off
        auto.toolTip = "Runs claude update once a week in the background."
        submenu.addItem(auto)
        let now = NSMenuItem(
            title: "Check for Updates Now", action: #selector(checkForUpdates), keyEquivalent: "")
        now.target = self
        submenu.addItem(now)
        var detail = Updater.installedVersion.map { "Claude Code \($0)" } ?? "Claude Code"
        if let last = Updater.lastCheck {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            detail += ", checked \(formatter.string(from: last))"
        }
        let stamp = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
        stamp.isEnabled = false
        submenu.addItem(stamp)

        item.submenu = submenu
        return item
    }

    @objc private func checkForUpdates() {
        Updater.check(force: true) { outcome in
            let alert = NSAlert()
            alert.messageText = "Rin"
            alert.informativeText = outcome.message
            if case .failed = outcome { alert.alertStyle = .warning }
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func toggleAutoUpdate() {
        Updater.isEnabled.toggle()
    }

    /// Sweep out ended tabs, shown only when there are some. A tab leaves the
    /// saved list by being closed and no other way, so one that comes back
    /// dead keeps coming back until it goes, and the only path out used to be
    /// closing each one by hand inside the panel.
    private func buildCloseDeadItem() -> NSMenuItem? {
        let count = store.deadSessions.count
        guard count > 0 else { return nil }
        let item = NSMenuItem(
            title: count == 1 ? "Close Ended Tab" : "Close \(count) Ended Tabs",
            action: #selector(closeDeadTabs),
            keyEquivalent: ""
        )
        item.target = self
        item.toolTip = "Ended sessions reopen on every launch until they leave the tab list."
        return item
    }

    @objc private func closeDeadTabs() {
        store.closeDead()
    }

    @objc private func reopenSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.openSession(id: id)
        if !panel.isVisible { showPanel() }
    }

    @objc private func togglePin() {
        store.isPinned.toggle()
        Haptics.tap()
    }

    @objc private func showAbout() {
        if !panel.isVisible { showPanel() }
        store.openAbout()
    }

    @objc private func showShortcuts() {
        if !panel.isVisible { showPanel() }
        store.openShortcuts()
    }

    @objc private func showTour() {
        if !panel.isVisible { showPanel() }
        store.openTour()
    }

    @objc private func findInSession() {
        guard panel.isVisible, store.active != nil else { return }
        store.isSearching = true
        store.searchNonce += 1
    }

    @objc private func jumpToTab() {
        guard panel.isVisible, !store.sessions.isEmpty else { return }
        // The summon key is also the dismiss key, the way Spotlight's is: a
        // second Cmd-K with the switcher up means never mind.
        store.isSwitching.toggle()
    }

    @objc private func toggleAwayNotice() {
        AwayNotice.isEnabled.toggle()
    }

    /// `rin://install/<module>`, arriving from the modules page.
    ///
    /// The app installs nothing itself, that went away with the Modules
    /// screen (2026-08-04). What it does is open a tab on the subject, the
    /// same handoff Raycast's web store makes: the page asks, the app opens,
    /// and the decision happens where the person can read what they are
    /// agreeing to. A system alert stands between the two, because a link on a
    /// page must never be able to start a conversation on somebody's Mac
    /// without them saying so first.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let name = urls.compactMap(DeepLink.moduleToInstall(in:)).first else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        guard AppConfig.isConfigured else {
            alert.messageText = "Rin has no brain folder yet"
            alert.informativeText = "Finish setting Rin up first, then this link will work."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        alert.messageText = "Add the \(name) module?"
        alert.informativeText = """
            A web page asked Rin to open a session about it. Nothing is installed \
            yet: the tab will say what \(name) can do and what it would add to your \
            brain folder, and ask before writing anything.
            """
        alert.addButton(withTitle: "Open a Session")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.newSession(prompt: DeepLink.prompt(forInstalling: name))
        if !panel.isVisible { showPanel() }
    }

    @objc private func toggleLogin() {
        LoginItem.isEnabled.toggle()
    }

    /// What the attention bell sounds like, as ONE question instead of two
    /// (2026-08-04). This used to be a checkbox for whether sound played at
    /// all and, under it, a separate list of chimes, so the menu offered a
    /// picker that did nothing whenever the box above it was off, which is
    /// the shape of a setting nobody can predict. There is one state here and
    /// it has one control: which sound, or none.
    ///
    /// Picking a chime turns sound on and previews it, because the point of
    /// choosing a sound is hearing it.
    private func buildSoundItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Alert Sound", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let silent = NSMenuItem(title: "Silent", action: #selector(silenceBell), keyEquivalent: "")
        silent.target = self
        silent.state = AlertSound.isEnabled ? .off : .on
        silent.toolTip = "The bell is a trackpad tap only."
        submenu.addItem(silent)
        submenu.addItem(.separator())

        let current = AlertSound.bellSound
        for name in AlertSound.availableSounds {
            let entry = NSMenuItem(title: name, action: #selector(pickBellSound(_:)), keyEquivalent: "")
            entry.target = self
            entry.state = (AlertSound.isEnabled && name == current) ? .on : .off
            submenu.addItem(entry)
        }

        item.submenu = submenu
        item.toolTip = "What the bell plays when a session wants you."
        return item
    }

    @objc private func silenceBell() {
        AlertSound.isEnabled = false
    }

    @objc private func pickBellSound(_ sender: NSMenuItem) {
        AlertSound.bellSound = sender.title
        AlertSound.isEnabled = true
        NSSound(named: sender.title)?.play()
    }

    /// Restarting ends every session, because each one is a child of this
    /// process and nothing here can outlive it. The conversation always comes
    /// back on resume; the turn claude was in the middle of does not. So a
    /// restart asks first when something is mid-task, rather than pulling the
    /// floor out while it types.
    /// Give the Mac back exactly as it was found (2026-08-03). Dragging the
    /// app to the Trash used to leave its support folder, its preferences,
    /// the first-run handoff, and a login item behind, invisible litter on
    /// someone else's machine, which is a rotten thing for a thing you were
    /// only trying out.
    ///
    /// What it will NOT touch, on purpose: the brain folder, because those
    /// are their notes and deleting a person's writing to tidy up after
    /// yourself is not tidying, and Claude Code, because it is not ours to
    /// remove. Both are named in the dialog so the choice is theirs.
    @objc private func uninstallApp() {
        let brain = AppConfig.isConfigured
            ? AppConfig.workingDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            : nil

        let alert = NSAlert()
        alert.messageText = "Uninstall Rin?"
        var body = """
            Rin will close its sessions, delete its own settings and saved \
            tabs, remove itself from Start at Login, and move the app to the \
            Trash.
            """
        if let brain {
            body += "\n\nYour brain folder at \(brain) is left alone; it holds your notes, "
                + "and it is yours to keep or delete."
        }
        body += "\n\nClaude Code stays installed; Rin did not put it there to begin with."
        alert.informativeText = body
        alert.alertStyle = .warning
        // Cancel is the default on a destructive action: a stray Return key
        // must not be able to uninstall anything.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Uninstall")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        store.shutdownAll()
        LoginItem.isEnabled = false
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: NudgeCenter.supportDirectory)
        try? fileManager.removeItem(atPath: NSHomeDirectory() + "/.config/rin")
        if let domain = Bundle.main.bundleIdentifier {
            AppConfig.defaults.removePersistentDomain(forName: domain)
            AppConfig.defaults.synchronize()
        }
        // Into the Trash rather than deleted outright, so a change of heart
        // is one drag away.
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            NSApp.terminate(nil)
        }
    }

    /// A restart queued behind "wait for the sessions to finish". Held so it
    /// can be SEEN and CALLED OFF: before 2026-08-03 this waited up to five
    /// minutes with nothing in the menu bar, nothing in the menu, and no way
    /// to change your mind, you pressed a button, watched nothing happen,
    /// and the app vanished later while you were typing.
    private var restartPending = false {
        didSet {
            statusItem.button?.toolTip = restartPending
                ? "Rin: restarting when the sessions finish"
                : "Rin"
        }
    }

    @objc private func restartApp() {
        // Same command, second press: change your mind.
        if restartPending {
            restartPending = false
            Haptics.tap()
            return
        }
        // Ask the disk before acting on the answer: the poll's slow band is
        // fifteen seconds wide when the panel is closed, and this menu is
        // reached with the panel closed.
        store.refreshWork()
        let busy = store.sessions.filter(\.isWorking)
        guard !busy.isEmpty else { return performRestart() }

        let alert = NSAlert()
        alert.messageText = busy.count == 1 ? "A session is still working" : "\(busy.count) sessions are still working"
        alert.informativeText = busy.map(\.title).joined(separator: ", ")
            + "\n\nRestarting loses whatever claude is in the middle of. The conversations themselves come back either way."
        alert.addButton(withTitle: "Wait, Then Restart")
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            restartPending = true
            waitForQuiet(until: Date().addingTimeInterval(300))
        case .alertSecondButtonReturn: performRestart()
        default: break
        }
    }

    /// Poll until every tab has fallen quiet, then go. Capped, so a session
    /// that never settles cannot hold the restart hostage, and abandoned
    /// the moment the wait is called off.
    private func waitForQuiet(until deadline: Date) {
        guard restartPending else { return }
        store.refreshWork()
        guard store.sessions.contains(where: \.isWorking), Date() < deadline else {
            restartPending = false
            return performRestart()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.waitForQuiet(until: deadline)
        }
    }

    private func performRestart() {
        let path = Bundle.main.bundleURL.path
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this copy to actually be gone: the new one bows out if it
        // finds a twin still running, and a fixed sleep is a coin flip.
        let mine = ProcessInfo.processInfo.processIdentifier
        relauncher.arguments = [
            "-c",
            "while kill -0 \(mine) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(path)\"",
        ]
        try? relauncher.run()
        NSApp.terminate(nil)
    }

    private func showPanel(activate: Bool = true) {
        needsAttention = false
        // The summons was answered: an unread "wants you" banner is stale
        // mail once the panel is up, so it leaves Notification Center the
        // way a read message drops its badge.
        AwayNotice.clear()
        cancelPendingHide()
        state.panelOpened()
        faces.greet()
        // On screen: the chips and the scroller are being read again, so the
        // poll goes back to its quick band without waiting out a slow tick.
        scheduleWorkPoll()
        store.ensureSession()
        // The tab on screen is the one being looked at; its pulse has served.
        store.active?.needsAttention = false
        positionPanel()
        let final = panel.frame
        // Drop down from under the menu bar with a touch of overshoot, so it
        // lands like a thing with weight instead of a fading rectangle.
        // Under Reduce Motion the travel goes and only the fade remains.
        let travels = !Motion.reduced
        if travels { panel.setFrame(final.offsetBy(dx: 0, dy: 10), display: false) }
        panel.alphaValue = 0
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        statusItem.button?.highlight(true)
        Haptics.tap()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.panelDrop
            // The overshoot belongs to the travel; a plain fade takes a
            // plain curve.
            context.timingFunction = travels
                ? CAMediaTimingFunction(controlPoints: 0.3, 1.3, 0.5, 1.0)
                : CAMediaTimingFunction(name: .easeOut)
            if travels { panel.animator().setFrame(final, display: true) }
            panel.animator().alphaValue = 1
        }
        installClickMonitor()
        DispatchQueue.main.async { [weak self] in
            guard let self, let session = self.store.active else { return }
            self.panel.makeFirstResponder(session.terminalView)
            // The panel was put away while this tab kept talking, so its last
            // stretch of output was parsed and never painted. Pay it back now
            // that the window is on screen again.
            session.repaintIfOwed()
        }
        // Focus insurance. A panel that is visible but not key swallows every
        // keystroke silently, which reads as a frozen app rather than an
        // unfocused one, the worst possible first impression, and the only
        // symptom reported from the first Mac that wasn't ours (2026-08-03).
        // macOS can refuse an accessory app's activation, so the ask is
        // repeated a couple of times shortly after opening; once the panel is
        // key, this costs nothing and stops.
        guard activate else { return }
        for delay in [0.12, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
                if let view = self.store.active?.terminalView {
                    self.panel.makeFirstResponder(view)
                }
            }
        }
    }

    /// The status item's rect in screen space, for anything that hangs off
    /// the icon.
    private func statusAnchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func positionPanel() {
        // Hang the panel off the status item itself, tucked under the menu bar
        // and never off screen. Anchoring to the screen's right edge instead
        // put the panel far from the icon whenever other menu bar items sat to
        // its right, which is the normal case.
        let button = statusItem.button
        let anchor = button.flatMap { b in b.window?.convertToScreen(b.convert(b.bounds, to: nil)) }
        let mouse = NSEvent.mouseLocation
        let screen = button?.window?.screen
            ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var size = panel.frame.size
        size.height = min(size.height, visible.height - 12)
        size.width = min(size.width, visible.width - 24)
        panel.setContentSize(size)

        // Centered under the icon, then pulled back inside the screen edges.
        let preferred = (anchor?.midX ?? visible.maxX - size.width / 2 - 12) - size.width / 2
        let x = min(max(preferred, visible.minX + 12), visible.maxX - size.width - 12)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: visible.maxY - 6))
    }

    private func hidePanel() {
        cancelPendingHide()
        guard panel.isVisible else { return }
        hiddenAt = Date()
        statusItem.button?.highlight(false)
        Haptics.tap()
        removeClickMonitor()
        // Off screen: drop to the slow band. Everything the panel was being
        // polled for just stopped being visible.
        scheduleWorkPoll()
        // Tuck back up toward the menu bar it came from, quicker than the
        // drop: leaving should feel lighter than arriving.
        let final = panel.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.panelTuck
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !Motion.reduced {
                panel.animator().setFrame(final.offsetBy(dx: 0, dy: 6), display: true)
            }
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.panel.setFrame(final, display: false)
        })
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        // Global monitor only sees clicks in OTHER apps: exactly the
        // click-outside-to-dismiss behavior a dropdown wants.
        // Dismissing on the press was what made dropping a file impossible:
        // grabbing the screenshot thumbnail, or a file in Finder, is a press
        // in another app, so the panel was already gone before the drag
        // began. Nothing closes until the button comes back UP, which is late
        // enough to tell a click apart from a drag.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.store.isPinned else { return }
            if event.type == .rightMouseDown {
                self.hidePanel()
            } else {
                self.isDismissPending = true
                self.watchForMouseUp()
            }
        }
        dragMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                guard let self, self.isDismissPending else { return }
                self.isDragInFlight = true
                self.cancelPendingHide()
            },
        ].compactMap { $0 }
    }

    /// The button going up ends both cases, but a drag swallows its own
    /// mouse-up before any monitor sees it, so the button state is polled
    /// instead of waited on. Whatever the drop landed on, the panel goes back
    /// to behaving normally: gone if the press was outside it, still there if
    /// the file came here (the drop cancels the dismissal on its way in).
    private func watchForMouseUp() {
        guard mouseUpWatcher == nil else { return }
        mouseUpWatcher = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            self.mouseUpWatcher = nil
            self.isDismissPending = false
            self.isDragInFlight = false
            // The file came here, so the panel has earned its place on screen.
            guard !self.didAcceptDrop else {
                self.didAcceptDrop = false
                return
            }
            self.scheduleHide(after: 0.25)
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        dragMonitors.forEach(NSEvent.removeMonitor)
        dragMonitors = []
        mouseUpWatcher?.invalidate()
        mouseUpWatcher = nil
        isDismissPending = false
        isDragInFlight = false
        cancelPendingHide()
    }

    private func scheduleHide(after delay: TimeInterval) {
        guard !store.isPinned else { return }
        cancelPendingHide()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHide = nil
            self?.hidePanel()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    /// A file carried over the menu bar icon opens the panel without stealing
    /// focus, which would cancel the drag out from under him.
    private func springOpenForDrag() {
        isDragInFlight = true
        cancelPendingHide()
        guard !panel.isVisible else { return }
        showPanel(activate: false)
    }

    /// A drop landing on the icon itself, rather than on the terminal.
    private func deliverDrop(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else { return false }
        if !panel.isVisible { showPanel(activate: false) }
        guard let view = store.active?.terminalView as? RinTerminalView else { return false }
        view.sendPaths(paths)
        Haptics.thunk()
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, !store.isPinned else { return }
        if NSApp.keyWindow == nil {
            scheduleHide(after: 0.25)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        // The shrink-wrapped setup size is a costume, not a preference: a
        // resize during first run must not become the remembered size.
        guard SetupState.shared.isComplete else { return }
        AppConfig.defaults.set(Double(panel.frame.width), forKey: "panelW")
        AppConfig.defaults.set(Double(panel.frame.height), forKey: "panelH")
    }

    /// Grow from the setup costume back to the working size, top edge held,
    /// centered where it stands. Reduce Motion snaps instead of animating.
    private func growPanelAfterSetup() {
        let defaults = AppConfig.defaults
        let width = CGFloat(defaults.object(forKey: "panelW") as? Double ?? 760)
        let height = CGFloat(defaults.object(forKey: "panelH") as? Double ?? 500)
        var frame = panel.frame
        frame.origin.x -= (width - frame.width) / 2
        frame.origin.y -= height - frame.height
        frame.size = NSSize(width: width, height: height)
        if let screen = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, screen.minX + 12), screen.maxX - width - 12)
            frame.origin.y = max(frame.origin.y, screen.minY)
        }
        guard panel.isVisible, !Motion.reduced else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.panelDrop
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}
