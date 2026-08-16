import Carbon.HIToolbox
import Foundation

/// Translates between the modifier masks AppKit reports and the ones Carbon's
/// hotkey API takes, and renders a shortcut the way a menu would.
enum KeyCombo {
    static func carbonModifiers(from cocoa: UInt) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoa & (1 << 20) != 0 { carbon |= UInt32(cmdKey) }
        if cocoa & (1 << 19) != 0 { carbon |= UInt32(optionKey) }
        if cocoa & (1 << 18) != 0 { carbon |= UInt32(controlKey) }
        if cocoa & (1 << 17) != 0 { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func description(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let named = namedKeys[keyCode] { return named }
        return characters(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what the key produces, so a hotkey
    /// reads the same as the key the user actually pressed.
    private static func characters(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, characters.count, &length, &characters)
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    private static let namedKeys: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_Escape): "⎋", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_Keypad0): "Num 0", UInt32(kVK_ANSI_Keypad1): "Num 1",
        UInt32(kVK_ANSI_Keypad2): "Num 2", UInt32(kVK_ANSI_Keypad3): "Num 3",
        UInt32(kVK_ANSI_Keypad4): "Num 4", UInt32(kVK_ANSI_Keypad5): "Num 5",
        UInt32(kVK_ANSI_Keypad6): "Num 6", UInt32(kVK_ANSI_Keypad7): "Num 7",
        UInt32(kVK_ANSI_Keypad8): "Num 8", UInt32(kVK_ANSI_Keypad9): "Num 9"
    ]
}
