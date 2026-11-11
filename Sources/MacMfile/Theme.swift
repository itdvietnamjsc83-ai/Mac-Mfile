import AppKit

/// Màu, phông, kích thước đo theo Windows 11 File Explorer (Mục 2.3, bản mẫu đã duyệt).
enum Theme {
    static let accent = NSColor(srgbRed: 0x00 / 255, green: 0x5f / 255, blue: 0xb8 / 255, alpha: 1)
    static let tabStrip = NSColor(srgbRed: 0xe8 / 255, green: 0xe8 / 255, blue: 0xe8 / 255, alpha: 1)
    static let chrome = NSColor(srgbRed: 0xf9 / 255, green: 0xf9 / 255, blue: 0xf9 / 255, alpha: 1)
    static let border = NSColor(srgbRed: 0xe5 / 255, green: 0xe5 / 255, blue: 0xe5 / 255, alpha: 1)
    static let selection = NSColor(srgbRed: 0xcc / 255, green: 0xe4 / 255, blue: 0xf7 / 255, alpha: 1)
    static let secondaryText = NSColor(srgbRed: 0x6b / 255, green: 0x6b / 255, blue: 0x6b / 255, alpha: 1)
    static let text = NSColor(srgbRed: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255, alpha: 1)
    static let closeHover = NSColor(srgbRed: 0xc4 / 255, green: 0x2b / 255, blue: 0x1c / 255, alpha: 1)

    static let rowHeight: CGFloat = 32

    /// Segoe UI nếu máy đã có, nếu không thì Selawik, cuối cùng là phông hệ thống.
    static func font(_ size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        let names = weight == .regular ? ["Segoe UI", "Selawik"] : ["Segoe UI Semibold", "Selawik Semibold"]
        for n in names {
            if let f = NSFont(name: n, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func symbol(_ name: String, size: CGFloat = 14) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return img?.withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
}

/// Nền một màu cho các thanh.
class ColorView: NSView {
    var color: NSColor { didSet { needsDisplay = true } }
    var bottomBorder = false
    init(_ color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
        if bottomBorder {
            Theme.border.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }
}

/// Vùng kéo được để di chuyển cửa sổ (thay thanh tiêu đề macOS).
final class DragView: ColorView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { super.mouseUp(with: event) }
    }
}

/// Nút phẳng kiểu thanh lệnh Windows 11: đổi nền khi di chuột.
class FlatButton: NSButton {
    var hoverColor = NSColor(srgbRed: 0xeb / 255, green: 0xeb / 255, blue: 0xeb / 255, alpha: 1)
    private var hovering = false { didSet { needsDisplay = true } }
    private var area: NSTrackingArea?

    convenience init(title: String, symbol: String?, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        font = Theme.font(12)
        contentTintColor = Theme.text
        if let s = symbol { image = Theme.symbol(s); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        imageHugsTitle = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + 16, height: 32)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering && isEnabled {
            hoverColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}

extension NSView {
    func pin(_ sub: NSView, insets: NSEdgeInsets = .init()) {
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)
        NSLayoutConstraint.activate([
            sub.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            sub.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            sub.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            sub.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }
}

func label(_ text: String, size: CGFloat = 12, color: NSColor = Theme.text) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = Theme.font(size)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

/// Hàng biểu tượng trên cùng của menu chuột phải Windows 11 (Cắt, Sao chép, Đổi tên, Chia sẻ, Xóa).
final class ContextIconRow: NSView {
    private weak var owner: NSObject?
    private weak var parentMenu: NSMenu?
    private var actions: [Selector] = []

    init(owner: NSObject, menu: NSMenu, buttons: [(String, String, Selector)]) {
        self.owner = owner
        self.parentMenu = menu
        super.init(frame: NSRect(x: 0, y: 0, width: 12 + buttons.count * 58, height: 52))
        for (i, b) in buttons.enumerated() {
            // Nhãn dưới biểu tượng như Windows 11: "Cắt", "Sao chép"… (bỏ phần phím trong ngoặc)
            let caption = b.1.components(separatedBy: " (").first ?? b.1
            let btn = FlatButton(title: caption, symbol: b.0, target: self, action: #selector(press(_:)))
            btn.imagePosition = .imageAbove
            btn.font = Theme.font(11)
            btn.toolTip = b.1
            btn.tag = i
            btn.translatesAutoresizingMaskIntoConstraints = true
            for c in btn.constraints where c.firstAttribute == .height { btn.removeConstraint(c) }
            btn.frame = NSRect(x: 6 + i * 58, y: 2, width: 56, height: 48)
            addSubview(btn)
            actions.append(b.2)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func press(_ sender: NSButton) {
        let sel = actions[sender.tag]
        parentMenu?.cancelTracking()
        let target = owner
        DispatchQueue.main.async { _ = target?.perform(sel, with: nil) }
    }
}
