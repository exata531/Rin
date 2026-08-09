// what the panel actually looks like
// the tab bar the empty room and the terminal sitting under both of them
// the find bar the quick switcher and the filed-note toast ride over the terminal now too
// the terminal is the only opaque thing in here on purpose glass over text you have to read is just worse

import AppKit
import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers

/// Hosts a session's persistent terminal view inside SwiftUI.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    /// The keyboard is claimed HERE and nowhere else in this type.
    ///
    /// `updateNSView` used to ask for first responder too, which meant every
    /// SwiftUI pass asked: a hover on the tab bar, a pin toggling, a tab title
    /// changing, the panel not even being on screen. Anything else that had the
    /// keyboard lost it a moment later, which is the whole reason nothing else
    /// in this panel could be driven from the keyboard at all. The view is
    /// rebuilt with `.id(session.id)`, so a tab switch comes back through here
    /// anyway, and opening the panel claims focus explicitly. Nothing was lost
    /// by taking the other one out.
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = session.terminalView
        DispatchQueue.main.async {
            guard let window = view.window, window.isKeyWindow else { return }
            guard window.firstResponder !== view else { return }
            window.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

/// Behind-window blur, the same treatment titlebars get, unless the person
/// asked for less of it. Reduce Transparency is the sibling setting to Reduce
/// Motion, and the HIG asks for the same courtesy: the layer keeps its job and
/// loses its translucency. `NSVisualEffectView` already flattens itself when
/// the setting is on, but it flattens to the system's idea of the surface,
/// which on this dark panel reads as a pale band. So the fill is chosen here,
/// out of the terminal's own palette, the same argument as everywhere else in
/// this app: a colour nobody chose is a colour that will be wrong somewhere.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        guard Motion.reducedTransparency else {
            view.isEmphasized = false
            view.layer?.backgroundColor = nil
            return
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = TerminalTheme.bar.cgColor
    }
}

