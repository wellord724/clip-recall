import Carbon.HIToolbox
import Foundation

@MainActor
final class HotKeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var callbackContext: UnsafeMutableRawPointer?

    func stop() {
        unregisterAll()
    }

    func register(
        openPanelShortcut: ShortcutBinding,
        toggleCollectionShortcut: ShortcutBinding,
        pasteSequenceShortcut: ShortcutBinding,
        openPanel: @escaping () -> Void,
        toggleCollection: @escaping () -> Void,
        pasteSequence: @escaping () -> Void
    ) {
        unregisterAll()
        actions = [
            1: openPanel,
            2: toggleCollection,
            3: pasteSequence
        ]

        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        callbackContext = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            [eventSpec],
            callbackContext,
            &eventHandler
        )

        register(binding: openPanelShortcut, id: 1)
        register(binding: toggleCollectionShortcut, id: 2)
        register(binding: pasteSequenceShortcut, id: 3)
    }

    private func register(binding: ShortcutBinding, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: 0x434C4950, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { return }
        hotKeyRefs.append(hotKeyRef)
    }

    private func unregisterAll() {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        callbackContext = nil
    }

    fileprivate func performAction(id: UInt32) {
        actions[id]?()
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.performAction(id: hotKeyID.id)
    }
    return noErr
}
