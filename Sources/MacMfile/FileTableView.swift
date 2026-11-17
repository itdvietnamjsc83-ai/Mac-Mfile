import AppKit

/// Bảng Chi tiết nhận phím kiểu Windows (Mục 5.6, 5.9).
final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onTrash: (() -> Void)?
    var onDeleteForever: (() -> Void)?
    var onRename: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onProperties: (() -> Void)?
    var onBack: (() -> Void)?
    /// Bấm chậm lần hai lên tên mục đang chọn: đổi tên tại chỗ (đối số là số hàng).
    var onSlowClickRename: ((Int) -> Void)?
    let slowClick = SlowClickRenamer()

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = row(at: p)
        let onName = row >= 0 && selectedRowIndexes == IndexSet(integer: row) && isOnNameText(p, row: row)
        slowClick.mouseDown(event, in: self, onName: onName)
        super.mouseDown(with: event)
        slowClick.mouseDownFinished { [weak self] in
            guard let self, self.selectedRowIndexes == IndexSet(integer: row) else { return }
            self.onSlowClickRename?(row)
        }
    }

    /// Như Windows: chỉ bấm lên chữ tên mới vào sửa, bấm lên biểu tượng hay chỗ trống thì không.
    private func isOnNameText(_ p: NSPoint, row: Int) -> Bool {
        let col = column(at: p)
        guard col >= 0, tableColumns[col].identifier.rawValue == "name",
              let cell = view(atColumn: col, row: row, makeIfNecessary: false) as? NSTableCellView,
              let tf = cell.textField else { return false }
        let r = tf.convert(tf.bounds, to: self)
        let w = min(r.width, tf.intrinsicContentSize.width)
        return p.x >= r.minX - 2 && p.x <= r.minX + w + 4
    }

    override func keyDown(with event: NSEvent) {
        slowClick.cancel()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76: // Return, Enter: mở; Option+Enter: Thuộc tính (Alt+Enter của Windows)
            if flags.contains(.option) { onProperties?() } else { onOpen?() }
        case 51, 117:
            switch DeleteKeys.action(keyCode: event.keyCode, flags: flags) {
            case .back: onBack?()
            case .trash: onTrash?()
            case .deleteForever: onDeleteForever?()
            case .none: super.keyDown(with: event)
            }
        case 120: // F2: đổi tên
            onRename?()
        case 49 where flags.isEmpty: // Space: xem nhanh
            onQuickLook?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// Phím xóa (Mục 5.6): mặc định ⌫ chuyển vào Thùng rác (Dũng chọn 11/11/2026), Delete / fn+delete / Cmd+⌫ cũng vậy,
/// Shift+Delete xóa vĩnh viễn. Đổi được trong Tùy chọn: ⌫ quay lại như Backspace của Windows.
enum DeleteKeys {
    enum Action { case back, trash, deleteForever, none }
    static let backspaceBackKey = "MacMfile.backspaceGoesBack"

    static var backspaceGoesBack: Bool {
        get { UserDefaults.standard.object(forKey: backspaceBackKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: backspaceBackKey) }
    }

    static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Action {
        let f = flags.intersection([.command, .shift, .option, .control])
        let forward = keyCode == 117
        if f.contains(.shift) || f == [.command, .option] { return .deleteForever }
        if f == .command { return .trash }
        guard f.isEmpty else { return .none }
        if forward { return .trash }
        return backspaceGoesBack ? .back : .trash
    }
}
