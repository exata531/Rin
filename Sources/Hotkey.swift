// ctrl backtick from anywhere
// this is the actual point of it living in the menu bar you should never have to go find the window

import Carbon
import Foundation

/// Global hotkeys: Control+` and Control+, both toggle the panel from any app.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var callback: (() -> Void)?

    func register(_ action: @escaping () -> Void) {
        callback = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().callback?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let combos: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_Grave), UInt32(controlKey)),
            (UInt32(kVK_ANSI_Comma), UInt32(controlKey)),
        ]
        for (index, combo) in combos.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x52494E31), id: UInt32(index + 1))
            RegisterEventHotKey(combo.0, combo.1, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }
}
