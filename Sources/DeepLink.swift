// the rin links from the website
// one verb only and the name gets checked before anything happens
// a web page should never be able to start something on your mac without you saying yes first

import AppKit
import Foundation

/// The one URL Rin answers to: `rin://install/<module>`.
///
/// Modules are not a screen in this app (Peter's call, 2026-08-04). Browsing
/// happens on the modules page, installing happens in a tab, the assistant
/// runs the command, reads out what the module can do, and writes the folder.
/// This is the handoff between the two, and it is the same handoff Raycast's
/// web store makes: the page cannot install anything, it can only ask the app
/// to open on the subject.
///
/// Three rules keep a link from a web page honest:
///
/// - **Only one verb exists.** Anything that is not `install` is dropped. There
///   is no URL that runs a command, opens a folder, or types text.
/// - **The name is checked, never carried through.** Lowercase letters, digits
///   and hyphens, and the prompt is built here out of that name. Nothing from
///   the URL reaches the terminal as text.
/// - **A person confirms.** A page can raise the question; only the person in
///   front of the Mac answers it, and then the assistant asks again before it
///   writes anything.
enum DeepLink {
    /// The module named by a `rin://install/<name>` URL, or nil for anything
    /// else. Trailing slashes and a `rin:install/<name>` spelling both land.
    static func moduleToInstall(in url: URL) -> String? {
        guard url.scheme?.lowercased() == "rin" else { return nil }
        var parts = (url.host.map { [$0] } ?? []) + url.path.split(separator: "/").map(String.init)
        // rin:install/name has no host, so the verb arrives in the path.
        if parts.isEmpty, !url.absoluteString.isEmpty {
            parts = url.absoluteString
                .replacingOccurrences(of: "rin:", with: "")
                .split(separator: "/").map(String.init)
        }
        guard parts.count == 2, parts[0].lowercased() == "install" else { return nil }
        let name = parts[1]
        guard !name.isEmpty, name.count <= 64,
              name.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-" || ($0.isLetter && $0.isLowercase)) }),
              name.first != "-", name.last != "-"
        else { return nil }
        return name
    }

    /// What the tab opens with. Fixed wording assembled here, so the URL
    /// supplies a name and never a sentence.
    static func prompt(forInstalling name: String) -> String {
        "/install \(name)"
    }
}
