import AppKit
import Carbon.HIToolbox

/// Registers the configured shortcuts with the system so they fire while EVE
/// has focus. Carbon's hotkey API is used because it needs no Accessibility
/// grant and never sees keystrokes it was not registered for.
@MainActor
final class HotkeyManager {
    nonisolated static let signature: OSType = 0x4556_4150 // 'EVAP'

    var onAction: ((HotkeyAction) -> Void)?
    /// Also claim the shortcut with further modifiers held, so a key the game
    /// uses with Ctrl or Alt still reaches this app.
    var allowsExtraModifiers = false
    private(set) var isSuspended = false

    private var registered: [UInt32: (ref: EventHotKeyRef, action: HotkeyAction)] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    static private(set) weak var current: HotkeyManager?

    init() {
        HotkeyManager.current = self
        installHandler()
    }

    func apply(_ hotkeys: [Hotkey]) {
        unregisterAll()
        for hotkey in hotkeys where hotkey.keyCode != 0 {
            register(hotkey)
        }
    }

    func suspend() { isSuspended = true }
    func resume() { isSuspended = false }
    func toggleSuspended() { isSuspended.toggle() }

    fileprivate func fire(id: UInt32) {
        guard !isSuspended, let entry = registered[id] else { return }
        onAction?(entry.action)
    }

    private func register(_ hotkey: Hotkey) {
        for modifiers in variants(of: hotkey.modifiers) {
            claim(keyCode: hotkey.keyCode, modifiers: modifiers, action: hotkey.action,
                  reportFailure: modifiers == hotkey.modifiers)
        }
    }

    /// The combination as configured, plus the ones with extra modifiers when
    /// the wildcard setting is on.
    private func variants(of modifiers: UInt32) -> [UInt32] {
        guard allowsExtraModifiers else { return [modifiers] }
        let extras: [UInt32] = [UInt32(cmdKey), UInt32(optionKey),
                                UInt32(controlKey), UInt32(shiftKey)]
            .filter { modifiers & $0 == 0 }

        var combinations: [UInt32] = [modifiers]
        for mask in 1..<(1 << extras.count) {
            var combined = modifiers
            for (index, extra) in extras.enumerated() where mask & (1 << index) != 0 {
                combined |= extra
            }
            combinations.append(combined)
        }
        return combinations
    }

    /// A wildcard variant often collides with a shortcut another application
    /// already holds, which is expected rather than an error worth reporting.
    private func claim(keyCode: UInt32, modifiers: UInt32, action: HotkeyAction,
                       reportFailure: Bool) {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            if reportFailure {
                Log.error("cannot register hotkey \(KeyCombo.description(keyCode: keyCode, modifiers: modifiers)): OSStatus \(status)")
            }
            return
        }
        registered[id] = (ref, action)
    }

    private func unregisterAll() {
        for entry in registered.values {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventHandler, 1, &spec, nil, &handler)
    }
}

/// Carbon hands events to a plain C function, so the press is routed back to the
/// single live manager.
private func hotkeyEventHandler(_ callRef: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ context: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == HotkeyManager.signature else { return status }

    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HotkeyManager.current?.fire(id: id)
    }
    return noErr
}