struct DropdownView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject private var faceState = FaceState.shared
    @ObservedObject private var setup = SetupState.shared
    @State private var barHovering = false
    /// The chip mid-drag, so the bar can reorder around it as it travels.
    @State private var draggingChip: UUID?
    @State private var pinPressed = false
    @State private var plusPressed = false
    @State private var startPressed = false
    @Namespace private var pillSpace

    var body: some View {
        VStack(spacing: 0) {
            // Until a brain folder exists, the one tab IS the setup (a TUI in
            // the terminal, first-run.sh), so the bar stays out of the way.
            if setup.isComplete, !store.sessions.isEmpty {
                tabBar
                // The find bar drops in under the tabs, part of the same
                // navigation layer, and leaves the way it came.
                if store.isSearching, store.active != nil {
                    FindBar(store: store)
                        .transition(
                            Motion.reduced
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            if let active = store.active {
                ZStack {
                    TerminalHostView(session: active)
                        .id(active.id)
                        // Optical, not arithmetic: the text sits in a balanced
                        // well. The trailing edge is narrower because the
                        // scroller lives in it, so an equal number there would
                        // read as a wider gap than the leading one.
                        .padding(.top, 7)
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .padding(.bottom, 7)
                    if store.isSwitching {
                        QuickSwitcher(store: store)
                            .transition(.opacity)
                    }
                    if let filed = store.filedNote {
                        filedToast(filed)
                    }
                }
                // The content layer stays OPAQUE. Glass belongs to the
                // navigation layer; a terminal rendered over a blurred
                // desktop is a legibility problem wearing a nice coat.
                .background(Color(nsColor: TerminalTheme.background))
            } else {
                emptyState
                    .background(Color(nsColor: TerminalTheme.background))
            }
        }
        .animation(Motion.move, value: store.sessions.isEmpty)
        .animation(Motion.move, value: store.isSearching)
        .animation(Motion.quick, value: store.isSwitching)
        .animation(Motion.quick, value: store.filedNote)
        // The shrink-wrapped setup panel sits below the working minimums;
        // holding 640 here would stretch the window right back out.
        .frame(
            minWidth: setup.isComplete ? 640 : 480,
            minHeight: setup.isComplete ? 400 : 320
        )
        // The font-size shortcuts used to be two invisible zero-size buttons
        // hidden in this overlay. They live in the View menu now, which is
        // where the Mac keeps them, which is also how Cmd-0 finally exists.
    }

    /// The one line of feedback filing earns: where the note landed, said
    /// once, gone on its own. A dialog for a success would be the app
    /// applauding itself.
    private func filedToast(_ toast: SessionStore.Toast) -> some View {
        Text(toast.text)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: TerminalTheme.foreground))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: TerminalTheme.bar), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(Ink.edge), lineWidth: 1))
            .frame(maxWidth: 420)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            // Rises a touch as it lands, the panel's own arrival in
            // miniature; Reduce Motion keeps only the fade.
            .transition(
                Motion.reduced
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity)
            )
            .task(id: toast) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                store.filedNote = nil
            }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // The one place inside the panel her state shows: the empty room
            // wears whatever face the menu bar is wearing, at ghost opacity,
            // falling back to the glyph when the bar is bare.
            Text(faceState.current ?? "凛")
                .font(.system(size: faceState.current == nil ? 64 : 44, weight: .medium))
                .foregroundStyle(Color(nsColor: TerminalTheme.foreground).opacity(Ink.ghost))
            // "no sessions running" was how the program describes itself.
            // This is how a person would say it.
            Text("nothing open")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: TerminalTheme.foreground).opacity(Ink.dim))
            Button(action: { store.newSession() }) {
                Text("start one")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressReporting(pressed: $startPressed))
            .foregroundStyle(Color(nsColor: TerminalTheme.foreground))
            .glassPill(in: Capsule())
            .pressed(startPressed)
            .focusRing(in: Capsule())
            .keyboardShortcut("t", modifiers: .command)
            // The shortcut used to sit under the button as a third line of
            // ever-smaller grey text. An empty room is a glyph, a sentence and
            // a way out; the keystroke belongs on the control it works, which
            // is where the Mac has always put it.
            .help("New session (Cmd-T)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    /// Chips divide the bar between them only when there is something to
    /// divide it with. Settled 2026-08-08, the last open call from the UI pass
    /// on the 4th.
    ///
    /// A lone chip stretched the full width of the panel with an eleven point
    /// label centred in it, which read as a title bar rather than as a tab.
    /// Safari answers that by showing no bar at all at one tab, and so do
    /// Finder, Terminal and Xcode, but their bar holds tabs and nothing else,
    /// and this one also holds the pin, the new-session button, and the
    /// working light that lives on the chip itself. Hiding it would take all
    /// three away in the case that is by far the most common. So the bar stays
    /// and the chip stops pretending to be one.
    private var chipsStretch: Bool { store.sessions.count > 1 }

    /// What the plus bounces off: tabs LANDED, not tabs alive, because the
    /// count also moves when a tab closes and a bounce for a departure
    /// announces the wrong event. Frozen under Reduce Motion, which silences
    /// the effect without branching the view: a value that never changes is
    /// an effect that never fires.
    private var plusBounce: Int { Motion.reduced ? 0 : store.arrivals }

    private var tabBar: some View {
        HStack(spacing: 7) {
            ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                TerminalTabChip(
                    session: session,
                    index: index,
                    isActive: session.id == store.activeID,
                    stretches: chipsStretch,
                    pillSpace: pillSpace,
                    store: store,
                    select: {
                        if store.activeID != session.id { Haptics.tap() }
                        store.activeID = session.id
                    },
                    close: { store.close(session) }
                )
                .frame(maxWidth: chipsStretch ? .infinity : nil)
                // Drag a chip somewhere else on the bar. The order used to be
                // fixed, so the only way to renumber a tab was closing and
                // reopening it, which for a live session meant hanging up on
                // claude to move a piece of furniture.
                .onDrag {
                    draggingChip = session.id
                    return NSItemProvider(object: session.id.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ChipDrop(target: session.id, dragging: $draggingChip, store: store)
                )
                .transition(
                    Motion.reduced
                        ? .opacity
                        : .scale(scale: 0.85).combined(with: .opacity)
                )
            }

            // With nothing stretching, the gap has to come from somewhere, or
            // the pin and the plus slide over and sit against the chip.
            if !chipsStretch { Spacer(minLength: 0) }

            // On screen at all times (Peter, 2026-08-08: "make the pin visible
            // ... currently it is invisible until you hover over it"). It used
            // to fade in on hover, the standing bargain for a secondary control
            // in a bar this small, with the menu bar's own menu as the findable
            // path. That bargain only pays for somebody who already knows the
            // control exists; a control nobody can see is a control nobody
            // looks for, and hover is not discoverable on a trackpad you are
            // not already moving. It carries its state in weight instead: dim
            // and outlined when off, full strength and filled when on.
            //
            // Tilted fifteen degrees, also his call, leaning LEFT (he looked
            // at it the other way round first and sent it back). A pushpin
            // drawn bolt upright reads as an icon of a pin; one leaning
            // slightly reads as a pin actually stuck into something, which is
            // what it does. The tilt is on the symbol and not on the button,
            // so the hit target, the focus ring and the tooltip stay square.
            Button(action: {
                store.isPinned.toggle()
                Haptics.tap()
            }) {
                Image(systemName: store.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    // Two different symbols were being swapped with no
                    // transition at all, so the pin just teleported between
                    // outline and filled. This is the exact swap Apple built
                    // the replace effect for, and it costs one line.
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(-15))
                    // Optically centred rather than mathematically centred
                    // (Peter, 2026-08-08, looking at a crop of it: "you might
                    // have to move it a tiny bit right because you tilted it").
                    // He is right. The glyph is a heavy head over a thin
                    // needle, so its visual weight sits well above and left of
                    // the box it is drawn in, and rotating it anticlockwise
                    // carries that weight further left again. Centring the BOX
                    // therefore leaves the thing your eye actually reads
                    // sitting off to one side. Nudged back by a point, which
                    // is half a pixel of glyph on this display and the whole
                    // difference between centred and nearly centred.
                    .offset(x: 1)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(PressReporting(pressed: $pinPressed))
            .foregroundStyle(store.isPinned ? .primary : .secondary)
            .opacity(store.isPinned ? 1 : (barHovering ? Ink.standingLift : Ink.standing))
            // The same glass circle the plus wears. It went missing the moment
            // the pin stopped being a hover-only ghost: two controls sitting
            // side by side, one on a disc and one floating bare, read as one
            // button and one smudge. A permanent control needs the same
            // affordance its neighbour has.
            .glassPill(in: Circle())
            .pressed(pinPressed)
            .focusRing(in: Circle())
            .help(store.isPinned ? "Unpin (close when clicking away)" : "Pin (stay open when clicking away)")
            .accessibilityLabel("Pin panel")

            Button(action: { store.newSession() }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    // The button answers when a tab actually lands, whether
                    // it was this button, Cmd-T, a nudge, or a link from the
                    // web that opened one. A control that reacts to what it
                    // caused is a nicety; one that reacts to the THING
                    // happening is feedback.
                    .symbolEffect(.bounce, options: .nonRepeating, value: plusBounce)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(PressReporting(pressed: $plusPressed))
            .glassPill(in: Circle())
            .pressed(plusPressed)
            .focusRing(in: Circle())
            .keyboardShortcut("t", modifiers: .command)
            // Prepared openings, offered where new sessions come from. Read
            // from the brain at the moment the menu opens, so the writers own
            // every word and the app only carries the tray.
            .contextMenu {
                let starters = AppConfig.sessionStarters()
                if starters.isEmpty {
                    Text("Starters live in _meta/starters.json")
                } else {
                    ForEach(Array(starters.enumerated()), id: \.offset) { _, starter in
                        Button(starter.title) { store.newSession(prompt: starter.prompt) }
                    }
                }
            }
            .help("New session (Cmd-T); right-click for starters")
            .accessibilityLabel("New session")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(VisualEffect(material: .headerView))
        // The catch-all under the chips: a reorder let go on the bar's
        // padding, or in the gap between chips, still commits with its
        // knock and clears the drag. Without this the commit only landed
        // when the drop finished exactly on a chip, and a near miss left
        // the new order in place but the gesture unanswered.
        .onDrop(of: [.plainText], delegate: BarDrop(dragging: $draggingChip))
        // No hairline here, deliberately (2026-08-03, reverted the same day
        // it shipped). Peter: "i liked the liquid glass more." A drawn rule
        // is the opposite move to what this material is for, Apple's own
        // guidance is that depth on glass comes from lensing light, not from
        // borders, and the edge it drew turned a floating surface into a
        // flat toolbar. The separation is the blur against the opaque
        // content below it, and that is enough.
        .onHover { barHovering = $0 }
        .animation(Motion.quick, value: barHovering)
        .animation(Motion.quick, value: store.isPinned)
        .animation(Motion.move, value: store.activeID)
        .animation(Motion.move, value: store.sessions.map(\.id))
    }
}

struct TerminalTabChip: View {
    @ObservedObject var session: TerminalSession
    let index: Int
    let isActive: Bool
    /// Whether this chip is sharing the bar and should divide the width with
    /// the others. At one session it sizes to its own label instead; the
    /// reasoning lives on the bar, where the call was made.
    let stretches: Bool
    let pillSpace: Namespace.ID
    /// For the actions the context menu grew on 2026-08-08 (rename, filing,
    /// the red bead's card). Held plainly, not observed: the chip already
    /// rebuilds through the bar's ForEach when the store changes.
    let store: SessionStore
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    /// The rename popover, and the name being typed into it.
    @State private var renaming = false
    @State private var draft = ""
    /// Escape was pressed in the rename field: the typed name dies with the
    /// popover instead of being caught by the click-away commit.
    @State private var renameCancelled = false
    /// Cmd-W just bounced off a session with a live claude behind it. The
    /// refusal used to be a haptic and nothing else, which on a Mac with no
    /// Force Touch trackpad is indistinguishable from a shortcut that does not
    /// exist. Now the close control shows itself and the chip flinches, so the
    /// answer is "hold this one" rather than silence.
    @State private var refusedClose = false

    var body: some View {
        chipButton
            .buttonStyle(PressReporting(pressed: $pressed))
            // Double-click renames, the way iTerm and Finder rename: the
            // context menu keeps its row for whoever looks there instead.
            // The first click of the pair selects, which is what a single
            // click was going to do anyway.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard !session.isEphemeral else { return }
                draft = session.customLabel ?? ""
                renaming = true
            })
            .background {
                // ONE glass surface in the bar, and it is the active pill.
                // Glass is the floating navigation layer, not a way to say
                // things: a bar where every tab is lensed reads as decoration
                // and loses the one contrast that was doing work.
                if isActive {
                    Capsule()
                        .fill(.clear)
                        .glassPill(in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(hovering ? Ink.edge : 0), lineWidth: 1))
                        .matchedGeometryEffect(id: "activePill", in: pillSpace)
                } else {
                    Capsule().fill(.primary.opacity(hovering ? Ink.hover : Ink.rest))
                }
            }
            .contextMenu {
                // A card is a page wearing a tab: nothing to rename, nothing
                // to file, so its menu stays one row.
                if !session.isEphemeral {
                    Button("Rename Tab…") {
                        draft = session.customLabel ?? ""
                        renaming = true
                    }
                    Button("File into Brain") { store.fileToBrain(session) }
                    Divider()
                }
                if session.didFailLaunch {
                    // The loudest colour on the bar finally explains itself.
                    Button("Why won't it start?") { store.openLaunchHelp() }
                }
                if !session.isRunning {
                    Button("Restart Session") { session.restart() }
                }
                Button("Close Tab") { close() }
            }
            .popover(isPresented: $renaming, arrowEdge: .bottom) {
                TextField("name this tab", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 190)
                    .padding(10)
                    .onSubmit {
                        // Emptying the field hands the title back to the
                        // terminal; rename() reads blank as "let it speak".
                        store.rename(session, to: draft)
                        renaming = false
                    }
                    // Escape means never mind, the way it does mid-rename in
                    // Finder. Without this the click-away commit below caught
                    // the Escape too, which turned the cancel gesture into a
                    // save.
                    .onExitCommand {
                        renameCancelled = true
                        renaming = false
                    }
                    // Clicking away keeps the name too, the way Finder
                    // keeps a rename: typing a label and losing it to a
                    // stray click reads as broken. Return and click-away
                    // agree; the guard keeps a submitted name from being
                    // committed twice.
                    .onDisappear {
                        defer { renameCancelled = false }
                        guard !renameCancelled else { return }
                        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if typed != (session.customLabel ?? "") {
                            store.rename(session, to: draft)
                        }
                    }
            }
            .scaleEffect(chipScale)
            .offset(x: refusedClose && !Motion.reduced ? -3 : 0)
            .animation(Motion.quick, value: hovering)
            // Down glued to the finger, up on the spring: same split as
            // every pill control, so the whole bar clicks with one voice.
            .animation(pressed ? Motion.quick : Motion.release, value: pressed)
            .animation(refusedClose ? .default.speed(6).repeatCount(3, autoreverses: true) : Motion.quick,
                       value: refusedClose)
            .focusRing(in: Capsule())
            .onHover { hovering = $0 }
            .accessibilityLabel(label)
    }

    /// The press, seen: mouse-down settles the chip a hair, release springs
    /// it back, and the hover lift stands aside while the finger is down.
    /// Visual only; the felt beat belongs to the select that fires.
    private var chipScale: CGFloat {
        if Motion.reduced { return 1 }
        if pressed { return Motion.chipPress }
        return hovering ? Motion.chipLift : 1.0
    }

    /// Every alert is said in words as well as in colour, so the hue is never
    /// the only thing carrying it.
    private var label: String {
        let name = "Session \(index + 1): \(session.displayTitle)"
        if session.didFailLaunch { return name + ", could not start" }
        if !session.isRunning { return name + ", ended" }
        if session.isPrivate { return name + ", private, gone at midnight" }
        if session.isRemote { return name + ", reachable from your phone" }
        return name
    }


    @ViewBuilder private var chipButton: some View {
        if index < 9 {
            coreButton.keyboardShortcut(
                KeyEquivalent(Character("\(index + 1)")),
                modifiers: .command
            )
        } else {
            coreButton
        }
    }

    private var coreButton: some View {
        Button(action: select) {
            ZStack {
                Text(session.displayTitle)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .opacity(session.isDormant ? Ink.muted : 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 22)

                HStack {
                    HoldToCloseX(session: session, refused: refusedClose, close: close)
                        .opacity(hovering || refusedClose ? 1 : 0)
                    Spacer()
                    // Every one of these is a published property now. The
                    // working light used to ride a two-second TimelineView per
                    // chip, which rebuilt every chip in the bar on a heartbeat
                    // whether or not a single thing had changed; the poll that
                    // reads the disk already runs on that beat and already
                    // knows the answer, so the bar can just be told.
                    ChipStatusDot(
                        needsAttention: session.needsAttention,
                        isRunning: session.isRunning,
                        isDormant: session.isDormant,
                        isWorking: session.isWorking,
                        didFailLaunch: session.didFailLaunch,
                        isRemote: session.isRemote,
                        isPrivate: session.isPrivate
                    )
                    // The red bead answers a click with the card that
                    // explains it. Only red: every other colour is either
                    // self-evident or already carried by its tooltip, and a
                    // dot that hijacks the click would break the chip.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard session.didFailLaunch else {
                            select()
                            return
                        }
                        store.openLaunchHelp()
                    }
                }
                .padding(.horizontal, 8)

                if isActive {
                    // Cmd-W: closes an ended tab or a card instantly; a live
                    // or dormant one only taps back (hold the x).
                    Button(action: {
                        if !session.isIdle {
                            Haptics.deny()
                            refusedClose = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                refusedClose = false
                            }
                        } else {
                            close()
                        }
                    }) { EmptyView() }
                    .buttonStyle(.plain)
                    .keyboardShortcut("w", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: stretches ? .infinity : nil)
            .frame(height: 24)
            .contentShape(Capsule())
        }
    }

}

