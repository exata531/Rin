// every number about how things look and move lives here
// if a duration or a color shows up anywhere else in the app that is a bug
// i kept ending up with three slightly different fade speeds and none of them meant anything

import AppKit
import SwiftUI

/// The design vocabulary, fixed in one place so a duration, an opacity, or a
/// hue means the same thing wherever it appears. Three families: Motion for
/// how things move, Ink for how strongly a thing sits on the slate, Alert
/// for the colours that are allowed to mean something. A number that appears
/// in a view instead of here is a bug of the same kind as a colour that
/// means two things.

/// How things move, and when they don't. System Reduce Motion is honoured
/// the way the HIG asks: travel, scale, and the breath go still; opacity
/// fades and information stay. `reduced` is read live, so flipping the
/// setting takes effect on the next update rather than the next launch.
enum Motion {
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduce Transparency, Reduce Motion's sibling. This app is mostly
    /// material, a frosted bar over an opaque terminal, one lensed pill
    /// marking the active tab, so honouring only one of the pair meant the
    /// setting did nothing where it mattered most. Read live, same as
    /// `reduced`, so flipping it takes on the next update.
    static var reducedTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Pointer reactions: hover fades, highlights, an aborted hold
    /// rewinding. Fast enough to feel attached to the finger. Fades
    /// survive Reduce Motion; anything that travels or scales checks
    /// `reduced` at the site, because the fade half still runs.
    static let quick: Animation = .easeOut(duration: 0.12)

    /// The release half of a press (2026-08-09, Peter: clicky, chunky,
    /// physics). The down-stroke stays on `quick`, glued to the finger; the
    /// way back up is a spring with a visible overshoot, which is the whole
    /// difference between a control that fades back and one that pops back.
    /// ONE soft overshoot, then settled: the first cut ran looser and
    /// wobbled (Peter, same morning: "a little too much jiggle"). Only ever
    /// runs where a press ran, so Reduce Motion never meets it.
    static let release: Animation = .spring(response: 0.25, dampingFraction: 0.72)

    /// How far a control settles under the finger, named so every button in
    /// the app weighs the same. The round pill controls sink deeper than a
    /// chip because a chip is carrying legible text at all times.
    static let pressDepth: CGFloat = 0.94
    static let chipPress: CGFloat = 0.97
    static let chipLift: CGFloat = 1.02

    /// The hand-rolled spring the held menu rows run on. AppKit draws those
    /// rows itself, so SwiftUI's spring cannot reach them; these two numbers
    /// are tuned to bounce like `release` does, one physics everywhere. Per
    /// 60fps tick: stiffness pulls toward the target, damping is the
    /// fraction of velocity that survives a frame. Damping sits where the
    /// release lands after ONE soft dip; the looser first cut is what
    /// jiggled.
    static let rowStiffness: CGFloat = 0.32
    static let rowDamping: CGFloat = 0.58

    /// Structure moving: tabs arriving and leaving, the active pill
    /// sliding. Under Reduce Motion structure snaps into place instead
    /// of travelling.
    static var move: Animation? { reduced ? nil : .snappy(duration: 0.25) }

    /// The two organic beats, shared by the menu bar glyph and the status
    /// dot so the app keeps ONE heart rate. Breathe: working, leave it.
    /// Pulse: come here. The pair reads because the tempo doubles.
    static let breatheDuration = 1.2
    static let pulseDuration = 0.7

    /// The panel's arrival and exit. Leaving is quicker than arriving on
    /// purpose: dismissal should feel lighter than presentation.
    static let panelDrop = 0.22
    static let panelTuck = 0.10

    /// An aborted hold rewinding its charge, wherever a hold lives: how long
    /// a full bar takes to run back to empty. A partial hold rewinds in a
    /// proportional slice of this, so letting go always feels like the same
    /// spring.
    static let holdRewind = 0.3
}

