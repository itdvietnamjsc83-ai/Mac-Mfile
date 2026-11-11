import AppKit
import MfileCore

/// Bố cục xếp cửa sổ khi di chuột lên nút Phóng to (như Snap Layouts của Windows 11, bản mẫu bảng 10).
final class SnapLayoutPopover: NSObject {
    private static var popover: NSPopover?

    static func show(for button: NSView, controller: MainWindowController) {
        guard popover == nil || popover?.isShown == false else { return }
        let vc = NSViewController()
        func layout(_ side: Int) -> NSButton {
            let b = NSButton(image: picture(side), target: controller, action: side < 0 ? #selector(MainWindowController.snapLeftFromChooser(_:)) : #selector(MainWindowController.snapRightFromChooser(_:)))
            b.isBordered = false
            b.toolTip = L10n.t(side < 0 ? "snapLeft" : "snapRight") + (side < 0 ? " (Cmd+←)" : " (Cmd+→)")
            return b
        }
        let row = NSStackView(views: [layout(-1), layout(1)])
        row.spacing = 8
        row.edgeInsets = .init(top: 8, left: 8, bottom: 8, right: 8)
        vc.view = row
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p
    }

    static func hide() { popover?.close(); popover = nil }

    private static func picture(_ side: Int) -> NSImage {
        NSImage(size: NSSize(width: 46, height: 30), flipped: false) { r in
            Theme.border.setStroke()
            let outer = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            Theme.background.setFill(); outer.fill(); outer.stroke()
            let half = NSRect(x: side < 0 ? 3 : r.midX + 1, y: 3, width: r.width / 2 - 4, height: r.height - 6)
            Theme.accent.setFill()
            NSBezierPath(roundedRect: half, xRadius: 2, yRadius: 2).fill()
            return true
        }
    }
}

/// Sau khi xếp một nửa: chọn cửa sổ Mac Mfile khác cho nửa còn lại (Snap Assist).
final class SnapAssist: NSObject {
    private static var current: SnapAssist?
    private var panel: NSPanel?
    private var monitor: Any?
    private var candidates: [MainWindowController] = []
    private let side: Int

    private init(side: Int) { self.side = side }

    static func offer(after controller: MainWindowController, side: Int, screen: NSScreen) {
        current?.dismiss()
        let others = NSApp.windows.compactMap { $0.windowController as? MainWindowController }
            .filter { $0 !== controller && $0.window?.isVisible == true && $0.window?.isMiniaturized == false }
        guard !others.isEmpty else { return }
        let a = SnapAssist(side: side)
        a.candidates = others
        current = a
        a.present(on: screen)
    }

    private func present(on screen: NSScreen) {
        let v = screen.visibleFrame
        let rect = NSRect(x: side < 0 ? v.midX : v.minX, y: v.minY, width: v.width / 2, height: v.height)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = NSColor(srgbRed: 0.2, green: 0.38, blue: 0.6, alpha: 0.92)
        p.hasShadow = false
        let title = label(L10n.t(side < 0 ? "snapAssistRight" : "snapAssistLeft"), size: 15, color: .white)
        var tiles: [NSView] = []
        for (i, wc) in candidates.prefix(6).enumerated() {
            let img = wc.window.flatMap { w -> NSImage? in
                guard let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { return nil }
                cv.cacheDisplay(in: cv.bounds, to: rep)
                let im = NSImage(size: cv.bounds.size)
                im.addRepresentation(rep)
                return im
            }
            let b = NSButton(title: "", image: img ?? NSImage(), target: self, action: #selector(pick(_:)))
            b.tag = i
            b.imageScaling = .scaleProportionallyDown
            b.isBordered = false
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 240).isActive = true
            b.heightAnchor.constraint(equalToConstant: 150).isActive = true
            let name = label("📁 " + (wc.window?.title ?? ""), color: .white)
            let s = NSStackView(views: [name, b])
            s.orientation = .vertical
            s.alignment = .leading
            tiles.append(s)
        }
        var rows: [NSView] = []
        var i = 0
        while i < tiles.count {
            let r = NSStackView(views: Array(tiles[i..<min(i + 2, tiles.count)]))
            r.spacing = 20
            rows.append(r)
            i += 2
        }
        let hint = label(L10n.t("snapAssistHint"), size: 11, color: NSColor(white: 1, alpha: 0.85))
        let stack = NSStackView(views: [title] + rows + [hint])
        stack.orientation = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: root.centerXAnchor), stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
        p.contentView = root
        p.orderFrontRegardless()
        panel = p
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] e in
            if e.type == .keyDown && e.keyCode == 53 { self?.dismiss(); return nil }
            if e.type == .leftMouseDown && e.window !== self?.panel { self?.dismiss() }
            return e
        }
    }

    @objc private func pick(_ b: NSButton) {
        guard candidates.indices.contains(b.tag) else { return }
        let wc = candidates[b.tag]
        dismiss()
        wc.window?.makeKeyAndOrderFront(nil)
        wc.snap(side: -side, offerAssist: false)
    }

    func dismiss() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
        if Self.current === self { Self.current = nil }
    }
}