/// The chip's one trailing slot, one meaning at a time. Pulsing dot: this
/// session wants Peter (bell, or a death he has not seen). Filled dot: it
/// ended. Hollow ring: restored but not started, so clicking launches it.
/// Breathing dot: claude is mid-task in there, leave it to cook. Attention
/// outranks everything, then hands the slot back once he looks.
///
/// Colour is spent on ALERTS and nothing else, so a hue in the bar always
/// means something is wrong or something is on, never which tab is which:
/// red cannot start, amber ended or broke, green the phone can reach it,
/// purple the tab went private and dies at midnight. Ordinary life stays
/// grey, and only a lit bead glows, the way a charger light does. Green and
/// purple are standing properties, hues that survive a busier state
/// underneath: the session stays private (or reachable) while claude works
/// in there, so the colour stays and the beat carries what is happening.
/// Purple outranks green when both are true, because "this will die" is the
/// warning and "your phone can see it" is a convenience.
struct ChipStatusDot: View {
    let needsAttention: Bool
    let isRunning: Bool
    let isDormant: Bool
    let isWorking: Bool
    let didFailLaunch: Bool
    let isRemote: Bool
    let isPrivate: Bool

    private struct Light {
        let color: SwiftUI.Color
        let beat: PulseBead.Beat
        let glows: Bool
        let help: String
    }

