// one tab and the claude running inside it
// tabs surviving a quit is most of the complicated stuff in here
// a restored tab does not start until you click it otherwise six saved tabs means six claudes booting at login

import AppKit
import QuartzCore
import SwiftTerm
import SwiftUI

extension Notification.Name {
    /// Posted when a session wants Peter's eyes: terminal bell, or death.
    static let rinNeedsAttention = Notification.Name("RinNeedsAttention")
    /// Posted when a session gets a new child, so its pid can be written down.
    static let rinSessionSpawned = Notification.Name("RinSessionSpawned")
    /// Posted when a drop lands, so the panel knows not to close behind it.
    static let rinDidAcceptDrop = Notification.Name("RinDidAcceptDrop")
    /// Posted when a tab that was never a conversation finishes, so the store
    /// can take it off the bar instead of leaving a dead chip behind.
    static let rinEphemeralEnded = Notification.Name("RinEphemeralEnded")
}

/// Terminal view that surfaces the bell instead of swallowing it, and makes
/// the scroll wheel work inside full-screen apps like claude.
final class RinTerminalView: LocalProcessTerminalView {
    /// How far the content sits off the line grid, zero up to one row.
    private var subLine: CGFloat = 0
    /// The same, for the notches a full-screen program gets instead.
    private var pageBank: CGFloat = 0
    /// Points a notched wheel still owes the view, paid out over frames.
    private var glideOwed: CGFloat = 0
    private var glideLink: CADisplayLink?
    /// This gesture already touched a wall of the scrollback. One alignment
    /// tap per gesture, ever: a wall that buzzed on every pixel of a held
    /// swipe would be a rattle, and the point is the first contact, where
    /// the finger learns the geometry the eye already knows.
    private var wallFelt = false
    /// When the last scroll arrived, so a notched wheel (which has no
    /// gesture phases at all) still gets a fresh wall after a pause.
    private var lastScrollAt = Date.distantPast

    public override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    override func bell(source: Terminal) {
        // No super: its chain plays the system beep. The bell is felt, not
        // heard, unless the menu's sound toggle is on. Silence is the
        // default so a session can never go off in the middle of class.
        NotificationCenter.default.post(name: .rinNeedsAttention, object: self)
        // A summons is for somebody not looking. When this tab is front in a
        // visible panel the bell is already on screen in claude's own words,
        // and drumming the trackpad under a hand that is mid-gesture says
        // "come here" to someone who is here. Hidden tab or tucked panel
        // still gets the full pattern, which is the whole point of it.
        if !hasSomewhereToDraw { Haptics.alert() }
        guard AlertSound.isEnabled else { return }
        NSSound(named: AlertSound.bellSound)?.play()
    }

    /// Whether a TUI (claude) owns the screen, leaving no scrollback.
    var isShowingTUI: Bool {
        getTerminal().isCurrentBufferAlternate
    }

    // MARK: - Drawing only where there is somewhere to draw
    //
    // A tab that is not the front tab has no view in the panel, and a panel
    // dropped back into the menu bar has no window on screen. Either way the
    // terminal underneath keeps taking output, and the library answers every
    // arriving byte the same way: schedule a display pass on the next frame,
    // move the caret, rebuild the caret's glyph, tell accessibility the value
    // changed, mark a region stale. None of it reaches a pixel, because AppKit
    // will not draw a view with no window, so the work is done and thrown
    // away, sixty times a second, for as long as claude streams an answer into
    // a tab nobody is looking at. That was the suspicion in the punch list on
    // 2026-08-03, and reading the library's own update path is what confirmed
    // it: the throttle is on the frame, not on whether the frame is worth
    // drawing.
    //
    // The parse stays exactly where it was. The buffer has to be right whether
    // or not anyone is watching, and the two things this app reads out of a
    // hidden tab both come out of the parse rather than the painting: the
    // title, which the chip wears, and the bell, which lights the pulse. Only
    // the painting half is skipped, and everything skipped is repainted in
    // full the moment the tab has somewhere to show it.

    /// Whether anything drawn right now could actually be seen. A view with no
    /// window is a background tab; a window that is not visible is the panel
    /// put away.
    private var hasSomewhereToDraw: Bool {
        window?.isVisible ?? false
    }

    /// Output arrived while the answer above was no, so what is on screen is
    /// behind the buffer and a repaint is owed.
    private var owesRepaint = false

