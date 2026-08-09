// menu rows you have to hold down
// the same bargain the tab's x makes, moved to the things that end the whole app

import AppKit

/// A menu row that refuses a single click and fires on a HOLD.
///
/// Peter's ask, 2026-08-08: "make uninstall rin like more like idk scary like
/// when you hover over tints red and the text turns red also rearange it so its
/// harder to click uninstall and add the same logic to closing a tab to that
/// button and quit rin and restart".
///
/// The app already had this argument once and settled it at the tab bar: a live
/// session will not close on a click, you hold the x and a ring fills. The three
/// rows at the bottom of this menu end things that cost more than a tab, every
/// session at once, or the app itself, and they were plain rows a slipped
/// pointer could land on. So they borrow the tab's bargain, including the
/// quarter-way ticks, which are what tell a finger the hold is registering
/// before it reaches the point of no return.
///
/// Destructive rows also wear it: red text, red wash under the pointer, and a
/// fill that runs left to right as it charges. macOS itself only ever tints a
/// destructive row red on hover, so this is that convention with the hold
/// bolted on rather than a look invented here.
///
/// A custom view means AppKit stops drawing the row for us: the highlight, the
/// text, the key hint and the enabled state are all painted below, which is the
/// price of a menu row that can do anything a menu row cannot.
final class HoldMenuItemView: NSView {
    private let title: String
    private let hint: String?
    private let destructive: Bool
    private let holdTime: TimeInterval
    private let perform: () -> Void

    private var hovering = false
    private var progress: CGFloat = 0
    private var began: Date?
    private var ticksFired = 0

    // The row's own little physics (2026-08-09, the feel pass). AppKit draws
    // this view by hand, so the springs are hand-rolled too: ONE clock at
    // 60fps runs only while something is moving, drives every animated value
    // toward its target, and stops itself when the row has settled. It
    // replaces the old charge ticker and rewinder pair.
    private var clock: Timer?
    /// The hover wash, faded in and out rather than snapped. 0 to 1.
    private var wash: CGFloat = 0
    /// How deep the row sits under the finger, 0 to 1, on a real spring:
    /// the release overshoots past rest and settles, which is the click.
    private var depression: CGFloat = 0
    private var depressionV: CGFloat = 0
    /// The teaching flash's target: an early click charges up to here fast,
    /// then the rewind runs it back down.
    private var surge: CGFloat = 0

    private static let inset: CGFloat = 21
    private static let height: CGFloat = 22
    /// Releases earlier than this fraction of the hold are a CLICK, someone
    /// expecting a normal row, and a click gets taught, not ignored.
    private static let clickThreshold: CGFloat = 0.15
    /// Where the teaching flash charges to before it rewinds: enough fill to
    /// read as "this row charges up", nowhere near enough to look dangerous.
    private static let hintCharge: CGFloat = 0.3
    /// How much of the row's scale a full press spends. Small on purpose: a
    /// menu row is wide, and two percent already reads as weight.
    private static let pressDip: CGFloat = 0.02
    /// Per-frame rates for the clock. The rewind's ease is derived from
    /// Motion.holdRewind so the menu rows and the tab's x keep ONE
    /// letting-go: three time-constants of proportional decay fit inside
    /// the shared rewind window, fast at first and settling gently.
    private static let washRate: CGFloat = 0.25
    private static let surgeRate: CGFloat = 0.06
    private static let rewindEase: CGFloat = 3.0 / CGFloat(Motion.holdRewind * 60.0)
    private static let rewindFloor: CGFloat = 0.004

    init(
        title: String,
        hint: String? = nil,
        destructive: Bool = false,
        holdTime: TimeInterval = 1.0,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.hint = hint
        self.destructive = destructive
        self.holdTime = holdTime
        self.perform = perform
        let width = Self.inset * 2 + Self.measure(title) + (hint.map { Self.measure($0) + 24 } ?? 0)
        super.init(frame: NSRect(x: 0, y: 0, width: max(180, width), height: Self.height))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    private static func measure(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }

    // MARK: hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                // A menu runs its own event loop, so anything less than
                // activeAlways never hears about the pointer at all.
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        startClock()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        // Dragging off a control and letting go is how every button on the Mac
        // is cancelled; the tab's x learned that the hard way and this inherits
        // the lesson rather than repeating it.
        abortHold(hint: false)
        startClock()
    }

