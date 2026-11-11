import AppKit

/// Bảng Chi tiết nhận phím kiểu Windows (Mục 5.6, 5.9).
final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onTrash: (() -> Void)?
    var onDeleteForever: (() -> Void)?
    var onRename: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onProperties: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76: // Return, Enter: mở; Option+Enter: Thuộc tính (Alt+Enter của Windows)
            if flags.contains(.option) { onProperties?() } else { onOpen?() }
        case 51, 117: // delete (⌫), forward delete
            if flags.contains(.shift) || flags == [.command, .option] { onDeleteForever?() }
            else if flags.isEmpty || flags == .command || flags == .function { onTrash?() }
            else { super.keyDown(with: event) }
        case 120: // F2: đổi tên
            onRename?()
        case 49 where flags.isEmpty: // Space: xem nhanh
            onQuickLook?()
        default:
            super.keyDown(with: event)
        }
    }
}
