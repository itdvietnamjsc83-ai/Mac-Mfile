import AppKit
import MfileCore
import UniformTypeIdentifiers

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

    /// Phông giao diện như Windows 11: Segoe UI nếu máy đã cài; nếu không thì Open Sans đóng kèm
    /// (cùng tác giả Steve Matteson, dáng chữ gần Segoe, đủ dấu tiếng Việt, giấy phép OFL); cuối cùng là phông hệ thống.
    static func font(_ size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        FluentIcons.register()
        let semibold = weight != .regular
        if let f = NSFont(name: semibold ? "Segoe UI Semibold" : "Segoe UI", size: size) { return f }
        // Open Sans có chiều cao chữ thường lớn hơn Segoe; thu nhỏ 5% để cột chữ cân như bản Windows.
        if let f = NSFont(name: semibold ? "OpenSansRoman-SemiBold" : "OpenSansRoman-Regular", size: (size * 0.95).rounded(.toNearestOrEven)) { return f }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Biểu tượng kiểu Windows 11: vẽ từ phông Fluent UI System Icons (MIT, Microsoft) đóng kèm app;
    /// tên nào chưa có glyph thì lùi về SF Symbols.
    static func symbol(_ name: String, size: CGFloat = 14) -> NSImage? {
        if let img = FluentIcons.image(name, size: size) { return img }
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
    /// Khoảng đệm hai bên (tổng), mặc định 16 như thanh lệnh; thanh địa chỉ dùng nhỏ hơn cho xích lại.
    var horizontalPadding: CGFloat = 16 { didSet { invalidateIntrinsicContentSize() } }

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
        return NSSize(width: s.width + horizontalPadding, height: 32)
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

/// Phông biểu tượng Fluent (bản rút gọn chỉ gồm các glyph app dùng) trong Contents/Resources/Fonts.
enum FluentIcons {
    static let fontName = "FluentSystemIcons-Regular"
    /// Tên SF Symbol → mã glyph ic_fluent_*_20_regular.
    static let glyphs: [String: UInt32] = [
        "arrow.clockwise": 0xF13D,
        "arrow.counterclockwise": 0xF13F,
        "arrow.left": 0xF15B,
        "arrow.right": 0xF181,
        "arrow.up": 0xF19B,
        "arrow.up.arrow.down": 0xF18A,
        "character.cursor.ibeam": 0xF669,
        "chevron.down": 0xF2A3,
        "chevron.right": 0xF2B0,
        "cloud.fill": 0xF2E4,
        "desktopcomputer": 0xF359,
        "doc": 0xF378,
        "doc.on.clipboard": 0xF2D5,
        "doc.on.doc": 0xF32B,
        "ellipsis": 0xE824,
        "externaldrive": 0xE6E3,
        "eye": 0xE5F2,
        "eye.slash": 0xE5F5,
        "folder.fill": 0xF418,
        "gearshape": 0xF6A9,
        "house": 0xF480,
        "info.circle": 0xF4A3,
        "line.3.horizontal.decrease": 0xF406,
        "list.bullet": 0xECD9,
        "lock.fill": 0xE78F,
        "magnifyingglass": 0xF68F,
        "moon": 0xF87D,
        "network": 0xF45A,
        "photo": 0xF488,
        "pin": 0xF601,
        "plus": 0xF109,
        "plus.circle.fill": 0xF10C,
        "questionmark.circle": 0xF63D,
        "scissors": 0xF33A,
        "sidebar.right": 0xE8BD,
        "square.and.arrow.up": 0xF6AF,
        "square.grid.2x2": 0xF462,
        "star": 0xF70F,
        "sun.max": 0xF8A1,
        "trash": 0xF34C,
        "xmark": 0xF369,
    ]
    private static var registered = false
    private static var cache: [String: NSImage] = [:]

    /// Gọi một lần lúc khởi động; đăng ký mọi phông trong Resources/Fonts (cả Selawik nếu bản build có).
    static func register() {
        guard !registered else { return }
        registered = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    static func image(_ name: String, size: CGFloat) -> NSImage? {
        guard let code = glyphs[name], let scalar = Unicode.Scalar(code) else { return nil }
        register()
        let key = "\(name)@\(size)"
        if let c = cache[key] { return c }
        // Glyph Fluent 20px vẽ đầy khung em; cỡ phông lớn hơn cỡ SF một chút để cân thị giác.
        guard let font = NSFont(name: fontName, size: size * 1.15) else { return nil }
        let str = NSAttributedString(string: String(Character(scalar)), attributes: [.font: font, .foregroundColor: NSColor.black])
        let box = NSSize(width: ceil(size * 1.15), height: ceil(size * 1.15))
        let img = NSImage(size: box, flipped: false) { rect in
            let b = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
            str.draw(at: NSPoint(x: (rect.width - b.width) / 2, y: (rect.height - b.height) / 2))
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = name
        cache[key] = img
        return img
    }
}

/// Biểu tượng thư mục và tệp kiểu Windows 11, lấy từ bộ Fluent Emoji của Microsoft (MIT) đóng kèm trong Resources/Icons.
/// Ứng dụng (.app) và ổ đĩa vẫn dùng biểu tượng của macOS.
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func named(_ name: String) -> NSImage? {
        if let c = cache[name] { return c }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(name).pdf"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }

    static func kind(of path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return "page_facing_up" }
        if isDir.boolValue {
            if ["app", "bundle", "framework", "photoslibrary", "rtfd", "pages", "numbers", "key"].contains(ext) { return nil }
            if let v = try? url.resourceValues(forKeys: [.isVolumeKey]), v.isVolume == true { return nil }
            return "file_folder"
        }
        guard let t = UTType(filenameExtension: ext) else { return "page_facing_up" }
        if t.conforms(to: .image) { return "framed_picture" }
        if t.conforms(to: .audio) { return "musical_note" }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return "film_frames" }
        if t.conforms(to: .archive) || ["zip", "rar", "7z", "gz", "tgz", "bz2", "xz", "tar", "dmg"].contains(ext) { return "package" }
        // Tệp có biểu tượng riêng của ứng dụng (Word, Excel, PDF…) giữ biểu tượng hệ thống như Windows.
        if t.conforms(to: .plainText) || t.conforms(to: .sourceCode) || ["log", "md", "csv", "json", "xml", "ini", "cfg"].contains(ext) { return "page_facing_up" }
        return nil
    }

    /// Bản nhỏ có màu cho ngăn điều hướng, thanh địa chỉ (thay glyph đơn sắc như Windows 11).
    static func small(_ symbol: String, size: CGFloat) -> NSImage? {
        let map = ["folder.fill": "file_folder", "folder": "file_folder", "desktopcomputer": "desktop_computer"]
        guard let n = map[symbol], let img = named(n)?.copy() as? NSImage else { return nil }
        img.size = NSSize(width: size, height: size)
        return img
    }

    /// Biểu tượng cho một đường dẫn: kiểu Windows nếu có, không thì của macOS.
    static func icon(for path: String) -> NSImage {
        // Trang chủ và Máy Mac này không phải đường dẫn thật: dùng biểu tượng riêng như tab của Windows 11.
        if path == SpecialLocation.home { return Theme.symbol("house", size: 16) ?? NSImage() }
        if path == SpecialLocation.thisMac { return named("desktop_computer") ?? NSImage() }
        if let k = kind(of: path), let img = named(k) { return img }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
