import AppKit
import MfileCore

/// Cửa sổ chính theo bố cục Windows 11: thanh tab trên cùng, nút − ☐ ✕ ở góc phải (Mục 4).
/// Mỗi tab là một BrowserViewController riêng (FR-02).
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private(set) var tabs: [BrowserViewController] = []
    private(set) var activeIndex = 0
    var browser: BrowserViewController { tabs[activeIndex] }
    var tabPaths: [String] { tabs.map(\.currentPath) }

    private let container = NSView()
    private let tabStack = NSStackView()
    private var restoreFrame: NSRect?
    private var snappedSide: Int = 0 // -1 trái, 1 phải

    init(paths: [String]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 640, height: 400)
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
        window.backgroundColor = Theme.chrome
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)
        window.delegate = self
        buildContent()
        for p in (paths.isEmpty ? [NSHomeDirectory()] : paths) { addTab(path: p, activate: false) }
        selectTab(0)
        window.center()
    }

    convenience init(startPath: String) { self.init(paths: [startPath]) }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let window else { return }
        let root = NSView()
        let strip = DragView(Theme.tabStrip)
        root.addSubview(strip)

        tabStack.orientation = .horizontal
        tabStack.spacing = 2
        tabStack.alignment = .bottom
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(tabStack)
        let plus = FlatButton(title: "", symbol: "plus", target: self, action: #selector(newTab(_:)))
        plus.toolTip = L10n.t("newTab") + " (Cmd+T)"
        strip.addSubview(plus)

        // − ☐ ✕ kiểu Windows
        let winButtons = NSStackView(views: [WindowButton(kind: .minimize), WindowButton(kind: .maximize), WindowButton(kind: .close)])
        winButtons.spacing = 0
        winButtons.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(winButtons)

        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 40),
            tabStack.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 8),
            tabStack.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            tabStack.heightAnchor.constraint(equalToConstant: 34),
            plus.leadingAnchor.constraint(equalTo: tabStack.trailingAnchor, constant: 4),
            plus.centerYAnchor.constraint(equalTo: tabStack.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 32),
            plus.trailingAnchor.constraint(lessThanOrEqualTo: winButtons.leadingAnchor, constant: -8),
            winButtons.topAnchor.constraint(equalTo: strip.topAnchor),
            winButtons.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
            container.topAnchor.constraint(equalTo: strip.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildTabStrip), name: L10n.didChangeNotification, object: nil)
    }

    // MARK: Tab (FR-02)

    @discardableResult
    func addTab(path: String, activate: Bool = true, at index: Int? = nil) -> BrowserViewController {
        let b = BrowserViewController(startPath: path)
        b.onLocationChange = { [weak self] _, _ in self?.rebuildTabStrip() }
        let i = min(index ?? tabs.count, tabs.count)
        tabs.insert(b, at: i)
        _ = b.view // nạp giao diện
        if activate { selectTab(i) } else { rebuildTabStrip() }
        return b
    }

    func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        activeIndex = i
        container.pin(browser.view)
        rebuildTabStrip()
        window?.title = browser.title ?? ""
        window?.makeFirstResponder(browser.table)
    }

    func closeTab(at i: Int) {
        guard tabs.indices.contains(i) else { return }
        if tabs.count == 1 { window?.performClose(nil); return }
        tabs.remove(at: i)
        selectTab(min(activeIndex >= i ? max(activeIndex - 1, 0) : activeIndex, tabs.count - 1))
    }

    @objc func newTab(_ sender: Any?) { addTab(path: NSHomeDirectory()) }
    @objc func closeCurrentTab(_ sender: Any?) { closeTab(at: activeIndex) }
    @objc func nextTab(_ sender: Any?) { selectTab((activeIndex + 1) % tabs.count) }
    @objc func previousTab(_ sender: Any?) { selectTab((activeIndex - 1 + tabs.count) % tabs.count) }
    @objc func duplicateTab(_ sender: Any?) {
        let i = (sender as? NSMenuItem)?.tag ?? activeIndex
        addTab(path: tabs[i].currentPath, at: i + 1)
    }
    @objc func closeOtherTabs(_ sender: Any?) {
        let i = (sender as? NSMenuItem)?.tag ?? activeIndex
        let keep = tabs[i]
        tabs = [keep]
        selectTab(0)
    }
    @objc func closeTabFromMenu(_ sender: NSMenuItem) { closeTab(at: sender.tag) }
    @objc func moveTabToNewWindow(_ sender: NSMenuItem) {
        let i = sender.tag
        guard tabs.count > 1 else { return }
        let path = tabs[i].currentPath
        closeTab(at: i)
        (NSApp.delegate as? AppDelegate)?.openWindow(at: path)
    }

    @objc private func rebuildTabStrip() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let width: CGFloat = tabs.count > 5 ? max(120, 1000 / CGFloat(tabs.count)) : 220
        for (i, b) in tabs.enumerated() {
            let t = TabItemView(controller: self, index: i, title: b.title ?? "", path: b.currentPath, active: i == activeIndex)
            t.widthAnchor.constraint(equalToConstant: width).isActive = true
            tabStack.addArrangedSubview(t)
        }
        if tabs.indices.contains(activeIndex) { window?.title = tabs[activeIndex].title ?? "" }
    }

    // MARK: Xếp cửa sổ nửa màn hình (FR-47, Mục 5.10)

    func snap(side: Int) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if snappedSide == side, let r = restoreFrame {
            window.setFrame(r, display: true, animate: true)
            snappedSide = 0
            restoreFrame = nil
            return
        }
        if snappedSide == -side, let r = restoreFrame {
            // Bấm phím ngược chiều: nếu có màn hình bên cạnh theo chiều đó thì sang nửa đối diện của màn hình đó.
            if let next = neighbor(of: screen, side: side) {
                let v = next.visibleFrame
                let half = NSRect(x: side > 0 ? v.minX : v.midX, y: v.minY, width: v.width / 2, height: v.height)
                window.setFrame(half, display: true, animate: true)
                snappedSide = -side
                return
            }
            window.setFrame(r, display: true, animate: true)
            snappedSide = 0
            restoreFrame = nil
            return
        }
        if restoreFrame == nil { restoreFrame = window.frame }
        let v = screen.visibleFrame
        let half = NSRect(x: side < 0 ? v.minX : v.midX, y: v.minY, width: v.width / 2, height: v.height)
        window.setFrame(half, display: true, animate: true)
        snappedSide = side
    }

    private func neighbor(of screen: NSScreen, side: Int) -> NSScreen? {
        NSScreen.screens.first { s in
            s != screen && (side > 0 ? abs(s.frame.minX - screen.frame.maxX) < 2 : abs(s.frame.maxX - screen.frame.minX) < 2)
        }
    }

    /// Lệnh menu chưa có ai nhận (ví dụ khi chưa chọn ô nào) thì chuyển cho trình duyệt thư mục.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if browser.responds(to: action) { return browser }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    @objc func snapLeft(_ sender: Any?) { snapOrMoveCaret(side: -1) }
    @objc func snapRight(_ sender: Any?) { snapOrMoveCaret(side: 1) }

    /// Khi đang gõ chữ, Cmd+←/→ vẫn đưa con trỏ về đầu/cuối dòng theo macOS.
    private func snapOrMoveCaret(side: Int) {
        if let text = window?.firstResponder as? NSTextView {
            if side < 0 { text.moveToBeginningOfLine(nil) } else { text.moveToEndOfLine(nil) }
            return
        }
        snap(side: side)
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.windowClosed(self)
    }
}

