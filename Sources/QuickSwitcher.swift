// jump to a tab by typing a few letters of its name
// starts mattering at five tabs which the tab restore actively encourages

import SwiftUI

/// The quick switcher (Cmd-K): a small overlay that jumps to a tab by a few
/// typed letters of its label. Arrow keys move the highlight, Return goes,
/// Escape leaves everything exactly as it was. Opaque on purpose: it sits
/// over text, and glass over text you have to read is just worse.
struct QuickSwitcher: View {
    @ObservedObject var store: SessionStore
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var focused: Bool

    private var matches: [TerminalSession] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.displayTitle.lowercased().contains(needle) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // A veil, so the switcher reads as ABOVE the conversation and a
            // click anywhere that is not it puts things back untouched.
            Color.black.opacity(0.25)
                .onTapGesture { store.isSwitching = false }
            VStack(spacing: 0) {
                TextField("jump to a tab", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    // The highlight and the caret carry focus; the system's
                    // grey ring stays off (2026-08-09, the ring purge).
                    .focusEffectDisabled()
                    .focused($focused)
                    .onSubmit { jump() }
                    .onExitCommand { store.isSwitching = false }
                    .onMoveCommand { direction in
                        switch direction {
                        case .down: picked = min(picked + 1, max(shown.count - 1, 0))
                        case .up: picked = max(picked - 1, 0)
                        default: break
                        }
                    }
                    .onChange(of: query) { _, _ in picked = 0 }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                if shown.isEmpty {
                    Text("no tab called that")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 9)
                } else {
                    // Real buttons rather than tap gestures, so the rows
                    // exist for VoiceOver and press like everything else.
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                        Button(action: {
                            picked = index
                            jump()
                        }) {
                            row(session, highlighted: index == picked)
                        }
                        .buttonStyle(.plain)
                        // The pointer and the arrow keys drive ONE
                        // highlight: a hover moves it, so what is lit
                        // is always what Return would choose.
                        .onHover { inside in
                            if inside { picked = index }
                        }
                    }
                    .padding(.bottom, 5)
                }
            }
            .frame(width: 300)
            .background(Color(nsColor: TerminalTheme.bar), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.primary.opacity(Ink.edge), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            .padding(.top, 36)
            // Arrives like a thing set down, not a thing switched on.
            // Reduce Motion keeps the fade and drops the settle.
            .transition(
                Motion.reduced
                    ? .opacity
                    : .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
            )
            .onAppear { focused = true }
        }
        // A tab chosen any other way while the switcher is up (a chip, Cmd-1)
        // answers the switcher's question; it leaves rather than hanging
        // stale over the tab it was not asked about.
        .onChange(of: store.activeID) { _, _ in store.isSwitching = false }
    }

    /// The list stays a glance, not a scroll: a switcher that needs its own
    /// scrolling has failed at its one job.
    private var shown: [TerminalSession] {
        Array(matches.prefix(8))
    }

    private func row(_ session: TerminalSession, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(session.displayTitle)
                .font(.system(size: 11, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let number = store.sessions.firstIndex(where: { $0.id == session.id }), number < 9 {
                Text("⌘\(number + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(Ink.dim))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.primary.opacity(highlighted ? Ink.hover : 0))
        .contentShape(Rectangle())
    }

    private func jump() {
        // Return with nothing under it does nothing, the way Spotlight
        // does: the query stays for another try, Escape is the way out.
        guard shown.indices.contains(picked) else { return }
        // The tap belongs to a tab actually changing; jumping to the tab
        // already on screen is an answer, not a switch.
        if store.activeID != shown[picked].id {
            store.activeID = shown[picked].id
            Haptics.tap()
        }
        store.isSwitching = false
    }
}