    private var light: Light? {
        if didFailLaunch {
            return Light(color: Alert.broken, beat: .pulse, glows: true, help: "Could not start")
        }
        if !isRunning {
            return Light(
                color: Alert.ended,
                beat: needsAttention ? .pulse : .still,
                glows: true,
                help: "Session ended"
            )
        }
        if isDormant { return nil }
        // Private and reachable-from-the-phone are standing properties of the
        // session, not passing states, so their hue holds the bead the whole
        // time it is on and the BEAT carries what is happening inside. Before
        // this the dot fell back to grey the moment claude started working,
        // which dropped the one thing the colour was there to say.
        let standing: SwiftUI.Color? = isPrivate ? Alert.incognito : (isRemote ? Alert.remote : nil)
        let standingWord = isPrivate ? "private, gone at midnight" : "reachable from your phone"
        if needsAttention {
            return Light(
                color: standing ?? Alert.wants,
                beat: .pulse,
                glows: standing != nil,
                help: standing != nil ? "Wants your eyes, \(standingWord)" : "Wants your eyes"
            )
        }
        if isWorking {
            return Light(
                color: standing ?? Alert.busy,
                beat: .breathe,
                glows: standing != nil,
                help: standing != nil ? "Claude is working, \(standingWord)" : "Claude is working"
            )
        }
        if let standing {
            return Light(
                color: standing,
                beat: .still,
                glows: true,
                help: isPrivate ? "Private, gone at midnight" : "Reachable from your phone"
            )
        }
        return nil
    }

