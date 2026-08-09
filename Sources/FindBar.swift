// finding something said earlier without scrolling and squinting
// the terminal library does the searching this is just the bar that feeds it

import AppKit
import SwiftUI
import SwiftTerm

/// The find bar (Cmd-F): the one table-stakes terminal feature the panel
/// lacked. SwiftTerm ships the search itself, selection and scrolling
/// included, so this is a strip over the terminal that hands it a term and
/// steps the matches. Return walks forward, Shift-Return back, Escape gives
/// the keyboard back to the terminal. The search is live: the first match
/// lights up as the term is typed, and a miss says so in words instead of
/// doing nothing.
struct FindBar: View {
    @ObservedObject var store: SessionStore
    @State private var term = ""
    @State private var missed = false
    @FocusState private var focused: Bool

    private var terminal: LocalProcessTerminalView? {
        store.active?.terminalView
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("find in this tab", text: $term)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                // The caret is the field's focus indicator; the system's
                // grey ring on top of a bar this small reads as a box
                // around a box (2026-08-09, the ring purge).
                .focusEffectDisabled()
                .focused($focused)
                .onSubmit { step(forward: true) }
                .onExitCommand { close() }
                .onChange(of: term) { _, _ in seek() }
                .frame(maxWidth: 280)
            if missed, !term.isEmpty {
                Text("no matches")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Stepping with nothing typed is a step to nowhere; the
            // chevrons dim to say so before the click instead of denying
            // after it.
            icon("chevron.up", label: "Previous match", disabled: term.isEmpty) { step(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Previous match (Shift-Return)")
            icon("chevron.down", label: "Next match", disabled: term.isEmpty) { step(forward: true) }
                .keyboardShortcut("g", modifiers: .command)
                .help("Next match (Return)")
            icon("xmark", label: "Done searching", disabled: false) { close() }
                .help("Done (Escape)")
            // Shift-Return steps back the way every find bar on the Mac
            // does; a hidden control carries it because the field's submit
            // only speaks plain Return.
            Button(action: { step(forward: false) }) { EmptyView() }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .shift)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(VisualEffect(material: .headerView))
        .onAppear {
            focused = true
            // The Mac's shared find pasteboard: what was last searched in
            // Safari or TextEdit is what this bar opens holding, and what is
            // typed here follows it back out (written in seek). Standard
            // citizenship, and it also means the term survives the bar
            // closing and reopening.
            if term.isEmpty,
               let shared = NSPasteboard(name: .find).string(forType: .string),
               !shared.isEmpty {
                term = shared
            }
        }
        // Switching tabs mid-search re-runs the term against the tab now on
        // screen, so the bar never shows a verdict about the wrong terminal.
        .onChange(of: store.activeID) { _, _ in seek() }
        // Cmd-F pressed while the bar is already up means "give me the
        // field back", not nothing.
        .onChange(of: store.searchNonce) { _, _ in focused = true }
    }

    /// The bar's icon buttons: hover shows a wash, the plain style keeps the
    /// system's focus chrome away, and disabled dims instead of vanishing.
    /// Each carries its purpose in words: a symbol-only control is a shrug
    /// to a screen reader.
    private func icon(
        _ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        IconButton(symbol: symbol, label: label, disabled: disabled, action: action)
    }

    private struct IconButton: View {
        let symbol: String
        let label: String
        let disabled: Bool
        let action: () -> Void
        @State private var hovering = false
        @State private var down = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(.primary.opacity(hovering && !disabled ? Ink.hover : 0), in: Circle())
                    .contentShape(Rectangle())
            }
            // The same press every control in the bar wears: down glued to
            // the finger, release on the spring (the feel pass, 2026-08-09).
            // These three were the only buttons still answering with nothing.
            .buttonStyle(PressReporting(pressed: $down))
            .pressed(down)
            .foregroundStyle(.secondary)
            .opacity(disabled ? Ink.muted : 1)
            .disabled(disabled)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .accessibilityLabel(label)
        }
    }

    /// A fresh term starts a fresh search: the old trail is cleared so the
    /// first match found is the first match, not the next one after wherever
    /// the last term left the selection.
    private func seek() {
        guard let terminal else { return }
        terminal.clearSearch()
        guard !term.isEmpty else {
            missed = false
            return
        }
        // The term goes to the shared find pasteboard as it is searched, so
        // Cmd-F in the next app picks up where this one left off.
        let board = NSPasteboard(name: .find)
        board.clearContents()
        board.setString(term, forType: .string)
        missed = !terminal.findNext(term)
    }

    private func step(forward: Bool) {
        guard let terminal, !term.isEmpty else { return }
        let hit = forward ? terminal.findNext(term) : terminal.findPrevious(term)
        missed = !hit
        // The felt no: the step was heard and there was nowhere to go.
        if !hit { Haptics.deny() }
    }

    private func close() {
        store.isSearching = false
        guard let terminal else { return }
        terminal.clearSearch()
        terminal.window?.makeFirstResponder(terminal)
    }
}