    // MARK: the hold

    override func mouseDown(with event: NSEvent) {
        began = Date()
        ticksFired = 0
        surge = 0
        Haptics.tap()
        startClock()
    }

    override func mouseUp(with event: NSEvent) {
        guard progress < 1 else { return }
        // A release this early is a click from somebody expecting a normal
        // row, and a row that answers a click with nothing at all reads as
        // broken. The felt "no" plus a flash of the charge teaches the
        // mechanism wordlessly; a longer hold let go is the person's own
        // change of mind, and cancelling is never refused, so that one just
        // rewinds in silence, same as the tab's ring.
        abortHold(hint: progress < Self.clickThreshold)
    }

    /// One tick of the row's clock: charge, flash, rewind, wash, spring,
    /// in that order, then stop the clock if nothing is moving any more.
    private func tick() {
        // The menu can vanish mid-hold, Escape, focus theft, and the clock
        // outlives it: NOTHING may charge toward firing without a window to
        // be seen in, or an Escape pressed at nine tenths still quits the app.
        guard window != nil else {
            stopClock()
            reset()
            return
        }

        if let began {
            // The charge itself stays LINEAR on purpose: it is a countdown
            // to something irreversible, and a countdown that eases lies
            // about how much time is left. The physics live at the edges.
            progress = min(1, CGFloat(Date().timeIntervalSince(began) / holdTime))
            // The ratchet, quarter by quarter, exactly as the tab's ring does it.
            let due = Int(progress * 4)
            if due > ticksFired, due < 4 {
                ticksFired = due
                Haptics.tap()
            }
            if progress >= 1 {
                needsDisplay = true
                fire()
                return
            }
        } else if surge > progress {
            // The teaching flash on its way up: fast, so it reads as the
            // row answering the click, then the rewind owns it.
            progress = min(surge, progress + Self.surgeRate)
            if progress >= surge { surge = 0 }
        } else if progress > 0 {
            surge = 0
            // The spring-out rewind: proportional decay with a floor, so a
            // full bar and a sliver both ease off the same way, quick at
            // first and settling gently, inside the one rewind window every
            // hold in this app shares.
            progress = max(0, progress - progress * Self.rewindEase - Self.rewindFloor)
        }

        // The wash fades toward where the pointer actually is; a fade
        // carries information, so it survives Reduce Motion.
        let washTarget: CGFloat = hovering ? 1 : 0
        wash += (washTarget - wash) * Self.washRate
        if abs(washTarget - wash) < 0.02 { wash = washTarget }

        // The depression is a real spring: it dips while the finger is down
        // and overshoots past rest on the way back, which is what makes the
        // release read as a click. Reduce Motion stills the scale entirely.
        let depthTarget: CGFloat = (began != nil && !Motion.reduced) ? 1 : 0
        depressionV = (depressionV + (depthTarget - depression) * Motion.rowStiffness) * Motion.rowDamping
        depression += depressionV

        needsDisplay = true

        let settled =
            began == nil && progress <= 0 && wash == washTarget
            && abs(depression - depthTarget) < 0.002 && abs(depressionV) < 0.002
        if settled {
            depression = depthTarget
            depressionV = 0
            stopClock()
        }
    }

    private func fire() {
        stopClock()
        began = nil
        Haptics.thunk()
        let run = perform
        enclosingMenuItem?.menu?.cancelTracking()
        // After the menu is off screen, so an alert it raises is not fighting a
        // menu still tracking on top of it.
        DispatchQueue.main.async(execute: run)
    }

    private func abortHold(hint: Bool) {
        guard began != nil else { return }
        began = nil
        if hint {
            Haptics.deny()
            // The flash is decoration; the deny already said no. Reduce
            // Motion keeps the haptic and skips the theatre.
            if !Motion.reduced { surge = max(progress, Self.hintCharge) }
        }
        startClock()
    }

    private func startClock() {
        guard clock == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common rather than .default: a menu tracks in its own run loop mode
        // and a default-mode timer simply never fires while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func reset() {
        began = nil
        progress = 0
        surge = 0
        wash = 0
        depression = 0
        depressionV = 0
    }