    /// Output from the child. The superclass parses it and then schedules a
    /// paint; when there is nothing to paint onto, this does the first half
    /// only. Delivery is on the main queue, so reading `window` here is safe.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        guard !hasSomewhereToDraw else {
            super.dataReceived(slice: slice)
            return
        }
        getTerminal().feed(buffer: slice)
        owesRepaint = true
    }

    /// Pay off the drawing that was skipped. The whole screen is marked stale
    /// rather than the accumulated range, because a range that grew while the
    /// tab was hidden can span more scrollback than the view has rows. Feeding
    /// nothing is what runs the library's own display pass, caret included,
    /// without reaching around it into anything it does not publish.
    func repaintIfOwed() {
        guard owesRepaint, hasSomewhereToDraw else { return }
        owesRepaint = false
        getTerminal().updateFullScreen()
        feed(byteArray: ArraySlice<UInt8>())
    }

    // MARK: - Scrolling
    //
    // The Mac hands scrolling out in pixels and keeps sending it after the
    // fingers lift, which is where the glide in every other app comes from.
    // The terminal underneath can only stand on whole lines, so on its own it
    // hops a line at a time and reads as a ratchet next to any other window.
    //
    // The leftover pixels are carried by the view's own coordinate space.
    // Sliding the origin up by part of a row makes the draw code lay down one
    // extra row at the edge and shift the whole page by exactly that much, so
    // the text moves continuously and the terminal never knows.

    /// One line, measured off the caret, which is exactly one cell tall.
    /// Dividing the panel height by the row count would be off by whatever
    /// remainder is left over, and this has to match the drawing to the pixel
    /// or every line boundary twitches as it goes past.
    private var rowHeight: CGFloat {
        let caret = caretFrame.height
        if caret >= 1 { return caret }
        let rows = CGFloat(getTerminal().rows)
        guard rows > 0, bounds.height > 0 else { return 16 }
        return bounds.height / rows
    }

    /// System Reduce Motion: scrolling still works, it just stops easing.
    private var stillness: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Finger travel per page key, for the programs that only take keys.
    /// Half a panel, so the screen runs about twice the speed of the hand: a
    /// page key is a blunt instrument, and asking for a full panel of travel
    /// per press turns scrolling back through a long file into work.
    private var pageStep: CGFloat { max(90, bounds.height * 0.5) }

    /// Every scroll over the terminal lands here. False means nothing was
    /// done with it, so the event can travel on.
    func handleScroll(_ event: NSEvent) -> Bool {
        // A new gesture owns the view: whatever the last one was still
        // coasting through gets dropped rather than fought with.
        if event.phase == .began || event.momentumPhase == .began { stopGlide() }
        // A fresh finger-down earns a fresh wall; momentum belongs to the
        // same gesture and does not. Wheels have no phases, so a pause is
        // what separates their gestures.
        if event.phase == .began || Date().timeIntervalSince(lastScrollAt) > 0.6 {
            wallFelt = false
        }
        lastScrollAt = Date()
        let raw = event.scrollingDeltaY
        guard raw != 0 else { return false }
        // A trackpad reports points. A notched wheel reports lines, and one
        // notch is worth three of them, same as everywhere else on the Mac.
        let points = event.hasPreciseScrollingDeltas ? raw : raw * rowHeight * 3
        syncScroller()

        if isShowingTUI {
            // A full-screen program owns the screen: there is no scrollback
            // under it to move, so there is nothing to offset either.
            setSubLine(0)
            spendOnTUI(points, at: event)
        } else if event.hasPreciseScrollingDeltas || stillness {
            spendOnPixels(points)
        } else {
            glide(by: points)
        }
        return true
    }

    /// Positive points scroll back into history. Whole rows go to the
    /// terminal, the remainder to the offset, and the two are read as one
    /// position so a slow drag crosses a line boundary without a hitch.
    private func spendOnPixels(_ points: CGFloat) {
        let height = rowHeight
        guard height > 0 else { return }
        let total = subLine - points
        let step = (total / height).rounded(.down)
        var rest = total - step * height

        if step < 0 {
            scrollUp(lines: Int(-step))
        } else if step > 0 {
            scrollDown(lines: Int(step))
        }
        // Both ends are hard stops. Sliding past the oldest line, or off the
        // live one at the bottom, would show a strip of nothing. First
        // contact with either stop is FELT, once per gesture: the walls used
        // to be silent, and an alignment tap is exactly what the haptic
        // grammar's first word is for. Only when there is scrollback to have
        // walls; a fresh tab is a room, not a corridor.
        let position = scrollPosition
        if (points > 0 && position <= 0) || (points < 0 && position >= 1) {
            rest = 0
            if !wallFelt, canScroll {
                wallFelt = true
                Haptics.tap()
            }
        }
        setSubLine(rest, redraw: step != 0)
    }

    /// The line grid is authoritative again. Anything that throws the view
    /// back to the live end, a keystroke most of all, lands on it square.
    func clearSubLine() {
        setSubLine(0)
    }

    private func setSubLine(_ value: CGFloat, redraw: Bool = false) {
        var dirty = redraw
        if abs(value - subLine) > 0.01 {
            subLine = value
            // The draw code reads its row range off the bounds, so moving the
            // origin is what buys the extra row at the edge. A layer shift
            // would slide what was already drawn and leave a gap instead.
            setBoundsOrigin(NSPoint(x: 0, y: -value))
            dirty = true
        }
        if dirty { setNeedsDisplay(bounds) }
    }

    /// A full-screen program gets what a real terminal would send it.
    ///
    /// Claude turns mouse reporting on and scrolls its own transcript off
    /// wheel events; it ignores PgUp and PgDn completely, which is why
    /// scrolling in a claude tab used to go nowhere. So travel is spent one
    /// wheel notch per row, exactly the way Terminal.app spends it, and the
    /// program decides how far a notch goes. Page keys stay as the fallback
    /// for full-screen programs that never asked for the mouse.
    private func spendOnTUI(_ points: CGFloat, at event: NSEvent) {
        let wheeled = getTerminal().mouseMode != .off
        let step = wheeled ? rowHeight : pageStep
        guard step > 0 else { return }
        let spot = wheeled ? cell(under: event) : (col: 1, row: 1)
        pageBank += points
        // A single flick can be worth a lot of notches. Cap what one event is
        // allowed to spend so a hard swipe cannot flood the program.
        var sent = 0
        while abs(pageBank) >= step, sent < 24 {
            let up = pageBank > 0
            pageBank += up ? -step : step
            sent += 1
            if wheeled {
                send(txt: "\u{1b}[<\(up ? 64 : 65);\(spot.col);\(spot.row)M")
            } else {
                send(txt: up ? "\u{1b}[5~" : "\u{1b}[6~")
            }
        }
        if sent >= 24 { pageBank = 0 }
    }

    /// SwiftTerm keeps its scroller to itself, but it is a subview, and it is
    /// the only bar in here.
    private var scroller: NSScroller? {
        subviews.compactMap { $0 as? NSScroller }.first
    }

    /// A full-screen program has no scrollback underneath it, so SwiftTerm
    /// disables the bar and leaves it sitting there looking broken: it cannot
    /// track claude, because claude keeps its own transcript and the terminal
    /// never sees it. So the bar goes away while claude owns the screen and
    /// comes back for the shell, where it means something again. Costs no
    /// width either way; that gutter is reserved whether the bar is drawn or
    /// not.
    func syncScroller() {
        guard let scroller, scroller.isHidden != isShowingTUI else { return }
        scroller.isHidden = isShowingTUI
    }

    /// The cell the pointer sits over, one-based, the way mouse reports count.
    private func cell(under event: NSEvent) -> (col: Int, row: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let width = max(1, caretFrame.width)
        let height = max(1, rowHeight)
        let terminal = getTerminal()
        let col = min(max(Int(point.x / width) + 1, 1), terminal.cols)
        let row = min(max(Int((bounds.maxY - point.y) / height) + 1, 1), terminal.rows)
        return (col, row)
    }

    /// A notched wheel arrives as one lump with no momentum behind it, so the
    /// lump is paid out across frames on an ease-out curve. Same trick a web
    /// page does, and it is the whole difference between text that jumps and
    /// text that moves.
    private func glide(by points: CGFloat) {
        glideOwed += points
        guard glideLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(payGlide))
        link.add(to: .main, forMode: .common)
        glideLink = link
    }

    @objc private func payGlide() {
        let step = glideOwed * 0.28
        guard abs(glideOwed) >= 0.5 else {
            let rest = glideOwed
            stopGlide()
            spendOnPixels(rest)
            return
        }
        glideOwed -= step
        spendOnPixels(step)
    }

    private func stopGlide() {
        glideLink?.invalidate()
        glideLink = nil
        glideOwed = 0
    }

    /// A tab that leaves the panel takes its animation with it, so a closed
    /// session cannot leave a timer running against a view nobody can see.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopGlide()
            clearSubLine()
        } else {
            // Came forward as the front tab. Anything that streamed in while
            // it was behind has not been painted yet.
            repaintIfOwed()
        }
    }

    /// A resize re-lays the grid under the offset, so the offset goes.
    override func setFrameSize(_ newSize: NSSize) {
        clearSubLine()
        super.setFrameSize(newSize)
    }

    deinit {
        glideLink?.invalidate()
    }

    // MARK: - Files in

    /// SwiftTerm registers no dragged types and pastes strings only, so a
    /// screenshot had no way in at all: dropping did nothing, and cmd-V of a
    /// file copied in Finder handed claude the file's ICON instead of the
    /// file. Both roads now end at a real path typed into the prompt, which
    /// is what claude reads images from.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pathsOnPasteboard(sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = pathsOnPasteboard(sender.draggingPasteboard)
        guard !paths.isEmpty else { return false }
        sendPaths(paths)
        // A drop is a commit, so it gets the knock; a paste keeps the tick.
        Haptics.thunk()
        return true
    }

    override func paste(_ sender: Any) {
        // A copied file wins outright: Finder puts the bare filename on the
        // clipboard as text too, and pasting that hands claude a name with no
        // path. Real text still pastes exactly as it always did, and a raw
        // screenshot is the last resort.
        let board = NSPasteboard.general
        if let files = fileURLPaths(board) {
            sendPaths(files)
            Haptics.tap()
        } else if board.string(forType: .string) != nil {
            super.paste(sender)
        } else if let image = imagePath(board) {
            sendPaths([image])
            Haptics.tap()
        }
    }

    /// Callers own the feel: a drop knocks, a paste ticks.
    func sendPaths(_ paths: [String]) {
        // Backslash-escaped, the way dropping onto Terminal.app writes them.
        let escaped = paths.map { $0.replacingOccurrences(of: " ", with: "\\ ") }
        send(txt: escaped.joined(separator: " ") + " ")
        NotificationCenter.default.post(name: .rinDidAcceptDrop, object: self)
    }

    /// Paths a pasteboard can offer, real files first and image data second.
    func pathsOnPasteboard(_ pasteboard: NSPasteboard) -> [String] {
        if let files = fileURLPaths(pasteboard) { return files }
        return imagePath(pasteboard).map { [$0] } ?? []
    }

    private func fileURLPaths(_ pasteboard: NSPasteboard) -> [String]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.map(stabilized)
    }

    /// The screenshot thumbnail in the corner hands over a file inside the
    /// screencapture helper's own scratch folder, which is emptied the moment
    /// the thumbnail is dismissed or saved. Claude reads the path later, not
    /// at the drop, so it would be reading a file that no longer exists.
    /// Anything from a scratch folder gets its own copy first.
    private func stabilized(_ url: URL) -> String {
        guard url.path.contains("/TemporaryItems/") else { return url.path }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("rin-drop-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)")
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return url.path }
        return copy.path
    }

    /// A screenshot sitting on the clipboard as raw pixels, written out so it
    /// has a path to hand over.
    private func imagePath(_ pasteboard: NSPasteboard) -> String? {
        guard let data = pasteboard.data(forType: .png) ?? tiffAsPNG(pasteboard) else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rin-paste-\(UUID().uuidString.prefix(8)).png")
        guard (try? data.write(to: file)) != nil else { return nil }
        return file.path
    }

    private func tiffAsPNG(_ pasteboard: NSPasteboard) -> Data? {
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// One running claude session with its own embedded terminal.
/// The view lives here, not in SwiftUI, so the process survives the
/// dropdown closing and tab switches.
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    /// Doubles as claude's session id, so a tab resumes its own
    /// conversation when the app comes back up.
    let id: UUID
    let number: Int
    @Published var title: String
    /// A name Peter typed himself. It outranks whatever the terminal last
    /// set, survives restarts with the tab list, and clearing it hands the
    /// title back to the terminal. The terminal's own title keeps updating
    /// underneath, so nothing is lost by naming a tab and nothing has to be
    /// re-earned by un-naming it.
    @Published var customLabel: String?
    /// What the chip wears: his name for the tab if he gave one, else
    /// whatever the session last called itself.
    var displayTitle: String { customLabel ?? title }
    @Published var isRunning = true
    /// Restored, but never looked at, so nothing has been launched behind it.
    @Published private(set) var isDormant = false
    /// This session rang its bell (or died) while Peter was looking elsewhere.
    /// Shown as a pulse on the tab chip; cleared the moment he looks.
    @Published var needsAttention = false
    let terminalView: LocalProcessTerminalView

    /// Whether closing this tab is free. Ended tabs and cards close on a
    /// plain click: nothing sits behind either, and a card is a page wearing
    /// a tab. A DORMANT tab is not free (Peter's call, 2026-08-08): it is a
    /// saved conversation holding its seat on the bar, and one stray click
    /// silently costing it that seat felt like loss even though Reopen
    /// Conversation can bring it back. A guard beats a recovery, so dormant
    /// tabs take the same held ring as live ones.
    var isIdle: Bool { !isRunning || isEphemeral }

    /// Claude is mid-task in this tab: its conversation was written to
    /// moments ago. Ten seconds rather than the helper's five, because turns
    /// land a piece at a time and a long tool call writes nothing while it
    /// runs; five made the light flicker on work that had not stopped.
    ///
    /// Published rather than computed (2026-08-04). Reading it touched the
    /// disk, so the bar had to keep asking on a timer of its own, one per
    /// chip, every two seconds, rebuilding chips that had not changed. The
    /// app's poll already runs on that beat and already has to ask; now it
    /// asks once and tells, and a chip redraws when the answer moves.
    @Published private(set) var isWorking = false

    /// Re-read the working light. One stat, cheap enough for every tick, and
    /// only a real change is published.
    func refreshWork() {
        let now = isRunning && !isDormant && AppConfig.isWorking(sessionID: id, within: 10)
        if now != isWorking { isWorking = now }
    }

    /// Remote Control is live in this tab: claude is holding a bridge open, so
    /// the session can be read and driven from Peter's phone. Read and kept
    /// current, but nothing in the bar says it yet: the signal was parked
    /// 2026-07-28 until it has a shape that does not fight the tab colours.
    @Published private(set) var isRemote = false

    /// The launch itself failed: this tab died on startup, spent its one
    /// retry on the other flag, and died again. Waiting will not fix it, which
    /// is why it is the loudest thing the bar can say.
    @Published private(set) var didFailLaunch = false

    /// The vault's private mode has claimed this tab: its conversation is
    /// purged from disk the moment the session ends, so the chip wears the
    /// one colour that means "this will not survive". The claim drops by
    /// itself when the session ends cleanly, because ending is what clears
    /// it from the privacy tool's ledger.
    @Published private(set) var isPrivate = false

    /// Read on the app's slow poll. Only a real change is published, so a lit
    /// tab is not a redraw every two seconds.
    func refresh(remote: Set<UUID>, tainted: Set<UUID>) {
        let live = isRunning && !isDormant && remote.contains(id)
        if live != isRemote { isRemote = live }
        // Gated exactly like the remote light, dormancy included, so purple
        // and green are one system: a standing hue on a live session, the
        // beat carrying work and attention, the grey ring owning dormant.
        let claimed = isRunning && !isDormant && tainted.contains(id)
        if claimed != isPrivate { isPrivate = claimed }
    }

    /// A nudge's opening line, consumed by the first launch and never by a
    /// restart, replaying the nudge on a relaunch would nag twice.
    private var initialPrompt: String?

    /// Which card this tab is, if it is one at all. A card is a tab that was
    /// never a conversation: it runs its own command, never resumes anything,
    /// never joins the saved tab list, and leaves the bar when its command
    /// exits. Peter's standing call (2026-08-04) is that a screen needing room
    /// becomes a TAB rather than a window or a panel view, so this is the shape
    /// every future one takes.
    ///
    /// It holds a NAME rather than a yes-or-no because there are two of them
    /// now (the shortcuts card, 2026-08-08). "Is a card already open" was the
    /// question that kept a second about tab from stacking; with two kinds
    /// that question has to become "is THIS card open", or asking for one
    /// silently jumps to whichever was opened first.
    let card: String?
    var isEphemeral: Bool { card != nil }
    private let commandOverride: String?

    init(
        number: Int,
        id: UUID = UUID(),
        autoStart: Bool = true,
        prompt: String? = nil,
        command: String? = nil,
        label: String? = nil,
        card: String? = nil
    ) {
        self.id = id
        self.number = number
        self.initialPrompt = prompt
        self.commandOverride = command
        self.card = card
        self.title = label ?? "rin \(number)"
        self.terminalView = RinTerminalView(frame: NSRect(x: 0, y: 0, width: 740, height: 420))
        super.init()
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: AppConfig.fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = TerminalTheme.background
        terminalView.nativeForegroundColor = TerminalTheme.foreground
        // The sixteen ANSI slots claude draws its whole interface in. Left
        // alone, SwiftTerm hands over the Tango defaults, which are mixed for
        // a different background and land under readable contrast on this one.
        terminalView.installColors(TerminalTheme.palette)
        terminalView.caretColor = TerminalTheme.caret
        terminalView.caretTextColor = TerminalTheme.background
        terminalView.selectedTextBackgroundColor = TerminalTheme.selection
        if autoStart {
            start()
        } else {
            isDormant = true
        }
    }

    /// Launch a tab that was restored but never opened. Six saved tabs used
    /// to mean six claude sessions booting the instant the app came up, which
    /// on a login launch is a stampede for conversations Peter may not open
    /// at all. A tab now costs nothing until it is looked at.
    func wake() {
        guard isDormant else { return }
        isDormant = false
        start()
    }

    /// The panel came back on screen. A tab coming forward repaints itself as
    /// it joins the view, but a panel returning moves no views at all, so the
    /// front tab has to be told that its window is worth drawing into again.
    func repaintIfOwed() {
        (terminalView as? RinTerminalView)?.repaintIfOwed()
    }

    private var childWatcher: DispatchSourceProcess?
    /// Which flag this launch used and when, so a death seconds after
    /// starting can be told apart from Peter closing the session himself.
    private var launchedAt = Date.distantPast
    private var didResume = false
    private var didRetryLaunch = false

    private func start(resume: Bool? = nil) {
        // posix_spawn inherits the app's cwd; every session uses the same dir
        FileManager.default.changeCurrentDirectoryPath(AppConfig.workingDirectory)
        let useResume = resume ?? AppConfig.hasTranscript(for: id)
        didResume = useResume
        launchedAt = Date()
        let prompt = initialPrompt
        initialPrompt = nil
        // The tab's own id rides in the environment so the first-run script
        // can hand it to the claude it execs into, keeping that conversation
        // resumable like any other tab's.
        let command = commandOverride ?? AppConfig.command(for: id, resume: useResume, prompt: prompt)
        var environment = AppConfig.environment() + ["RIN_SESSION_ID=\(id.uuidString.lowercased())"]
        if isEphemeral {
            // What the about card prints. Handed in rather than read by the
            // script, so the numbers on screen are the running app's own and
            // not whatever happens to be installed somewhere else.
            environment += [
                "RIN_VERSION=\(AppConfig.appVersion)",
                "RIN_BUILD=\(AppConfig.appBuild)",
                "RIN_BRAIN=\(AppConfig.isConfigured ? AppConfig.workingDirectory : "")",
            ]
        }
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-l", "-c", command],
            environment: environment,
            execName: nil
        )
        watchChild()
        NotificationCenter.default.post(name: .rinSessionSpawned, object: self)
    }

    /// SwiftTerm 1.11's own child monitor installs its handler after
    /// activating and never fires for us, so the exit is watched here:
    /// handler first, then activate, and the zombie gets reaped.
    private func watchChild() {
        childWatcher?.cancel()
        childWatcher = nil
        guard let pid = terminalView.process?.shellPid, pid > 0 else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            guard let self else { return }
            self.childWatcher?.cancel()
            self.childWatcher = nil
            self.markEnded(pid: pid)
        }
        source.activate()
        childWatcher = source
    }

    /// A death lands here twice, once from the watcher and once from
    /// SwiftTerm's delegate, and after a relaunch the second one is about a
    /// process this tab no longer has. Reports carry the pid that died so a
    /// stale one cannot kill the tab that replaced it.
    private func markEnded(pid: pid_t?) {
        guard isRunning else { return }
        if let pid, let current = terminalView.process?.shellPid, pid != current { return }
        // A card closing is not a session dying. No retry, no attention pulse,
        // no amber chip left on the bar: it did its one job and the tab goes.
        if isEphemeral {
            isRunning = false
            isWorking = false
            NotificationCenter.default.post(name: .rinEphemeralEnded, object: self)
            return
        }
        // A session that dies within a breath of starting did not end, it was
        // REFUSED. Claude resumes only conversations in the folder it derives
        // from the working directory, and refuses a --session-id that folder
        // already holds; both answers flip the day claude renames the folder,
        // which is what killed every restored tab on 2026-07-27. Trying the
        // other flag once turns a dead tab into a working one, at worst a
        // fresh conversation under the same id instead of a resumed one.
        if !didRetryLaunch, Date().timeIntervalSince(launchedAt) < 5 {
            didRetryLaunch = true
            NSLog("rin: session died on launch, retrying with \(didResume ? "--session-id" : "--resume")")
            // A refused launch is exactly when claude may have moved its
            // folder, so the retry asks the disk again instead of trusting
            // the answer that just failed.
            AppConfig.forgetTranscriptDirectory()
            start(resume: !didResume)
            return
        }
        // Both flags tried, both refused within a breath: the tab cannot start
        // at all, which is a different problem from a session that ran and
        // ended, and it gets the loudest colour rather than the quiet one.
        if didRetryLaunch, Date().timeIntervalSince(launchedAt) < 5 {
            didFailLaunch = true
        }
        isRunning = false
        isWorking = false
        title = "ended"
        NotificationCenter.default.post(name: .rinNeedsAttention, object: self)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            self.title = title.isEmpty ? "rin \(self.number)" : title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Read the pid now, while the dead process is still the one on file:
        // by the time this reaches the main queue the tab may have relaunched.
        let pid = terminalView.process?.shellPid
        DispatchQueue.main.async { self.markEnded(pid: pid) }
    }

    /// The live claude for this tab, if it still has one.
    var childPID: pid_t? {
        guard isRunning, let pid = terminalView.process?.shellPid, pid > 0 else { return nil }
        return pid
    }

    /// End the child so it cannot outlive its tab. An orphaned claude keeps
    /// writing to the same transcript the next launch wants to resume.
    /// Cancelling the watcher leaves nobody to wait on the pid, so the wait
    /// happens here: a closed tab used to leave a zombie for the life of the
    /// app. A child that will not take the hangup gets killed outright.
    func shutdown() {
        childWatcher?.cancel()
        childWatcher = nil
        guard let pid = terminalView.process?.shellPid, pid > 0 else { return }
        isRunning = false
        kill(pid, SIGHUP)
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            for _ in 0..<30 {
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }
    }

    /// Relaunch claude in the same tab after the process ends. A restart by
    /// hand earns its own retry, so a tab that was refused once can still be
    /// rescued later, when the folder underneath it has settled.
    func restart() {
        guard !isRunning else { return }
        isRunning = true
        title = "rin \(number)"
        didRetryLaunch = false
        start()
        Haptics.thunk()
    }
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    /// Selecting a tab is what starts it: a restored tab launches the first
    /// time it is looked at, and never before.
    @Published var activeID: UUID? {
        didSet {
            active?.wake()
            active?.needsAttention = false
            save()
        }
    }
    /// Pinned = the panel stays up when focus moves to another app.
    @Published var isPinned = false
    /// The find bar is on screen. Lives here so the menu key, the bar
    /// itself, and anything else that wants to close it flip one switch.
    @Published var isSearching = false
    /// Bumped on every Cmd-F, so a press with the bar already up hands the
    /// field back instead of doing nothing.
    @Published var searchNonce = 0
    /// The quick switcher overlay is on screen (Cmd-K).
    @Published var isSwitching = false
    /// Tabs that have LANDED, ever. Arrival effects key off this rather than
    /// the session count, because the count also falls when a tab closes and
    /// a plus that bounces for a departure is announcing the wrong event.
    @Published private(set) var arrivals = 0
    /// The last conversation filed into the brain, as a line the panel can
    /// show for a moment ("filed to 00-inbox/…"). Cleared by the toast.
    /// Carries a nonce so the same words twice running still re-show: a
    /// second refusal that cannot be seen is a click that read as ignored.
    struct Toast: Equatable {
        let text: String
        let nonce: Int
    }
    @Published var filedNote: Toast?
    private var toastNonce = 0

    /// Say one line over the terminal, replacing whatever line was up.
    private func toast(_ text: String) {
        toastNonce += 1
        filedNote = Toast(text: text, nonce: toastNonce)
    }
    /// Wired by the app delegate; the store cannot see the panel itself.
    var isPanelVisible: () -> Bool = { false }
    private var counter = 0
    private static let tabsKey = "savedTabs"
    private static let activeKey = "savedActiveTab"

    private var spawnObserver: Any?
    private var attentionObserver: Any?
    private var ephemeralObserver: Any?

    init() {
        // Restarting a dead tab gives it a new child; the saved pid has to
        // follow or the orphan sweep next launch aims at nothing.
        spawnObserver = NotificationCenter.default.addObserver(
            forName: .rinSessionSpawned, object: nil, queue: .main
        ) { [weak self] _ in
            self?.save()
        }
        // A card that finished takes its own tab off the bar.
        ephemeralObserver = NotificationCenter.default.addObserver(
            forName: .rinEphemeralEnded, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let session = note.object as? TerminalSession else { return }
            self.close(session)
        }
        // The bell posts the terminal view; a death posts the session. Either
        // way the chip lights up, unless Peter is already looking at that tab.
        attentionObserver = NotificationCenter.default.addObserver(
            forName: .rinNeedsAttention, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let session = self.sessions.first(where: {
                      $0 === note.object as? TerminalSession || $0.terminalView === note.object as? NSView
                  })
            else { return }
            if session.id == self.activeID, self.isPanelVisible() { return }
            session.needsAttention = true
        }
    }

    var active: TerminalSession? { sessions.first { $0.id == activeID } }

    /// Re-read every tab's working light. Called by the app's poll, and by
    /// anything about to ACT on the answer, a restart asking whether it is
    /// interrupting is asking about right now, and the poll's slow band runs
    /// as far apart as fifteen seconds when the panel is closed.
    func refreshWork() {
        sessions.forEach { $0.refreshWork() }
    }

    func ensureSession() {
        if sessions.isEmpty { newSession() }
    }

    func newSession() { newSession(prompt: nil) }

    /// A new tab that opens already carrying a nudge's line as its first
    /// prompt, so the session speaks it instead of waiting to be spoken to.
    func newSession(prompt: String?) {
        counter += 1
        arrivals += 1
        let session = TerminalSession(number: counter, prompt: prompt)
        sessions.append(session)
        activeID = session.id
        save()
        Haptics.thunk()
    }

    /// The about card, as a tab. A second press jumps to the one already open
    /// rather than stacking cards, the same way it behaves for a conversation.
    func openAbout() {
        openCard("about", script: AppConfig.aboutScript)
    }

    /// Every key this app answers to, as a tab (2026-08-08). The app had grown
    /// nine bindings and listed none of them anywhere a person could read:
    /// Cmd-1 through Cmd-9 in particular existed only in the source. A card is
    /// what the standing call asks for, and it costs a script and a menu row
    /// rather than a settings window.
    func openShortcuts() {
        openCard("shortcuts", script: AppConfig.shortcutsScript)
    }

    /// One card open at a time PER KIND. Asking for one already on the bar
    /// jumps to it instead of stacking a second, the same way a conversation
    /// behaves, and asking for the other opens the other.
    private func openCard(_ name: String, script: String?, activate: Bool = true) {
        if let existing = sessions.first(where: { $0.card == name }) {
            guard activate else { return }
            activeID = existing.id
            Haptics.tap()
            return
        }
        guard let script else { return }
        counter += 1
        arrivals += 1
        let session = TerminalSession(
            number: counter,
            command: "exec /bin/zsh \"\(script)\"",
            label: name,
            card: name
        )
        sessions.append(session)
        // The tour lands on the bar without stealing the tab he is in: right
        // after setup that tab is the setup conversation itself, and a card
        // yanking focus mid-login would be the tour costing more than it
        // teaches.
        if activate { activeID = session.id }
        Haptics.thunk()
    }

    /// Reopen a conversation that exists on disk, including one this app
    /// never opened, or jump to its tab if it is already up.
    func openSession(id: UUID) {
        if sessions.contains(where: { $0.id == id }) {
            activeID = id
            Haptics.tap()
            return
        }
        counter += 1
        arrivals += 1
        sessions.append(TerminalSession(number: counter, id: id))
        activeID = id
        save()
        Haptics.thunk()
    }

    /// A name he typed wins until he clears it; nil or empty hands the title
    /// back to the terminal. Persisted with the tab list either way.
    func rename(_ session: TerminalSession, to label: String?) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customLabel = (trimmed?.isEmpty ?? true) ? nil : trimmed
        save()
        Haptics.tap()
    }

    /// A chip dragged over another takes its place. Cmd-1 through 9 follow
    /// position on purpose: the number is an address on the bar, not a name,
    /// and reordering is the whole point of being able to renumber without
    /// closing and reopening. Answers whether anything actually moved, so
    /// the caller can put the felt tick on real swaps only.
    @discardableResult
    func move(_ id: UUID, to targetID: UUID) -> Bool {
        guard id != targetID,
              let from = sessions.firstIndex(where: { $0.id == id }),
              let to = sessions.firstIndex(where: { $0.id == targetID })
        else { return false }
        let session = sessions.remove(at: from)
        sessions.insert(session, at: to)
        save()
        return true
    }

    /// Turn a tab's conversation into a note in the brain's inbox. The one
    /// feature no competitor has a reason to build: the transcript is already
    /// on disk and the brain is already the working directory, so filing is
    /// a parse and a write, not an integration.
    func fileToBrain(_ session: TerminalSession) {
        guard let relative = Filing.fileConversation(for: session) else {
            toast("nothing to file yet")
            Haptics.deny()
            return
        }
        toast("filed to \(relative)")
        Haptics.thunk()
    }

    /// The card behind the red bead: what a launch failure means and what to
    /// try, in words a stranger can use. The loudest colour on the bar
    /// finally explains itself.
    func openLaunchHelp() {
        openCard("help", script: AppConfig.helpScript)
    }

    /// The welcome tour, third card. Auto-opened once after first run
    /// (without stealing the setup conversation's focus) and reachable from
    /// the menus forever after.
    func openTour(activate: Bool = true) {
        openCard("tour", script: AppConfig.tourScript, activate: activate)
    }

    func close(_ session: TerminalSession) {
        let closedIndex = sessions.firstIndex { $0.id == session.id }
        session.shutdown()
        sessions.removeAll { $0.id == session.id }
        // The felt grammar's second definition, gone-now, said HERE so every
        // close speaks it once: the held x, the plain click on an ended tab,
        // Cmd-W, the context menu. It used to ride only the hold's firing,
        // which left the other three closes silent.
        Haptics.thunk()
        if activeID == session.id {
            // Focus lands on the NEIGHBOUR, which is what every tabbed Mac
            // app does: closing the second of five leaves you on what was
            // the third, not thrown to the far end of the bar. Handing it to
            // the last tab (as this did until 2026-08-03) means closing a
            // tab in the middle silently moves you somewhere you were not.
            if let closedIndex, !sessions.isEmpty {
                activeID = sessions[min(closedIndex, sessions.count - 1)].id
            } else {
                activeID = sessions.last?.id
            }
        }
        save()
    }

    /// Tabs whose session has ended.
    var deadSessions: [TerminalSession] { sessions.filter { !$0.isRunning } }

    /// Clear every ended tab in one go. A tab only leaves the saved list by
    /// being closed, so one that comes back dead comes back dead on every
    /// launch until it does, and closing them one at a time was the only way
    /// out of that. Live tabs are untouched.
    func closeDead() {
        let doomed = Set(deadSessions.map(\.id))
        guard !doomed.isEmpty else { return }
        sessions.filter { doomed.contains($0.id) }.forEach { $0.shutdown() }
        sessions.removeAll { doomed.contains($0.id) }
        if let active = activeID, doomed.contains(active) { activeID = sessions.last?.id }
        save()
        Haptics.thunk()
    }

    /// The curfew (Peter's rule, 2026-08-01): a private tab lives only until
    /// the day it opened ends. Ending the session is the whole mechanism,
    /// that is what seals the private section and purges the conversation,
    /// so all this does is hang up and take the chip off the bar. Nothing
    /// here touches disk; the vault's own hook does the deleting.
    func reapPrivateTabs() {
        let tainted = AppConfig.taintedSessions()
        let doomed = Set(sessions.filter { tainted.contains($0.id) }.map(\.id))
        guard !doomed.isEmpty else { return }
        sessions.filter { doomed.contains($0.id) }.forEach { $0.shutdown() }
        sessions.removeAll { doomed.contains($0.id) }
        if let active = activeID, doomed.contains(active) { activeID = sessions.last?.id }
        save()
        ensureSession()
        // No felt word, on purpose: the curfew fires from the midnight tick
        // with nobody's hand on anything, and the grammar allows exactly one
        // unprompted word, the alert. A reap is housekeeping, not a summons.
    }

    /// Reopen last run's tabs, each resuming its own conversation. The
    /// terminal itself is gone, so what comes back is the transcript claude
    /// redraws, not the old scrollback. One fresh tab if there was nothing.
    ///
    /// Only the tab Peter left off in actually launches. The rest come back
    /// dormant and start when he clicks them, so a login with six saved tabs
    /// costs one claude instead of six. The orphan sweep still runs for every
    /// one of them: a session left behind by a crash has to go whether or not
    /// this launch intends to resume its conversation.
    func restore() {
        let saved = AppConfig.defaults.array(forKey: Self.tabsKey) as? [[String: Any]] ?? []
        for entry in saved {
            guard let string = entry["id"] as? String, let id = UUID(uuidString: string) else { continue }
            let number = entry["number"] as? Int ?? counter + 1
            counter = max(counter, number)
            // A crash or a force quit skips the shutdown, leaving the old
            // claude alive and still holding this conversation. Resuming
            // underneath it would put two of them on one transcript.
            if let stale = entry["pid"] as? Int {
                AppConfig.killOrphan(pid: pid_t(stale), sessionID: id)
            }
            // A tab that went private never comes back: its conversation was
            // purged the moment its session ended, so restoring it would seat
            // an empty zombie wearing yesterday's number.
            if entry["private"] as? Bool == true { continue }
            let session = TerminalSession(number: number, id: id, autoStart: false)
            session.customLabel = entry["label"] as? String
            sessions.append(session)
        }
        let previous = AppConfig.defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        activeID = sessions.contains { $0.id == previous } ? previous : sessions.first?.id
        // Every restored tab's conversation gets claimed the moment the app
        // owns it again, dormant ones included: a dormant tab writes nothing,
        // which is exactly what claude's retention sweep mistakes for
        // abandoned.
        AppConfig.claimTranscripts(for: sessions.map(\.id))
        ensureSession()
    }

    /// Write the tab list down (pids included, so the sweep next launch has
    /// something to aim at), then hang up on every child and wait for them.
    /// The wait is the point: the app is about to exit, and anything still
    /// breathing when it does becomes an orphan holding a conversation.
    func shutdownAll() {
        save()
        // One last claim on the way out, so the day the sweep needs to reap
        // a saved conversation starts counting from quit, not from whenever
        // each tab last spoke.
        AppConfig.claimTranscripts(for: sessions.map(\.id))
        let pids = sessions.compactMap { $0.childPID }
        sessions.forEach { $0.shutdown() }
        for _ in 0..<20 {
            var status: Int32 = 0
            let alive = pids.filter { waitpid($0, &status, WNOHANG) == 0 && kill($0, 0) == 0 }
            if alive.isEmpty { return }
            usleep(100_000)
        }
        pids.forEach { kill($0, SIGKILL) }
    }

    /// The pid rides along so the next launch can recognise a claude this
    /// app left behind and clear it before resuming the same conversation.
    /// Privacy is stamped here rather than looked up at restore, because by
    /// restore time the session has ended and the privacy ledger has already
    /// forgotten it, quit-time is the only moment both facts are in hand.
    func save() {
        let tainted = AppConfig.taintedSessions()
        // Cards are not conversations, so they never come back on a relaunch.
        let tabs = sessions.filter { !$0.isEphemeral }.map { session -> [String: Any] in
            var entry: [String: Any] = ["id": session.id.uuidString, "number": session.number]
            if let pid = session.childPID { entry["pid"] = Int(pid) }
            if let label = session.customLabel { entry["label"] = label }
            if tainted.contains(session.id) { entry["private"] = true }
            return entry
        }
        AppConfig.defaults.set(tabs, forKey: Self.tabsKey)
        AppConfig.defaults.set(activeID?.uuidString, forKey: Self.activeKey)
    }

    /// Cmd-minus / cmd-equals resize every session's text, persisted.
    /// The rail refuses out loud: a step that changes nothing used to feel
    /// identical to one that did, so the limits were only findable by eye.
    func adjustFont(by delta: CGFloat) {
        setFont(to: min(18, max(9, AppConfig.fontSize + delta)))
    }

    /// Back to the size the app ships with. The third of the standard trio,
    /// and the one that was missing: without it there is no way to find your
    /// way home except by counting steps.
    func resetFont() {
        setFont(to: AppConfig.defaultFontSize)
    }

    private func setFont(to size: CGFloat) {
        guard size != AppConfig.fontSize else {
            Haptics.deny()
            return
        }
        AppConfig.defaults.set(Double(size), forKey: "fontSize")
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        sessions.forEach { $0.terminalView.font = font }
        Haptics.tap()
    }
}
