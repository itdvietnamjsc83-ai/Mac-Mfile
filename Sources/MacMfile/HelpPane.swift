import AppKit
import MfileCore

/// Ngăn Hướng dẫn sử dụng (F1, bản mẫu bảng 23): tìm câu hỏi, Làm ngay, Chỉ cho tôi, Hay dùng.
final class HelpPaneView: ColorView, NSSearchFieldDelegate {
    var onClose: (() -> Void)?
    /// Chạy một lệnh như bấm menu.
    var perform: ((String) -> Void)?
    /// Chỉ từng bước: trả về khung giao diện cần chỉ.
    var showSteps: ((HelpTopic) -> Void)?
    var selectionName: (() -> String?)?

    private let search = NSSearchField()
    private let context = label("", size: 11, color: Theme.secondaryText)
    private let list = NSStackView()
    private let common = NSStackView()
    private let title = label("", size: 14)

    init() {
        super.init(Theme.chrome)
        title.font = Theme.font(14, weight: .semibold)
        let close = FlatButton(title: "", symbol: "xmark", target: self, action: #selector(closePressed))
        close.fixedHeight.constant = 22
        let f1 = label("F1", size: 11, color: Theme.secondaryText)
        let head = NSStackView(views: [title, NSView(), f1, close])
        search.delegate = self
        search.sendsSearchStringImmediately = true
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        common.orientation = .vertical
        common.alignment = .leading
        common.spacing = 6
        let scrollDoc = FlippedView()
        let inner = NSStackView(views: [list, common])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 16
        inner.translatesAutoresizingMaskIntoConstraints = false
        scrollDoc.addSubview(inner)
        scrollDoc.translatesAutoresizingMaskIntoConstraints = false
        let sc = NSScrollView()
        sc.documentView = scrollDoc
        sc.drawsBackground = false
        sc.hasVerticalScroller = true
        sc.translatesAutoresizingMaskIntoConstraints = false
        let foot = NSStackView(views: [link("helpIndex", #selector(showIndex)), link("cheatSheet", #selector(showCheat)), link("tipsLink", #selector(showTips))])
        foot.spacing = 12
        let stack = NSStackView(views: [head, search, context, sc, foot])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        pin(stack, insets: .init(top: 12, left: 12, bottom: 10, right: 12))
        NSLayoutConstraint.activate([
            head.widthAnchor.constraint(equalTo: stack.widthAnchor),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sc.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollDoc.leadingAnchor.constraint(equalTo: sc.contentView.leadingAnchor),
            scrollDoc.trailingAnchor.constraint(equalTo: sc.contentView.trailingAnchor),
            scrollDoc.topAnchor.constraint(equalTo: sc.contentView.topAnchor),
            inner.topAnchor.constraint(equalTo: scrollDoc.topAnchor),
            inner.leadingAnchor.constraint(equalTo: scrollDoc.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: scrollDoc.trailingAnchor, constant: -4),
            inner.bottomAnchor.constraint(equalTo: scrollDoc.bottomAnchor),
            list.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: L10n.didChangeNotification, object: nil)
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func link(_ key: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: L10n.t(key), target: self, action: sel)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: L10n.t(key), attributes: [.foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .font: Theme.font(12)])
        return b
    }

    func focusSearch(_ text: String? = nil) {
        if let text { search.stringValue = text }
        window?.makeFirstResponder(search)
        reload()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    @objc func reload() {
        title.stringValue = L10n.t("userGuide")
        search.placeholderString = L10n.t("helpSearchPlaceholder")
        if let n = selectionName?() { context.stringValue = L10n.f("currentSelection", n); context.isHidden = false } else { context.isHidden = true }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let results = HelpTopics.search(search.stringValue)
        if results.isEmpty { list.addArrangedSubview(label(L10n.t("helpNoResults"), color: Theme.secondaryText)) }
        for (i, tp) in results.prefix(8).enumerated() {
            let c = card(tp, primary: i == 0)
            list.addArrangedSubview(c)
            c.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        common.arrangedSubviews.forEach { $0.removeFromSuperview() }
        common.addArrangedSubview(label(L10n.t("commonTasks"), size: 11, color: Theme.secondaryText))
        var row = NSStackView(); row.spacing = 6
        var count = 0
        for tp in HelpTopics.all where tp.common {
            let b = NSButton(title: tp.title(), target: self, action: #selector(chip(_:)))
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.identifier = .init(tp.id)
            row.addArrangedSubview(b)
            count += 1
            if count % 2 == 0 { common.addArrangedSubview(row); row = NSStackView(); row.spacing = 6 }
        }
        if !row.arrangedSubviews.isEmpty { common.addArrangedSubview(row) }
    }

    private func card(_ tp: HelpTopic, primary: Bool) -> NSView {
        let box = ColorView(primary ? Theme.background : Theme.background)
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = (primary ? Theme.accent : Theme.border).cgColor
        let t = label(tp.title())
        t.font = Theme.font(12, weight: .semibold)
        t.maximumNumberOfLines = 2
        t.lineBreakMode = .byWordWrapping
        let body = label(tp.body(), color: Theme.text)
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.preferredMaxLayoutWidth = 270
        var buttons: [NSView] = []
        if tp.action != nil {
            let b = NSButton(title: L10n.t("doItNow"), target: self, action: #selector(doIt(_:)))
            b.identifier = .init(tp.id)
            b.bezelStyle = .rounded
            if primary { b.keyEquivalent = "" ; b.bezelColor = Theme.accent }
            buttons.append(b)
        }
        if !tp.steps.isEmpty {
            let b = NSButton(title: L10n.t("showMe"), target: self, action: #selector(showMe(_:)))
            b.identifier = .init(tp.id)
            b.bezelStyle = .rounded
            buttons.append(b)
        }
        let s = NSStackView(views: [t, body] + (buttons.isEmpty ? [] : [NSStackView(views: buttons)]))
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        box.pin(s, insets: .init(top: 10, left: 12, bottom: 10, right: 12))
        t.widthAnchor.constraint(lessThanOrEqualTo: s.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true
        return box
    }

    @objc private func doIt(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, let tp = HelpTopics.topic(id), let a = tp.action else { return }
        perform?(a)
    }
    @objc private func showMe(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, let tp = HelpTopics.topic(id) else { return }
        showSteps?(tp)
    }
    @objc private func chip(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, let tp = HelpTopics.topic(id) else { return }
        search.stringValue = tp.title()
        reload()
    }
    @objc private func closePressed() { onClose?() }
    @objc private func showIndex() {
        search.stringValue = ""
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tp in HelpTopics.all {
            let b = NSButton(title: tp.title(), target: self, action: #selector(chip(_:)))
            b.isBordered = false
            b.identifier = .init(tp.id)
            b.attributedTitle = NSAttributedString(string: "• " + tp.title(), attributes: [.foregroundColor: Theme.accent, .font: Theme.font(12)])
            list.addArrangedSubview(b)
        }
    }
    @objc private func showCheat() { perform?("showShortcuts:") }
    @objc private func showTips() { TipsWindowController.show(force: true) }
}

/// "Chỉ cho tôi": khung vàng quanh vùng cần bấm và bong bóng từng bước (Bước 1/2 … Tiếp › Bỏ qua).
final class CoachMarks: NSObject {
    private static var current: CoachMarks?
    private let steps: [(view: NSView, text: String)]
    private var index = 0
    private var popover: NSPopover?
    private var ring: NSView?

    static func run(_ steps: [(NSView, String)]) {
        current?.finish()
        guard !steps.isEmpty else { return }
        let c = CoachMarks(steps: steps)
        current = c
        c.show()
    }

    private init(steps: [(NSView, String)]) { self.steps = steps.map { (view: $0.0, text: $0.1) } }

    private func show() {
        ring?.removeFromSuperview()
        popover?.close()
        guard index < steps.count else { finish(); return }
        let s = steps[index]
        if let sup = s.view.superview {
            let r = ColorView(.clear)
            r.translatesAutoresizingMaskIntoConstraints = true
            r.wantsLayer = true
            r.layer?.borderWidth = 2
            r.layer?.cornerRadius = 6
            r.layer?.borderColor = NSColor(srgbRed: 0.98, green: 0.76, blue: 0.18, alpha: 1).cgColor
            r.frame = s.view.frame.insetBy(dx: -3, dy: -3)
            sup.addSubview(r, positioned: .above, relativeTo: s.view)
            ring = r
        }
        let vc = NSViewController()
        let text = label(L10n.f("stepOf", index + 1, steps.count) + ": " + s.text)
        text.maximumNumberOfLines = 0
        text.preferredMaxLayoutWidth = 260
        let next = NSButton(title: L10n.t(index == steps.count - 1 ? "done" : "nextStep"), target: self, action: #selector(nextStep))
        let skip = NSButton(title: L10n.t("skip"), target: self, action: #selector(finish))
        skip.isBordered = false
        let row = NSStackView(views: [text, next, skip])
        row.spacing = 8
        row.edgeInsets = .init(top: 10, left: 12, bottom: 10, right: 12)
        vc.view = row
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .applicationDefined
        p.show(relativeTo: s.view.bounds, of: s.view, preferredEdge: .maxY)
        popover = p
    }

    @objc private func nextStep() { index += 1; show() }
    @objc func finish() {
        popover?.close()
        ring?.removeFromSuperview()
        if Self.current === self { Self.current = nil }
    }
}

/// Mẹo khi mở (bản mẫu bảng 24).
final class TipsWindowController: NSWindowController {
    private static var shared: TipsWindowController?
    private var index = Int.random(in: 0..<HelpTopics.tips.count)
    private let tipTitle = label("", size: 16)
    private let body = label("")
    private let tryB = NSButton()
    private let showAtLaunch = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    static func show(force: Bool = false) {
        guard force || Settings.showTips else { return }
        if shared == nil { shared = TipsWindowController() }
        shared?.refresh()
        shared?.window?.center()
        shared?.showWindow(nil)
    }

    private init() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        tipTitle.font = Theme.font(16)
        tipTitle.textColor = Theme.accent
        body.maximumNumberOfLines = 0
        body.preferredMaxLayoutWidth = 410
        tryB.target = self; tryB.action = #selector(tryIt); tryB.bezelStyle = .rounded
        let nextB = NSButton(title: L10n.t("nextTip"), target: self, action: #selector(nextTip))
        showAtLaunch.target = self; showAtLaunch.action = #selector(toggleShow)
        let close = NSButton(title: L10n.t("close"), target: self, action: #selector(closeIt))
        let top = NSStackView(views: [tipTitle, body, NSStackView(views: [tryB, nextB])])
        top.orientation = .vertical; top.alignment = .leading; top.spacing = 10
        let bottom = ColorView(Theme.chrome)
        bottom.pin(NSStackView(views: [showAtLaunch, NSView(), close]), insets: .init(top: 10, left: 16, bottom: 10, right: 16))
        let root = ColorView(Theme.background)
        root.addSubview(top); root.addSubview(bottom)
        top.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        w.contentView = root
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        let t = HelpTopics.tips[index % HelpTopics.tips.count]
        let vi = L10n.current == .vi
        window?.title = L10n.t("tipOfDay")
        tipTitle.stringValue = vi ? t.title.0 : t.title.1
        body.stringValue = vi ? t.vi : t.en
        tryB.title = L10n.t("tryNow")
        tryB.isHidden = t.action == nil
        showAtLaunch.title = L10n.t("showTipsEachLaunch")
        showAtLaunch.state = Settings.showTips ? .on : .off
    }
    @objc private func nextTip() { index += 1; refresh() }
    @objc private func tryIt() {
        if let a = HelpTopics.tips[index % HelpTopics.tips.count].action { NSApp.sendAction(Selector(a), to: nil, from: nil) }
        close()
    }
    @objc private func toggleShow() { Settings.showTips = showAtLaunch.state == .on }
    @objc private func closeIt() { close() }
}