    /// The menu is gone, so every clock this row was running dies with it.
    /// Without this, a hold abandoned to Escape leaves a timer firing forever
    ///, and if the view happens to outlive the dismissal, a charge that
    /// keeps counting FIRES, which for these rows means quitting the app the
    /// person just backed out of.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        stopClock()
        reset()
    }

    deinit {
        clock?.invalidate()
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let row = bounds.insetBy(dx: 5, dy: 0)
        let radius: CGFloat = 5

        // The press, seen: the whole surface sinks while the hold charges
        // and springs back past rest on release. Drawn as one transform so
        // wash, charge and text all sit on the same sinking plate. The
        // clamp lets the overshoot breathe without ever letting a runaway
        // spring draw something absurd.
        NSGraphicsContext.saveGraphicsState()
        let dip = Self.pressDip * min(max(depression, -0.6), 1.2)
        if dip != 0 {
            let sink = NSAffineTransform()
            sink.translateX(by: bounds.midX, yBy: bounds.midY)
            sink.scale(by: 1 - dip)
            sink.translateX(by: -bounds.midX, yBy: -bounds.midY)
            sink.concat()
        }

        if wash > 0.01 {
            let base = destructive ? NSColor.systemRed : NSColor.selectedContentBackgroundColor
            base.withAlphaComponent(Ink.menuWash * wash).setFill()
            NSBezierPath(roundedRect: row, xRadius: radius, yRadius: radius).fill()
        }

        if progress > 0 {
            // Charging left to right, so the row reads as filling up rather
            // than as flashing. It is the same information the tab's ring
            // carries, in the shape this row has room for. Clipped to the
            // rounded row so the leading edge of the fill keeps the corner.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: row, xRadius: radius, yRadius: radius).addClip()
            var filled = row
            filled.size.width = row.width * progress
            let base = destructive ? NSColor.systemRed : NSColor.selectedContentBackgroundColor
            base.withAlphaComponent(Ink.menuFill).setFill()
            filled.fill()
            // The brighter lip on the leading edge, so the charge reads as
            // a level rising rather than a rectangle growing.
            var lip = filled
            lip.origin.x = max(filled.minX, filled.maxX - 2)
            lip.size.width = 2
            base.withAlphaComponent(Ink.menuLip).setFill()
            lip.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let colour: NSColor =
            destructive
            ? (hovering || progress > 0 ? .systemRed : NSColor.systemRed.withAlphaComponent(0.85))
            : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: colour,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: Self.inset, y: (bounds.height - size.height) / 2),
            withAttributes: attributes)

        if let hint {
            // AppKit draws the key equivalent for an ordinary row and nothing
            // at all for a custom one, so the hint is painted here or it
            // disappears the moment a row starts holding.
            let dim: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let hintSize = (hint as NSString).size(withAttributes: dim)
            (hint as NSString).draw(
                at: NSPoint(
                    x: bounds.width - Self.inset - hintSize.width,
                    y: (bounds.height - hintSize.height) / 2),
                withAttributes: dim)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: assistive access
    //
    // The hold is a defence against a SLIPPED POINTER, and assistive tech has
    // no pointer to slip: VoiceOver cannot press-and-wait on a menu row at
    // all, so without this the three rows that matter most would simply not
    // exist for it. A deliberate accessibility press goes straight through,
    // the destructive rows still put their own dialog between the press and
    // anything irreversible.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? { title }

    override func accessibilityHelp() -> String? {
        "Hold down with the pointer, or press, to \(title.lowercased())"
    }

    override func accessibilityPerformPress() -> Bool {
        stopClock()
        began = nil
        let run = perform
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: run)
        return true
    }
}

extension NSMenu {
    /// Add a row that has to be held. Returns the item so a caller can keep it
    /// for the enabled-state dance if it ever needs one.
    @discardableResult
    func addHoldItem(
        title: String,
        hint: String? = nil,
        destructive: Bool = false,
        holdTime: TimeInterval = 1.0,
        perform: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = HoldMenuItemView(
            title: title,
            hint: hint,
            destructive: destructive,
            holdTime: holdTime,
            perform: perform)
        addItem(item)
        return item
    }
}