    var body: some View {
        if isRunning, isDormant {
            Circle()
                .strokeBorder(.secondary.opacity(Ink.dim), lineWidth: 1)
                .frame(width: 6, height: 6)
        } else if let light {
            PulseBead(color: light.color, beat: light.beat, glows: light.glows)
                .frame(width: 6, height: 6)
                .help(light.help)
        }
    }
}

/// The lit bead, beating on the render server instead of in the view graph.
///
/// It looks the same to the pixel. What changed is who carries the rhythm. A
/// SwiftUI `repeatForever` re-enters the view graph and commits a layer tree
/// every frame for as long as it runs, and while anything on screen is
/// committing, WindowServer will not flatten its layers, so the frosted bar
/// above the terminal keeps re-sampling live pixels underneath it for the
/// whole time one tab happens to be working. Handing the same two keyframes
/// to CoreAnimation moves the loop out of the app: the beat runs in the
/// render server, and this process gets to sleep between the frames it is
/// actually needed for (measured 2026-08-03).
///
/// It also buys a rhythm that survives a wording change. The old bead was
/// identified by its tooltip as well as its beat, so a session whose
/// description changed restarted the animation mid-breath, a visible stutter
/// arriving at exactly the moment the tab was worth looking at.
struct PulseBead: NSViewRepresentable {
    let color: SwiftUI.Color
    let beat: Beat
    let glows: Bool

