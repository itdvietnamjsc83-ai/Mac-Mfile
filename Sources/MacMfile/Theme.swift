import AppKit

/// Màu, phông, kích thước đo theo Windows 11 File Explorer (Mục 2.3, bản mẫu đã duyệt).
enum Theme {
    /// Màu theo giao diện Sáng/Tối của Windows 11 (bản mẫu bảng 1 và 28).
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func c(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        let l = c(light), d = c(dark)
        return NSColor(name: nil) { ap in ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
    }
    static let accent = dyn(0x005fb8, 0x4cc2ff)
    static let tabStrip = dyn(0xe8e8e8, 0x1a1a1a)
    static let chrome = dyn(0xf9f9f9, 0x202020)
    static let background = dyn(0xffffff, 0x1c1c1c)
    static let border = dyn(0xe5e5e5, 0x333333)
    static let selection = dyn(0xcce4f7, 0x0e3a5c)
    static let hover = dyn(0xf2f2f2, 0x2d2d2d)
    static let secondaryText = dyn(0x6b6b6b, 0xa8a8a8)
    static let text = dyn(0x1a1a1a, 0xffffff)
    static let closeHover = NSColor(srgbRed: 0xc4 / 255, green: 0x2b / 255, blue: 0x1c / 255, alpha: 1)

    /// Sáng / Tối / Theo hệ thống; nút ☀/☾ ở thanh trạng thái đổi nhanh (Cmd+Shift+L).
    enum Appearance: String { case system, light, dark }
    static let appearanceKey = "MacMfile.appearance"
    static var appearance: Appearance {
        get { Appearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey); apply() }
    }
    static func apply() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NotificationCenter.default.post(name: appearanceChanged, object: nil)
    }
    static let appearanceChanged = Notification.Name("MacMfile.appearanceChanged")
    static var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    static func toggleAppearance() { appearance = isDark ? .light : .dark }

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
    var hoverColor = Theme.hover
    private var hovering = false { didSet { needsDisplay = true } }
    private var area: NSTrackingArea?
    private(set) var fixedHeight: NSLayoutConstraint!
    /// Nút bật/tắt đang chọn (như nút Chi tiết/Biểu tượng lớn ở thanh trạng thái Windows).
    var isActive = false { didSet { needsDisplay = true } }

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
        fixedHeight = heightAnchor.constraint(equalToConstant: 32)
        fixedHeight.isActive = true
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
        if isActive {
            Theme.selection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        } else if hovering && isEnabled {
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
