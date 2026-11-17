import AppKit
import MfileCore

/// Thanh địa chỉ dạng từng đoạn bấm được như Windows 11 (Mục 5.13, bản mẫu bảng 11):
/// bấm một đoạn để tới đó, bấm "›" để chọn thư mục con, bấm chỗ trống để gõ đường dẫn, "⌄" mở lịch sử địa chỉ.
final class BreadcrumbBar: NSView {
    var onNavigate: ((String) -> Void)?
    var onEdit: (() -> Void)?
    private let stack = NSStackView()
    private let overflow = FlatButton(title: "…", symbol: nil, target: nil, action: nil)
    private let historyB = FlatButton(title: "", symbol: "chevron.down", target: nil, action: nil)
    private var crumbs: [Crumb] = []

    static let historyKey = "MacMfile.addressHistory"
    static var history: [String] {
        get { UserDefaults.standard.stringArray(forKey: historyKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(20)), forKey: historyKey) }
    }
    static func remember(_ path: String) {
        var h = history.filter { $0 != path }
        h.insert(path, at: 0)
        history = h
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Đường dẫn dài không được đẩy cửa sổ giãn ra: layout() tự rút gọn các thư mục giữa vào "…".
        stack.setClippingResistancePriority(NSLayoutConstraint.Priority(200), for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        overflow.target = self; overflow.action = #selector(showOverflow(_:))
        historyB.target = self; historyB.action = #selector(showHistory(_:))
        historyB.toolTip = L10n.t("recentLocations")
        for b in [overflow, historyB] { b.fixedHeight.constant = 24 }
        overflow.horizontalPadding = 8
        addSubview(stack)
        addSubview(historyB)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: historyB.leadingAnchor, constant: -4),
            historyB.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            historyB.centerYAnchor.constraint(equalTo: centerYAnchor),
            historyB.widthAnchor.constraint(equalToConstant: 26),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }

    /// Bấm vào chỗ trống: chuyển sang gõ đường dẫn (như Windows).
    override func mouseDown(with event: NSEvent) { onEdit?() }

    /// Nhóm hiển thị: nhóm 0 là đoạn đầu; nhóm i (i ≥ 1) gồm mũi tên › và đoạn thứ i.
    private var groups: [[NSView]] = []
    private var leadingViews: [NSView] = []
    private var trailingViews: [NSView] = []
    private let overflowChev = FlatButton(title: "", symbol: nil, target: nil, action: nil)
    /// Các đoạn giữa đang bị rút gọn vào nút "…".
    private var hiddenGroups: Set<Int> = []

    private func chevron(tag: Int) -> FlatButton {
        let chev = FlatButton(title: "", symbol: nil, target: self, action: #selector(showChildren(_:)))
        chev.tag = tag
        chev.fixedHeight.constant = 24
        chev.horizontalPadding = 2
        chev.image = Theme.symbol("chevron.right", size: 10)
        chev.imagePosition = .imageOnly
        chev.toolTip = L10n.t("subfolders")
        return chev
    }

    func show(_ list: [Crumb]) {
        crumbs = list
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        groups = []; leadingViews = []; trailingViews = []; hiddenGroups = []
        let rootSymbol = list.first?.path == SpecialLocation.home ? "house" : "folder.fill"
        let icon = NSImageView(image: FileIcons.small(rootSymbol, size: 16) ?? Theme.symbol(rootSymbol) ?? NSImage())
        icon.contentTintColor = list.first?.path == SpecialLocation.home ? Theme.text : NSColor(srgbRed: 0.91, green: 0.69, blue: 0.16, alpha: 1)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        stack.addArrangedSubview(icon)
        stack.setCustomSpacing(4, after: icon)
        leadingViews = [icon]
        for (i, c) in list.enumerated() {
            var g: [NSView] = []
            if i > 0 { g.append(chevron(tag: i - 1)) }
            let b = FlatButton(title: c.title, symbol: nil, target: self, action: #selector(crumbClicked(_:)))
            b.tag = i
            b.fixedHeight.constant = 24
            b.horizontalPadding = 8
            // Quá hẹp đến mức không đủ chỗ cho đoạn đầu và đoạn cuối thì đoạn đầu co lại trước.
            let isLast = i == list.count - 1
            b.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(isLast ? 400 : 300), for: .horizontal)
            b.toolTip = SpecialLocation.isSpecial(c.path) ? c.title : c.path
            b.lineBreakMode = .byTruncatingTail
            g.append(b)
            groups.append(g)
            if i == 0 {
                g.forEach { stack.addArrangedSubview($0) }
                // Nút "…" (các thư mục giữa bị rút gọn) đứng ngay sau thư mục đầu, như Windows.
                overflowChev.image = Theme.symbol("chevron.right", size: 10)
                overflowChev.imagePosition = .imageOnly
                overflowChev.horizontalPadding = 2
                overflowChev.fixedHeight.constant = 24
                overflowChev.isEnabled = false
                stack.addArrangedSubview(overflowChev)
                stack.addArrangedSubview(overflow)
                overflowChev.isHidden = true
                overflow.isHidden = true
            } else {
                g.forEach { stack.addArrangedSubview($0) }
            }
        }
        // Mũi tên cuối: thư mục con của thư mục đang mở.
        if let last = list.last, !SpecialLocation.isSpecial(last.path) || last.path == SpecialLocation.thisMac {
            let chev = chevron(tag: list.count - 1)
            stack.addArrangedSubview(chev)
            trailingViews = [chev]
        }
        needsLayout = true
    }

    private func width(_ views: [NSView]) -> CGFloat {
        views.reduce(0) { $0 + max($1.intrinsicContentSize.width, 0) }
    }

    /// Thiếu chỗ: giữ đủ thư mục đầu và thư mục cuối, rút gọn các thư mục ở giữa (gần đầu trước) vào nút "…".
    override func layout() {
        super.layout()
        guard !groups.isEmpty else { return }
        let avail = bounds.width - 4 - 4 - 26 - 2
        let fixed = width(leadingViews) + 4 + width(groups[0]) + width(trailingViews) + (groups.count > 1 ? width(groups[groups.count - 1]) : 0)
        var total = fixed + groups.dropFirst().dropLast().reduce(0) { $0 + width($1) }
        var hide: Set<Int> = []
        if total > avail, groups.count > 2 {
            total += width([overflowChev, overflow])
            for i in 1..<(groups.count - 1) where total > avail {
                hide.insert(i)
                total -= width(groups[i])
            }
        }
        guard hide != hiddenGroups || overflow.isHidden != hide.isEmpty else { return }
        hiddenGroups = hide
        for (i, g) in groups.enumerated() { g.forEach { $0.isHidden = hide.contains(i) } }
        overflow.isHidden = hide.isEmpty
        overflowChev.isHidden = hide.isEmpty
        overflow.toolTip = hide.sorted().map { crumbs[$0].title }.joined(separator: " › ")
    }

    @objc private func crumbClicked(_ b: NSButton) {
        guard crumbs.indices.contains(b.tag) else { return }
        onNavigate?(crumbs[b.tag].path)
    }

    /// Menu thư mục con của đoạn đứng trước mũi tên.
    @objc private func showChildren(_ b: NSButton) {
        let idx = b.tag
        guard crumbs.indices.contains(idx) else { return }
        let path = crumbs[idx].path
        let next = crumbs.indices.contains(idx + 1) ? crumbs[idx + 1].path : nil
        let m = NSMenu()
        var entries: [(String, String)] = []
        if path == SpecialLocation.thisMac {
            let home = NSHomeDirectory()
            entries.append((FileManager.default.displayName(atPath: home), home))
            entries.append((Breadcrumb.rootVolumeName, "/"))
            let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
            for u in vols where u.path != "/" { entries.append((FileManager.default.displayName(atPath: u.path), u.path)) }
        } else {
            let items = (try? DirectoryReader.list(path)) ?? []
            entries = FileSorting.sort(items.filter(\.isDirectory), by: .name, ascending: true).prefix(300).map { ($0.name, $0.path) }
        }
        if entries.isEmpty { m.addItem(withTitle: L10n.t("noSubfolders"), action: nil, keyEquivalent: "") }
        for (t, p) in entries {
            let it = NSMenuItem(title: t, action: #selector(menuGo(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = p
            it.image = FileIcons.small("folder.fill", size: 14) ?? Theme.symbol("folder.fill", size: 12)
            if p == next { it.state = .on }
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 2), in: b)
    }

    @objc private func showOverflow(_ b: NSButton) {
        let m = NSMenu()
        for c in hiddenGroups.sorted().map({ crumbs[$0] }) {
            let it = NSMenuItem(title: c.title, action: #selector(menuGo(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = c.path
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 2), in: b)
    }

    @objc private func showHistory(_ b: NSButton) {
        let m = NSMenu()
        let h = Self.history
        if h.isEmpty { m.addItem(withTitle: L10n.t("noRecentLocations"), action: nil, keyEquivalent: "") }
        for p in h {
            let title = SpecialLocation.title(p) ?? p
            let it = NSMenuItem(title: title, action: #selector(menuGo(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = p
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 2), in: b)
    }

    @objc private func menuGo(_ it: NSMenuItem) {
        if let p = it.representedObject as? String { onNavigate?(p) }
    }
}
