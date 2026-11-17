import AppKit
import MfileCore

/// Ô sửa tên ngay trên mục, như F2 hoặc bấm chậm lần hai trong File Explorer:
/// chọn sẵn phần tên (không gồm đuôi), Enter lưu, Esc hủy, bấm ra ngoài thì lưu,
/// gõ / hoặc : thì bỏ ký tự đó và hiện lời nhắc nhỏ ngay dưới ô.
final class InlineRenameEditor: NSObject, NSTextFieldDelegate {
    enum Outcome { case commit(String), cancel }

    let path: String
    private let field = RenameField()
    private weak var host: NSView?
    private var finished = false
    private var tip: NSPopover?
    private let onEnd: (Outcome) -> Void

    init(path: String, text: String, selectLength: Int, frame: NSRect, in host: NSView,
         multiline: Bool, onEnd: @escaping (Outcome) -> Void) {
        self.path = path
        self.host = host
        self.onEnd = onEnd
        super.init()
        field.stringValue = text
        field.font = Theme.font(12)
        field.textColor = Theme.text
        field.backgroundColor = Theme.background
        field.drawsBackground = true
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.borderColor = Theme.accent.cgColor
        field.layer?.borderWidth = 1
        // Nằm trên các hàng/ô vẽ sau (bảng và lưới thêm hàng mới khi cuộn).
        field.layer?.zPosition = 100
        field.alignment = multiline ? .center : .left
        if multiline {
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.usesSingleLineMode = false
            field.maximumNumberOfLines = 0
        } else {
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.usesSingleLineMode = true
        }
        field.delegate = self
        field.frame = frame
        host.addSubview(field, positioned: .above, relativeTo: nil)
        host.window?.makeFirstResponder(field)
        let len = min(max(0, selectLength), (text as NSString).length)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: len)
    }

    /// Hủy từ bên ngoài (chuyển thư mục, đổi chế độ xem…).
    func cancel() { finish(.cancel, refocus: false) }

    private func finish(_ outcome: Outcome, refocus: Bool) {
        guard !finished else { return }
        finished = true
        tip?.close()
        tip = nil
        field.delegate = nil
        if refocus, let host { host.window?.makeFirstResponder(host) }
        // Gỡ ô sau khi AppKit xử lý xong việc kết thúc sửa (có thể đang ở giữa thông báo mất tiêu điểm).
        field.isHidden = true
        let f = field
        DispatchQueue.main.async { f.removeFromSuperview() }
        onEnd(outcome)
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            finish(.commit(field.stringValue), refocus: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(.cancel, refocus: true)
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        let (clean, removed) = FileNaming.stripForbidden(field.stringValue)
        guard removed else { return }
        let editor = field.currentEditor()
        let caret = editor?.selectedRange.location ?? (clean as NSString).length
        field.stringValue = clean
        editor?.selectedRange = NSRange(location: min(caret, (clean as NSString).length), length: 0)
        NSSound.beep()
        showTip(L10n.t("renameBadChars"))
    }

    /// Bấm ra ngoài (ô mất tiêu điểm) thì lưu, như Windows.
    func controlTextDidEndEditing(_ obj: Notification) {
        finish(.commit(field.stringValue), refocus: false)
    }

    private func showTip(_ text: String) {
        tip?.close()
        let vc = NSViewController()
        let l = label(text)
        l.translatesAutoresizingMaskIntoConstraints = true
        l.sizeToFit()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: l.frame.width + 20, height: l.frame.height + 12))
        l.frame.origin = NSPoint(x: 10, y: 6)
        box.addSubview(l)
        vc.view = box
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .applicationDefined
        p.animates = false
        p.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY)
        tip = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak p] in
            guard let p, self?.tip === p else { return }
            p.close()
        }
    }
}

/// Ô nhập của trình đổi tên; chữ canh giữa theo chiều dọc ở chế độ một dòng.
final class RenameField: NSTextField {
    override class var cellClass: AnyClass? {
        get { RenameFieldCell.self }
        set {}
    }
}

private final class RenameFieldCell: NSTextFieldCell {
    private func centered(_ r: NSRect) -> NSRect {
        guard !wraps else { return r.insetBy(dx: 2, dy: 1) }
        let h = cellSize(forBounds: r).height
        var o = r.insetBy(dx: 3, dy: 0)
        o.origin.y += max(0, (r.height - h) / 2)
        o.size.height = min(h, r.height)
        return o
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect { super.drawingRect(forBounds: centered(rect)) }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// Nhận biết "bấm chậm lần hai" trên tên mục đang được chọn riêng (như File Explorer):
/// bấm lại vào tên mục đã chọn, rồi không bấm tiếp trong khoảng thời gian bấm đúp của hệ thống thì vào sửa tên.
/// Bấm đúp nhanh vẫn là mở.
final class SlowClickRenamer {
    private var timer: Timer?
    /// Đã thỏa điều kiện trước khi lớp bảng/lưới xử lý cú bấm.
    private var armed = false
    private var downPoint = NSPoint.zero

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    /// Gọi ở đầu mouseDown, trước super. `onName`: cú bấm nằm trên chữ tên của mục đã chọn riêng từ trước.
    func mouseDown(_ event: NSEvent, in view: NSView, onName: Bool) {
        cancel()
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        armed = event.clickCount == 1 && flags.isEmpty && onName
            && view.window?.isKeyWindow == true && view.window?.firstResponder === view
        downPoint = event.locationInWindow
    }

    /// Gọi sau super.mouseDown (lúc đó chuột đã nhả, hoặc đang kéo thả).
    func mouseDownFinished(fire: @escaping () -> Void) {
        guard armed else { return }
        armed = false
        // Kéo thả thì không đổi tên: chỉ tính khi sự kiện cuối là nhả chuột gần chỗ bấm.
        guard let up = NSApp.currentEvent, up.type == .leftMouseUp,
              hypot(up.locationInWindow.x - downPoint.x, up.locationInWindow.y - downPoint.y) < 5 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
            self?.timer = nil
            fire()
        }
    }
}