    /// Still: the bead just sits lit. Breathe: slow, leave it alone. Pulse:
    /// faster and scaled, come here.
    enum Beat: String { case still, breathe, pulse }

    func makeNSView(context: Context) -> BeadView { BeadView() }

    func updateNSView(_ view: BeadView, context: Context) {
        view.apply(color: NSColor(color), beat: beat, glows: glows)
    }

    final class BeadView: NSView {
        private let bead = CALayer()
        private var applied: (color: NSColor, beat: Beat, glows: Bool, still: Bool)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(bead)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        override func layout() {
            super.layout()
            bead.frame = bounds
            bead.cornerRadius = bounds.width / 2
            // The shadow's SHAPE never changes, only how far it spreads, so
            // handing CoreAnimation the path once stops it tracing the circle
            // out of the layer's alpha on every frame of the throb.
            bead.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        }

        /// How each state looks at its brightest and at its dimmest.
        ///
        /// The glow does most of the talking. A six-point dot cannot change
        /// size enough to read across the bar, fifteen percent of six points
        /// is under a pixel, but the halo around it has room to bloom, so the
        /// spread carries the urgency and the dot stays a dot. Scale is left
        /// in on the pulse only, small, as something the eye catches rather
        /// than sees.
        private struct Look {
            let opacity: (bright: Double, dim: Double)
            let halo: (bright: Double, dim: Double)
            let spread: (bright: Double, dim: Double)
            let scale: (bright: Double, dim: Double)
            /// Where in the cycle the dim point falls. Even is a machine
            /// blinking; uneven is something breathing.
            let turn: Double
        }

        private func look(_ beat: Beat) -> Look {
            switch beat {
            case .still:
                return Look(opacity: (0.85, 0.85), halo: (0.5, 0.5),
                            spread: (3.6, 3.6), scale: (1, 1), turn: 0.5)
            case .breathe:
                // Out slowly, back a little quicker, the way a breath actually
                // goes. Leave-it-alone should never look impatient.
                return Look(opacity: (0.74, 0.2), halo: (0.5, 0.14),
                            spread: (4.6, 2.6), scale: (1, 1), turn: 0.62)
            case .pulse:
                // Come-here is even and insistent, and the halo swings hardest
                // here because this is the one that has to be seen from the
                // corner of an eye.
                return Look(opacity: (0.98, 0.34), halo: (0.62, 0.12),
                            spread: (6.2, 2.4), scale: (1.12, 0.88), turn: 0.5)
            }
        }

