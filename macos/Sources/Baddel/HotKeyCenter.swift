import Carbon.HIToolbox
import Foundation

/// Registers one system-wide hot key with `RegisterEventHotKey`.
///
/// The system delivers an event only when the registered combination is
/// pressed or released. Baddel installs no event tap and no key-down monitor,
/// so it never sees ordinary typing.
final class HotKeyCenter {
    /// `isRepeat` is true for a press that arrives without a release since the
    /// previous press (a held key).
    var onPress: ((_ isRepeat: Bool) -> Void)?
    var onRelease: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var isDown = false

    init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            center.handle(kind: GetEventKind(event))
            return noErr
        }, specs.count, &specs, context, &handler)
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    private func handle(kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed) {
            let isRepeat = isDown
            isDown = true
            onPress?(isRepeat)
        } else if kind == UInt32(kEventHotKeyReleased) {
            isDown = false
            onRelease?()
        }
    }

    /// - Returns: `false` if the system refused the combination, for example
    ///   because another app already registered it.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4244_4C31), id: 1)  // 'BDL1'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        hotKey = reference
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isDown = false
    }

    var isRegistered: Bool { hotKey != nil }
}