/// Nút Thu nhỏ / Phóng to / Đóng vẽ theo Windows 11, rộng 46 px, nút Đóng đỏ khi di chuột.
final class WindowButton: NSButton {
    enum Kind { case minimize, maximize, close }
    let kind: Kind
    private var hovering = false { didSet { needsDisplay = true } }
    private var area: NSTrackingArea?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(press)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 46).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        reloadTooltip()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTooltip), name: L10n.didChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func reloadTooltip() {
        switch kind {
        case .minimize: toolTip = L10n.t("minimize")
        case .maximize: toolTip = L10n.t("maximize")
        case .close: toolTip = L10n.t("close")
        }
    }

    @objc private func press() {
        switch kind {
        case .minimize: window?.miniaturize(nil)
        case .maximize: window?.zoom(nil)
        case .close: window?.performClose(nil)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            (kind == .close ? Theme.closeHover : NSColor(white: 0, alpha: 0.06)).setFill()
            bounds.fill()
        }
        let stroke = (hovering && kind == .close) ? NSColor.white : Theme.text
        stroke.setStroke()
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let p = NSBezierPath()
        p.lineWidth = 1
        switch kind {
        case .minimize:
            p.move(to: NSPoint(x: c.x - 5, y: c.y))
            p.line(to: NSPoint(x: c.x + 5, y: c.y))
        case .maximize:
            p.appendRect(NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10).insetBy(dx: 0.5, dy: 0.5))
        case .close:
            p.move(to: NSPoint(x: c.x - 5, y: c.y - 5)); p.line(to: NSPoint(x: c.x + 5, y: c.y + 5))
            p.move(to: NSPoint(x: c.x + 5, y: c.y - 5)); p.line(to: NSPoint(x: c.x - 5, y: c.y + 5))
        }
        p.stroke()
    }
}

/// Một tab trên thanh tiêu đề: biểu tượng, tên thư mục, nút ✕; nhấp chuột phải có Nhân bản tab, Đóng các tab khác.
final class TabItemView: ColorView {
    private weak var controller: MainWindowController?
    private let index: Int

    init(controller: MainWindowController, index: Int, title: String, path: String, active: Bool) {
        self.controller = controller
        self.index = index
        super.init(active ? Theme.chrome : Theme.tabStrip)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let t = label(title)
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = FlatButton(title: "", symbol: "xmark", target: self, action: #selector(closeMe))
        close.widthAnchor.constraint(equalToConstant: 26).isActive = true
        close.toolTip = L10n.t("closeTab") + " (Cmd+W)"
        let stack = NSStackView(views: [icon, t, NSView(), close])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = path
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { controller?.selectTab(index) }
    override func otherMouseUp(with event: NSEvent) { controller?.closeTab(at: index) } // nhấp chuột giữa: đóng tab

    @objc private func closeMe() { controller?.closeTab(at: index) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        for (key, sel) in [("duplicateTab", #selector(MainWindowController.duplicateTab(_:))),
                           ("moveTabToNewWindow", #selector(MainWindowController.moveTabToNewWindow(_:))),
                           ("closeOtherTabs", #selector(MainWindowController.closeOtherTabs(_:))),
                           ("closeTab", #selector(MainWindowController.closeTabFromMenu(_:)))] {
            let it = NSMenuItem(title: L10n.t(key), action: sel, keyEquivalent: "")
            it.target = controller
            it.tag = index
            m.addItem(it)
        }
        return m
    }
}
