import AppKit
import Carbon.HIToolbox

/// Phím tắt toàn hệ thống (mặc định Cmd+E, giống Windows+E; FR-40, Mục 5.7).
/// Dùng RegisterEventHotKey: không cần quyền Trợ năng, chạy được trong App Sandbox.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    /// keyCode theo Carbon (ví dụ kVK_ANSI_E), modifiers theo Carbon (cmdKey, optionKey, controlKey, shiftKey).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let target = GlobalHotKey.instances[hk.id] {
                DispatchQueue.main.async { target.action() }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D464C45), id: id) // "MFLE"
        let reg = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard reg == noErr else {
            if let h = handler { RemoveEventHandler(h) }
            return nil
        }
        GlobalHotKey.instances[id] = self
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
        GlobalHotKey.instances[id] = nil
    }
}