/// The felt vocabulary, stated as law beside Motion and Ink (2026-08-08).
/// The app had spoken four felt words since the beginning and never written
/// them down as a system, which is how a missing beat stays invisible; a
/// colour that means two things is caught by inspection because Alert is
/// written down, and now a wrong haptic is too. The words live in
/// `Haptics`; what each one MEANS lives here.
///
///   tap    — touched or aligned. A toggle, a tab selected, a size step,
///            the panel arriving or leaving, a scroll gesture meeting the
///            scrollback's wall. The lightest word, and the most spoken.
///   thunk  — committed or created. A tab lands, a drop lands, a hold
///            charges through, an order is let go of. Something exists now
///            (or is gone now) that did not before.
///   deny   — heard and refused. The font rail's end, a Cmd-W bounced off a
///            live session, a find with nowhere left to go. Never silence:
///            a refusal that cannot be felt or seen is a control that reads
///            as broken.
///   alert  — a summons. The bell's pattern, and nothing else. It is the
///            only word the app speaks unprompted, which is exactly why it
///            is the only one with a repeat.
///
/// Two rules keep the grammar legible. A press is never felt: press states
/// are visual only, because the felt beat belongs to the ACTION firing, and
/// doubling it on the touch would spend the vocabulary on nothing. And one
/// action is one word: a gesture that taps on contact and thunks on commit
/// is two moments, not one moment said twice.
enum Felt {}

/// How strongly a thing sits on the dark slate. The surface ramp is for
/// fills and strokes; the content ramp is for text and symbols. Primary
/// content is full strength and needs no token.
enum Ink {
    // Surfaces
    /// Resting fill of an inactive control.
    static let rest = 0.05
    /// The same control under the pointer.
    static let hover = 0.08
    /// A hairline that has to read as an edge.
    static let edge = 0.12
    /// The track behind a progress ring.
    static let track = 0.15

    // Menu rows. These two sit on MENU material rather than the slate, which
    // is why they are their own stops instead of reusing the surface ramp:
    // the same alpha reads a step stronger on the menu's lighter ground.
    /// The wash under a held row's pointer.
    static let menuWash = 0.14
    /// A held row's charge fill as it fills.
    static let menuFill = 0.34
    /// The brighter lip on the charge's leading edge, so the fill reads as
    /// a level rising rather than a rectangle growing.
    static let menuLip = 0.55

    // Content
    /// A permanent secondary CONTROL at rest: visible enough to be found,
    /// quiet enough to yield to the chips. The pin's resting strength, and
    /// its lift while the bar is hovered. Tuned by Peter's eye on the
    /// 2026-08-08 pass; named here so the numbers have one home.
    static let standing = 0.65
    static let standingLift = 0.9
    /// Watermark: present, ignorable.
    static let ghost = 0.22
    /// A hint beneath the main line.
    static let faint = 0.30
    /// Supporting text.
    static let dim = 0.45
    /// Content that is still content, muted: a dormant tab's title.
    static let muted = 0.55
}

/// The alert vocabulary, fixed so a colour means the same thing in every
/// tab: red cannot start, amber ended or broke, green the phone can reach
/// it, purple the tab went private and its conversation will not survive.
/// Colour is spent on alerts and nothing else; ordinary life stays
/// grey. Amber is drawn by hand rather than taken from the system orange,
/// which sits too close to red at six points across a dark bar.
enum Alert {
    /// The two a bead spends when nothing is WRONG: a tab that wants you, and
    /// a tab that is working. Deliberately not hues, colour still means an
    /// alert, but chosen rather than inherited. `.primary` and `.secondary`
    /// are mixed for whatever surface AppKit believes it is drawing on, and
    /// this bar is the same dark material in every appearance, so the system
    /// pair came out glaring in one and washed out in the other. These two are
    /// lifted from the terminal's own palette instead: the white it draws text
    /// in, and the slate slot claude leans on for everything it wants to
    /// de-emphasise. Same argument as the palette in `AppConfig`: a colour
    /// nobody chose is a colour that will be wrong somewhere.
    static let wants = SwiftUI.Color(nsColor: NSColor(srgbRed: 0.902, green: 0.914, blue: 0.933, alpha: 1))
    static let busy = SwiftUI.Color(nsColor: NSColor(srgbRed: 0.486, green: 0.533, blue: 0.588, alpha: 1))

    static let broken = SwiftUI.Color(nsColor: .systemRed)
    static let ended = SwiftUI.Color(nsColor: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.19, alpha: 1))
    static let remote = SwiftUI.Color(nsColor: .systemGreen)
    // Purple because it already means incognito everywhere else Peter looks,
    // but mixed by hand, like the amber: the system purple runs hot and reads
    // pink against the dark bar. This one is lilac, pastel on purpose
    // (Peter's call, 2026-08-01).
    static let incognito = SwiftUI.Color(nsColor: NSColor(srgbRed: 0.73, green: 0.62, blue: 0.93, alpha: 1))
}