        func apply(color: NSColor, beat: Beat, glows: Bool) {
            // System Reduce Motion: the bead still lights, it just stops
            // moving, and it holds its BRIGHT phase rather than whatever
            // trough the animation would have started from. A come-look dot
            // parked at its dimmest is a signal switched off for exactly the
            // people who asked for less motion.
            let still = Motion.reduced
            let now = (color, beat, glows, still)
            if let applied, applied == now { return }
            applied = now

            let look = look(beat)
            bead.removeAllAnimations()
            bead.backgroundColor = color.cgColor
            bead.shadowColor = color.cgColor
            bead.shadowOffset = .zero
            bead.opacity = Float(look.opacity.bright)
            bead.shadowOpacity = glows ? Float(look.halo.bright) : 0
            bead.shadowRadius = look.spread.bright
            bead.transform = CATransform3DIdentity

            guard beat != .still, !still else { return }

            // One cycle is bright, dim, bright, the whole breath in a single
            // animation rather than a half of one played backwards, which is
            // what makes the uneven turn possible at all.
            let span = (beat == .pulse ? Motion.pulseDuration : Motion.breatheDuration) * 2
            bead.add(swing(#keyPath(CALayer.opacity), look.opacity, look.turn, span), forKey: "beat")
            if glows {
                bead.add(swing(#keyPath(CALayer.shadowOpacity), look.halo, look.turn, span), forKey: "halo")
                bead.add(swing(#keyPath(CALayer.shadowRadius), look.spread, look.turn, span), forKey: "spread")
            }
            if look.scale.bright != look.scale.dim {
                bead.add(swing("transform.scale", look.scale, look.turn, span), forKey: "swell")
            }
        }

        private func swing(
            _ path: String,
            _ ends: (bright: Double, dim: Double),
            _ turn: Double,
            _ span: Double
        ) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = [ends.bright, ends.dim, ends.bright]
            animation.keyTimes = [0, NSNumber(value: turn), 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            animation.duration = span
            animation.repeatCount = .infinity
            // Every property of one bead is driven off the same clock, so the
            // fade, the bloom and the swell cannot drift apart into a shimmer.
            animation.beginTime = 0
            return animation
        }
    }
}

/// Close control: a dead session closes on click; a live one must be HELD
/// while a ring fills around the x. Early release rewinds. Haptics on a
/// Force Touch trackpad mark the start and the point of no return, and a
/// ratchet of ticks in between says the hold is being counted.
struct HoldToCloseX: View {
    @ObservedObject var session: TerminalSession
    /// A Cmd-W just bounced off this tab. The chip flinches sideways; the x
    /// itself answers too, so the refusal reads on the control that was
    /// refused rather than only on the thing around it.
    let refused: Bool
    let close: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var fireItem: DispatchWorkItem?
    @State private var tickItems: [DispatchWorkItem] = []
    private let holdTime = 1.0

    var body: some View {
        ZStack {
            if !session.isIdle {
                Circle()
                    .stroke(.primary.opacity(holding ? Ink.track : 0), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .symbolEffect(.bounce, options: .nonRepeating, value: refused && !Motion.reduced)
        }
        .frame(width: 15, height: 15)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                // Dragging off a control and letting go is how every button on
                // the Mac is cancelled, and it was the one escape hatch this
                // one did not have: a press that wandered away still closed the
                // tab on release.
                .onEnded { value in endHold(onTarget: Self.target.contains(value.location)) }
        )
        .help(session.isIdle ? "Close" : "Hold to close")
        .accessibilityLabel(session.isIdle ? "Close session" : "Close session (hold)")
    }

    /// The control's own bounds, with a point of slack on each side so a
    /// steady finger on the edge is not read as a change of mind.
    private static let target = CGRect(x: -1, y: -1, width: 17, height: 17)

    private func beginHold() {
        guard !holding else { return }
        holding = true
        guard !session.isIdle else { return }
        Haptics.tap()
        withAnimation(.linear(duration: holdTime)) { progress = 1 }
        // The ratchet: a tick each quarter-turn of the ring, so the finger
        // knows the hold is registering before the point of no return.
        tickItems = [0.25, 0.5, 0.75].map { beat in
            let tick = DispatchWorkItem {
                guard holding else { return }
                Haptics.tap()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + holdTime * beat, execute: tick)
            return tick
        }
        let item = DispatchWorkItem {
            guard holding else { return }
            // The knock lives in the store's close now, one word per close
            // whichever gesture asked for it.
            close()
        }
        fireItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: item)
    }

    private func endHold(onTarget: Bool = true) {
        if session.isIdle {
            holding = false
            if onTarget { close() }
            return
        }
        fireItem?.cancel()
        fireItem = nil
        tickItems.forEach { $0.cancel() }
        tickItems = []
        holding = false
        withAnimation(Motion.quick) { progress = 0 }
    }
}

extension View {
    /// The lensed surface, or an honest opaque one when Reduce Transparency is
    /// on. Glass is the whole look of the navigation layer, so the setting has
    /// to reach it: a person who asked for less translucency and got a frosted
    /// bar with a lensed pill on it was told no.
    @ViewBuilder
    func glassPill(in shape: some Shape) -> some View {
        if Motion.reducedTransparency {
            self.background(Color(nsColor: TerminalTheme.bar), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(Ink.edge), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// The ring every other control on the Mac draws when Full Keyboard Access
    /// walks onto it. `.buttonStyle(.plain)` and `.borderless` both delete the
    /// system's, and nothing replaced it, so tabbing through this panel moved
    /// a focus nobody could see. Drawn in the accent colour, which is what the
    /// system uses and the one place this app is allowed a hue it did not pick.
    func focusRing(in shape: some Shape) -> some View {
        modifier(FocusRing(shape: AnyShape(shape)))
    }
}

private struct FocusRing: ViewModifier {
    let shape: AnyShape
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            // The SYSTEM'S ring stays off, everywhere this modifier goes
            // (2026-08-09, from Peter's screenshot). The plain and borderless
            // button styles used to suppress it as a side effect; the press
            // state's custom style does not, so every click grew a grey
            // rounded rectangle inside the capsule, the exact thing the
            // custom ring below was drawn to replace. One control, one ring:
            // ours, on the keyboard walk, in the accent.
            .focusEffectDisabled()
            .focused($focused)
            .overlay {
                shape
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .padding(-2)
                    .opacity(focused ? 1 : 0)
            }
            .animation(Motion.quick, value: focused)
    }
}

/// Reports the system's own pressed state outward and draws nothing itself.
/// The controls in this bar wear their glass OUTSIDE the button (the pill
/// modifiers sit after the style), so a style that scaled its own label
/// would depress the symbol and leave the disc floating still. The binding
/// lets the whole control, glass included, take the press.
struct PressReporting: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, now in pressed = now }
    }
}

extension View {
    /// The press, seen (2026-08-08): a hair of scale on mouse-down, sprung
    /// back on release, which is the entire skeuomorphic argument in one
    /// gesture. The two halves move differently on purpose (2026-08-09,
    /// the feel pass): down rides `quick`, glued to the finger, and the
    /// release rides the underdamped `release` spring, so the control POPS
    /// back past rest and settles, a click the eye can feel. Deliberately
    /// VISUAL ONLY, no haptic on the touch: the felt beat belongs to the
    /// action firing, and doubling it on the press would break the sparing
    /// rule that keeps the felt grammar legible (the law lives in
    /// Design.swift). Reduce Motion stills it.
    func pressed(_ down: Bool) -> some View {
        scaleEffect(down && !Motion.reduced ? Motion.pressDepth : 1)
            .animation(down ? Motion.quick : Motion.release, value: down)
    }
}

/// The bar's own drop floor, under the chips: only ever reached when a chip
/// drag lets go off-target, so it answers nothing else. Files and text keep
/// falling through to whatever they were aimed at.
struct BarDrop: DropDelegate {
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dragging != nil else { return false }
        dragging = nil
        Haptics.thunk()
        return true
    }
}

/// The reorder half of dragging a chip: as the travelling chip crosses a
/// neighbour, they trade places, and the drop is just letting go. Cmd-1
/// through 9 follow the new order because the number is an address, not a
/// name.
struct ChipDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let store: SessionStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        // Each swap ticks (Peter's ask, 2026-08-09): the drag ratchets the
        // way the hold-to-close ring counts its quarters, so the finger
        // knows a seat changed hands without looking. Alignment is the
        // word: chips snapping to a new order is the grammar's first
        // definition.
        if store.move(dragging, to: target) { Haptics.tap() }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        // Letting go commits the new order, and a commit is the knock.
        Haptics.thunk()
        return true
    }
}
