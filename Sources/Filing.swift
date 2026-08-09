// a conversation becomes a note in the brain
// the transcript is already on disk and the brain is already the working folder
// no competitor has a reason to build this which is exactly why it exists

import Foundation

/// Files a tab's conversation into the brain's inbox as a Markdown note,
/// frontmatter and all. Only the words go: prompts the person typed and the
/// answers they got back. Tool calls, tool results, hook noise and thinking
/// all stay out, the same way the tab-title reader skips them, because the
/// note is the conversation as a person remembers it, not the machinery
/// underneath.
enum Filing {
    /// Writes the note and returns its path relative to the brain, or nil
    /// when there is no conversation on disk worth filing.
    static func fileConversation(for session: TerminalSession) -> String? {
        let transcript = URL(fileURLWithPath: AppConfig.transcriptPath(for: session.id))
        guard let data = try? Data(contentsOf: transcript), !data.isEmpty else { return nil }

        var turns: [(speaker: String, text: String)] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String,
                  let message = object["message"] as? [String: Any]
            else { continue }
            switch type {
            case "user":
                var text: String?
                if let string = message["content"] as? String {
                    text = string
                } else if let parts = message["content"] as? [[String: Any]] {
                    text = parts.filter { $0["type"] as? String == "text" }
                        .compactMap { $0["text"] as? String }
                        .joined(separator: "\n\n")
                }
                guard let spoken = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      isSpoken(spoken)
                else { continue }
                turns.append(("You", spoken))
            case "assistant":
                guard let parts = message["content"] as? [[String: Any]] else { continue }
                let text = parts.filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // A turn lands a piece at a time, one message per piece;
                // merged here so the note reads as an answer, not a stutter.
                if let last = turns.last, last.speaker == "Claude" {
                    turns[turns.count - 1].text += "\n\n" + text
                } else {
                    turns.append(("Claude", text))
                }
            default:
                continue
            }
        }
        guard !turns.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())

        // His name for the tab beats a title the terminal invented; failing
        // both, the first thing anyone said is what the conversation was.
        let heading = session.customLabel
            ?? firstLine(of: turns.first(where: { $0.speaker == "You" })?.text ?? session.title)

        var note = """
        ---
        type: note
        date: \(day)
        status: inbox
        tags: [conversation]
        source: rin tab, session \(session.id.uuidString.lowercased())
        ---

        # \(heading)

        """
        for turn in turns {
            note += "\n**\(turn.speaker):**\n\n\(turn.text)\n"
        }

        let inbox = URL(fileURLWithPath: AppConfig.workingDirectory)
            .appendingPathComponent("00-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let base = "\(day)-\(slug(heading))"
        var target = inbox.appendingPathComponent(base + ".md")
        var copy = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = inbox.appendingPathComponent("\(base)-\(copy).md")
            copy += 1
        }
        guard (try? note.write(to: target, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        return "00-inbox/" + target.lastPathComponent
    }

    /// Hook output, tool results and interruption markers ride the user role
    /// too; anything bracketed is machinery, not a person.
    private static func isSpoken(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("<") && !text.hasPrefix("[") && !text.hasPrefix("Caveat:")
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(60)) + "..." : line
    }

    private static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "conversation" : String(collapsed.prefix(40))
    }
}
