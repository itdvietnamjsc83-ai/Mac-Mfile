import AppKit
import MfileCore

/// Cửa sổ chính theo bố cục Windows 11: thanh tab trên cùng, nút − ☐ ✕ ở góc phải (Mục 4).
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let browser: BrowserViewController
    private var tabTitle: NSTextField!
    private var tabIcon: NSImageView!
    private var restoreFrame: NSRect?
    private var snappedSide: Int = 0 // -1 trái, 1 phải

    init(startPath: String) {
        browser = BrowserViewController(startPath: startPath)
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
        browser.onLocationChange = { [weak self] title, path in
            self?.tabTitle.stringValue = title
            self?.tabIcon.image = NSWorkspace.shared.icon(forFile: path)
            self?.window?.title = title
        }
        browser.reloadTitle()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let window else { return }
        let root = NSView()
        let strip = DragView(Theme.tabStrip)
        root.addSubview(strip)

        // Tab đang mở
        let tab = ColorView(Theme.chrome)
        tab.wantsLayer = true
        tab.layer?.cornerRadius = 8
        tab.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tabIcon = NSImageView()
        tabIcon.translatesAutoresizingMaskIntoConstraints = false
        tabTitle = label("")
        let tabClose = FlatButton(title: "", symbol: "xmark", target: window, action: #selector(NSWindow.performClose(_:)))
        let tabStack = NSStackView(views: [tabIcon, tabTitle, tabClose])
        tabStack.spacing = 8
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tab.addSubview(tabStack)
        strip.addSubview(tab)
        let plus = FlatButton(title: "", symbol: "plus", target: nil, action: #selector(AppDelegate.newWindow(_:)))
        strip.addSubview(plus)

        // − ☐ ✕ kiểu Windows
        let minB = WindowButton(kind: .minimize)
        let maxB = WindowButton(kind: .maximize)
        let closeB = WindowButton(kind: .close)
        let winButtons = NSStackView(views: [minB, maxB, closeB])
        winButtons.spacing = 0
        winButtons.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(winButtons)

        let content = browser.view
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 40),
            tab.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 8),
            tab.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            tab.heightAnchor.constraint(equalToConstant: 34),
            tab.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            tabStack.leadingAnchor.constraint(equalTo: tab.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(equalTo: tab.trailingAnchor, constant: -4),
            tabStack.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            tabIcon.widthAnchor.constraint(equalToConstant: 16),
            tabIcon.heightAnchor.constraint(equalToConstant: 16),
            plus.leadingAnchor.constraint(equalTo: tab.trailingAnchor, constant: 4),
            plus.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            winButtons.topAnchor.constraint(equalTo: strip.topAnchor),
            winButtons.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
            content.topAnchor.constraint(equalTo: strip.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
        window.makeFirstResponder(browser.table)
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
