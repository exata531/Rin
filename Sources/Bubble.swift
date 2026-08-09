// the little note that shows up under the icon
// dropping the whole terminal down for one sentence felt like way too much so this is the small version
// the app never writes the words the session that scheduled it does

import AppKit
import SwiftUI

/// The speech bubble: a nudge's one pre-written line, shown small under the
/// menu bar glyph and gone again. The whole terminal dropping for one
/// sentence is a stage entrance; this is the post-it. The app still never
/// composes a word, the text rides the nudge entry, written by the session
/// that queued it, and the face beside it is whatever the bar is already
/// wearing.
final class BubbleCenter {
    /// Where the bubble hangs from (the status item's screen rect) and what
    /// a tap should do; wired by the app delegate.
    var anchor: () -> NSRect? = { nil }
    var onTap: (String?) -> Void = { _ in }

    private var panel: NSPanel?
    private var hostController: NSViewController?
    private var hideTimer: Timer?
    private var prompt: String?
    private var holdUntil = Date.distantPast

    /// Show one line. A second bubble replaces the first: two post-its is a
    /// pile, and a pile is a notification center, which this is not.
    func show(text: String, face: String?, prompt: String?) {
        dismiss(animated: false)
        self.prompt = prompt

        let controller = NSHostingController(rootView: BubbleView(
            face: face,
            text: text,
            onHover: { [weak self] inside in self?.hoverChanged(inside) },
            onTap: { [weak self] in self?.tapped() }
        ))
        // SwiftUI must never drive this window's frame. The 09:34 test
        // measured one line, rendered three, and the window wandered off to
        // mid-screen while the diary swore it sat under the bar. The
        // controller measures once, at the bubble's fixed width, with its
        // auto-sizing OFF; after that the frame belongs to this class alone.
        controller.sizingOptions = []
        let fit = controller.sizeThatFits(in: NSSize(width: 376, height: 600))
        let size = NSSize(
            width: min(max(fit.width, 120), 376),
            height: max(fit.height, 48)
        )
        controller.view.setFrameSize(size)
        hostController = controller

        // Non-activating and never key: he is mid-something, and a bubble
        // that takes the keyboard is a bug wearing a feature's clothes. The
        // shadow is drawn by the view, not the window, so the clear window
        // never casts a rectangle around a rounded shape.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.contentView = controller.view
        self.panel = panel

        position(panel)
        NudgeLog.line("bubble window \(Int(size.width))x\(Int(size.height)) at \(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y))")

        // The dropdown's own arrival, at bubble scale: same travel, same
        // overshoot, so the two read as one family. Reduce Motion keeps the
        // fade and drops the travel, information intact.
        let final = panel.frame
        let travels = !Motion.reduced
        if travels { panel.setFrame(final.offsetBy(dx: 0, dy: 10), display: false) }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.panelDrop
            context.timingFunction = travels
                ? CAMediaTimingFunction(controlPoints: 0.3, 1.3, 0.5, 1.0)
                : CAMediaTimingFunction(name: .easeOut)
            if travels { panel.animator().setFrame(final, display: true) }
            panel.animator().alphaValue = 1
        }

        let hold = holdTime(for: text)
        holdUntil = Date().addingTimeInterval(hold)
        scheduleHide(after: hold)

        // The settle line: if anything moves this window after the fact,
        // the diary catches it in the act instead of leaving a mystery.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let settled = self.panel else { return }
            let f = settled.frame
            NudgeLog.line("bubble settled at \(Int(f.origin.x)),\(Int(f.origin.y)) size \(Int(f.width))x\(Int(f.height))")
        }
    }

    /// Centered under the icon, pulled back inside the screen edges, the
    /// dropdown's own placement rule, one size down.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        let anchorRect = anchor()
        let screen = NSScreen.screens.first { candidate in
            anchorRect.map { candidate.frame.intersects($0) } ?? false
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let preferred = (anchorRect?.midX ?? visible.maxX - size.width / 2 - 12) - size.width / 2
        let x = min(max(preferred, visible.minX + 4), visible.maxX - size.width - 4)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: visible.maxY + 2))
    }

    /// Long enough to read twice, sized up a little for a longer line.
    /// Reading is not a race; hover holds it open outright.
    private func holdTime(for text: String) -> TimeInterval {
        8 + min(4, TimeInterval(text.count) / 30)
    }

    private func hoverChanged(_ inside: Bool) {
        if inside {
            hideTimer?.invalidate()
            hideTimer = nil
        } else if panel != nil, hideTimer == nil {
            // A fly-through must not shorten the bubble's life: leaving
            // hover re-arms the full remainder of the original hold, with a
            // two-second grace once that time has already been spent.
            scheduleHide(after: max(2, holdUntil.timeIntervalSinceNow))
        }
    }

    private func tapped() {
        let prompt = prompt
        dismiss(animated: true)
        onTap(prompt)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func dismiss(animated: Bool) {
        hideTimer?.invalidate()
        hideTimer = nil
        prompt = nil
        guard let panel else { return }
        self.panel = nil
        hostController = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        // Tuck back up, quicker than the arrival, same as the dropdown:
        // leaving should feel lighter than arriving.
        let final = panel.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.panelTuck
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !Motion.reduced {
                panel.animator().setFrame(final.offsetBy(dx: 0, dy: 6), display: true)
            }
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

/// One line on slate: the bar's current face at reduced ink, the words at
/// full strength. The face is expressive to the eye and noise to a screen
/// reader, so accessibility hears only the words, and it hears them, unlike
/// the face flash, because these are words.
private struct BubbleView: View {
    let face: String?
    let text: String
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let face, !face.isEmpty {
                Text(face)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(Ink.muted))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(nsColor: TerminalTheme.foreground))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: TerminalTheme.background))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(Ink.edge))
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(14)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rin: \(text)")
    }
}
