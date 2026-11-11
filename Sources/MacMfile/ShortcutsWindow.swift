import AppKit
import UniformTypeIdentifiers
import MfileCore

/// Cài đặt phím tắt (bản mẫu bảng 4): bộ phím Mac/Windows, Ctrl như Windows, tìm, kiểm tra trùng,
/// nhập/xuất, đổi phím chính và phím phụ, gợi ý phím còn trống khi bị trùng.
final class ShortcutsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static var shared: ShortcutsWindowController?
    static func show() {
        if shared == nil { shared = ShortcutsWindowController() }
        shared?.window?.center()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var bindings = Settings.shortcuts
    private var ctrlLikeWindows = Settings.ctrlLikeWindows
    private let preset = NSPopUpButton()
    private let ctrlSwitch = NSSwitch()
    private let search = NSSearchField()
    private let cats = NSTableView()
    private let table = NSTableView()
    private let warning = ColorView(NSColor(srgbRed: 1, green: 0.957, blue: 0.808, alpha: 1))
    private let warnTitle = label("")
    private let warnText = label("", color: Theme.text)
    private let warnButtons = NSStackView()
    private let categories: [String] = ShortcutRegistry.actions.reduce(into: ["catAll"]) { r, a in if !r.contains(a.category) { r.append(a.category) } }
    private var selectedCat = 0
    private var visible: [ShortcutAction] = []
    private var recording: (id: String, slot: Int)?
    private var monitor: Any?
    private var onlyConflicts = false

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 820, height: 480)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
        refilter()
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        Self.shared = nil
    }

    private func id(_ base: String, _ slot: Int) -> String { slot == 0 ? base : base + ".2" }

    // MARK: Giao diện

    private func build() {
        guard let w = window else { return }
        w.title = L10n.t("shortcutWindowTitle")
        let root = ColorView(.white)
        w.contentView = root

        preset.addItems(withTitles: [L10n.t("presetMac"), L10n.t("presetWindows")])
        preset.selectItem(at: bindings.preset == .mac ? 0 : 1)
        preset.target = self; preset.action = #selector(presetChanged)
        ctrlSwitch.state = ctrlLikeWindows ? .on : .off
        ctrlSwitch.target = self; ctrlSwitch.action = #selector(ctrlChanged)
        search.placeholderString = L10n.t("searchCommandOrKey")
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let check = NSButton(title: L10n.t("checkConflicts"), target: self, action: #selector(checkConflicts))
        check.keyEquivalent = ""
        check.bezelColor = Theme.accent
        let imp = NSButton(title: L10n.t("importDots"), target: self, action: #selector(importBindings))
        let exp = NSButton(title: L10n.t("exportDots"), target: self, action: #selector(exportBindings))
        let top = NSStackView(views: [label(L10n.t("presetLabel")), preset, ctrlSwitch, label(L10n.t("ctrlLikeWindows")), NSView(), search, check, imp, exp])
        top.spacing = 10
        let topBar = ColorView(Theme.chrome)
        topBar.bottomBorder = true
        topBar.pin(top, insets: .init(top: 12, left: 16, bottom: 12, right: 16))

        cats.addTableColumn(NSTableColumn(identifier: .init("c")))
        cats.headerView = nil
        cats.rowHeight = 32
        cats.style = .sourceList
        cats.dataSource = self; cats.delegate = self
        let cs = NSScrollView(); cs.documentView = cats; cs.drawsBackground = false
        cs.translatesAutoresizingMaskIntoConstraints = false
        let hint = label(L10n.t("cheatHint"), size: 11, color: Theme.secondaryText)
        hint.maximumNumberOfLines = 0
        hint.lineBreakMode = .byWordWrapping
        let left = ColorView(Theme.chrome)
        left.addSubview(cs); left.addSubview(hint)

        for (idn, key, wdt) in [("cmd", "colCommand", 330.0), ("k1", "colPrimary", 170.0), ("k2", "colSecondary", 170.0), ("st", "colStatus", 170.0), ("r", "", 40.0)] {
            let c = NSTableColumn(identifier: .init(idn))
            c.title = key.isEmpty ? "" : L10n.t(key)
            c.width = CGFloat(wdt)
            table.addTableColumn(c)
        }
        table.rowHeight = 36
        table.style = .plain
        table.dataSource = self; table.delegate = self
        let ts = NSScrollView(); ts.documentView = table; ts.hasVerticalScroller = true
        ts.translatesAutoresizingMaskIntoConstraints = false

        warning.wantsLayer = true
        warning.layer?.cornerRadius = 6
        warning.layer?.borderWidth = 1
        warning.layer?.borderColor = NSColor(srgbRed: 0.93, green: 0.78, blue: 0.4, alpha: 1).cgColor
        warnTitle.font = Theme.font(12, weight: .semibold)
        warnText.maximumNumberOfLines = 0
        warnText.lineBreakMode = .byWordWrapping
        warnButtons.spacing = 8
        let ws = NSStackView(views: [warnTitle, warnText, warnButtons])
        ws.orientation = .vertical; ws.alignment = .leading; ws.spacing = 6
        warning.pin(ws, insets: .init(top: 12, left: 16, bottom: 12, right: 16))
        warning.isHidden = true

        let reset = NSButton(title: L10n.t("resetAllShortcuts"), target: self, action: #selector(resetAll))
        let ok = NSButton(title: L10n.t("ok"), target: self, action: #selector(okPressed))
        let cancel = NSButton(title: L10n.t("cancel"), target: self, action: #selector(cancelPressed))
        let apply = NSButton(title: L10n.t("apply"), target: self, action: #selector(applyPressed))
        for b in [ok, cancel, apply] { b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true }
        let bottom = ColorView(Theme.chrome)
        bottom.pin(NSStackView(views: [reset, NSView(), ok, cancel, apply]), insets: .init(top: 12, left: 16, bottom: 12, right: 16))

        for v in [topBar, left, ts, warning, bottom] as [NSView] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: root.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            left.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            left.widthAnchor.constraint(equalToConstant: 220),
            cs.topAnchor.constraint(equalTo: left.topAnchor, constant: 8),
            cs.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            cs.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            cs.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
            hint.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -12),
            ts.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            ts.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 16),
            ts.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            warning.topAnchor.constraint(equalTo: ts.bottomAnchor, constant: 8),
            warning.leadingAnchor.constraint(equalTo: ts.leadingAnchor),
            warning.trailingAnchor.constraint(equalTo: ts.trailingAnchor),
            warning.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -10),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        cats.selectRowIndexes([0], byExtendingSelection: false)
    }

    // MARK: Dữ liệu

    private func refilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        let eff = bindings.effective
        let conflicts = Set(ShortcutRegistry.conflicts(eff).values.flatMap { $0 }.map { $0.replacingOccurrences(of: ".2", with: "") })
        visible = ShortcutRegistry.actions.filter { a in
            if selectedCat > 0 && a.category != categories[selectedCat] { return false }
            if onlyConflicts && !conflicts.contains(a.id) { return false }
            guard !q.isEmpty else { return true }
            let keys = [eff[a.id], eff[id(a.id, 1)]].compactMap { $0?.description }.joined(separator: " ")
            return (L10n.t(a.titleKey) + " " + keys).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        table.reloadData()
        cats.reloadData()
        if cats.selectedRow != selectedCat { cats.selectRowIndexes([selectedCat], byExtendingSelection: false) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === cats ? categories.count : visible.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        func put(_ v: NSView, leading: CGFloat = 8) {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
            NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
                                         v.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                         v.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4)])
        }
        if tableView === cats {
            let c = categories[row]
            let n = c == "catAll" ? ShortcutRegistry.actions.count : ShortcutRegistry.actions.filter { $0.category == c }.count
            put(label(L10n.t(c) + "  (\(n))"))
            return cell
        }
        let a = visible[row]
        let eff = bindings.effective
        switch tableColumn?.identifier.rawValue {
        case "cmd":
            put(label(L10n.t(a.titleKey) + (a.isGlobal ? "  🌐" : "")))
        case "k1", "k2":
            let slot = tableColumn?.identifier.rawValue == "k1" ? 0 : 1
            let key = id(a.id, slot)
            let isRec = recording?.id == a.id && recording?.slot == slot
            let title = isRec ? L10n.t("pressKeys") : (eff[key]?.description ?? (slot == 1 ? "+ " + L10n.t("addKey") : "—"))
            let b = NSButton(title: title, target: self, action: #selector(startRecording(_:)))
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.tag = row * 2 + slot
            b.toolTip = L10n.t("recordHint")
            put(b)
        case "st":
            let combos = [eff[a.id], eff[id(a.id, 1)]].compactMap { $0 }
            var status = L10n.t("statusOK"), color = NSColor(srgbRed: 0.06, green: 0.48, blue: 0.06, alpha: 1)
            for c in combos {
                if let o = ShortcutRegistry.owner(of: c, in: eff, except: a.id), o.replacingOccurrences(of: ".2", with: "") != a.id {
                    status = L10n.t("statusConflict"); color = Theme.closeHover
                }
            }
            if bindings.overrides[a.id] != nil || bindings.overrides[id(a.id, 1)] != nil, status == L10n.t("statusOK") { status = L10n.t("statusChanged"); color = Theme.accent }
            put(label(status, color: color))
        default:
            let b = NSButton(image: Theme.symbol("arrow.counterclockwise", size: 12) ?? NSImage(), target: self, action: #selector(resetRow(_:)))
            b.isBordered = false
            b.tag = row
            b.toolTip = L10n.t("resetToDefault")
            put(b)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === cats, cats.selectedRow >= 0 else { return }
        selectedCat = cats.selectedRow
        onlyConflicts = false
        refilter()
    }

    func controlTextDidChange(_ obj: Notification) { refilter() }

    // MARK: Ghi phím

    @objc private func startRecording(_ sender: NSButton) {
        let row = sender.tag / 2, slot = sender.tag % 2
        guard visible.indices.contains(row) else { return }
        stopRecording()
        recording = (visible[row].id, slot)
        table.reloadData()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.recorded(e)
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = nil
    }

    private func recorded(_ e: NSEvent) {
        guard let rec = recording else { return }
        let key = id(rec.id, rec.slot)
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        if e.keyCode == 53 && flags.isEmpty { stopRecording(); table.reloadData(); return }          // Esc: hủy
        if e.keyCode == 51 && flags.isEmpty { bindings.set(nil, for: key); stopRecording(); refilter(); hideWarning(); return } // ⌫: bỏ phím
        guard let combo = KeyCombo(event: e) else { return }
        stopRecording()
        let isFn = combo.key.hasPrefix("f") && combo.key.count > 1 && Int(combo.key.dropFirst()) != nil
        if !combo.hasModifier && !isFn {
            showWarning(title: L10n.f("needsModifierTitle", combo.description), text: L10n.t("needsModifier"), suggest: nil, for: key, combo: combo, other: nil)
            table.reloadData()
            return
        }
        let eff = bindings.effective
        if let owner = ShortcutRegistry.owner(of: combo, in: eff, except: key) {
            let s = ShortcutRegistry.suggest(for: combo, in: eff, except: key)
            if owner.hasPrefix("system:") {
                showWarning(title: L10n.f("usedBySystem", combo.description, String(owner.dropFirst(7))), text: L10n.t("systemBlocks"), suggest: s, for: key, combo: combo, other: nil)
            } else {
                let base = owner.replacingOccurrences(of: ".2", with: "")
                let name = ShortcutRegistry.action(base).map { L10n.t($0.titleKey) } ?? owner
                showWarning(title: L10n.f("usedByCommand", combo.description, name), text: L10n.t("chooseFreeKey"), suggest: s, for: key, combo: combo, other: owner)
            }
            table.reloadData()
            return
        }
        bindings.set(combo, for: key)
        hideWarning()
        refilter()
    }

    private var pending: (key: String, combo: KeyCombo, suggest: KeyCombo?, other: String?)?

    private func showWarning(title: String, text: String, suggest: KeyCombo?, for key: String, combo: KeyCombo, other: String?) {
        pending = (key, combo, suggest, other)
        warnTitle.stringValue = "⚠️ " + title
        warnText.stringValue = text
        warnButtons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let s = suggest {
            warnButtons.addArrangedSubview(NSButton(title: L10n.f("useSuggestion", s.description), target: self, action: #selector(useSuggestion)))
        }
        if other != nil {
            warnButtons.addArrangedSubview(NSButton(title: L10n.t("assignAnyway"), target: self, action: #selector(assignAnyway)))
        }
        let again = NSButton(title: L10n.t("pressOtherKey"), target: self, action: #selector(pressAgain))
        warnButtons.addArrangedSubview(again)
        warning.isHidden = false
    }
    private func hideWarning() { warning.isHidden = true; pending = nil }

    @objc private func useSuggestion() {
        guard let p = pending, let s = p.suggest else { return }
        bindings.set(s, for: p.key)
        hideWarning(); refilter()
    }
    @objc private func assignAnyway() {
        guard let p = pending, let o = p.other else { return }
        bindings.set(nil, for: o)
        bindings.set(p.combo, for: p.key)
        hideWarning(); refilter()
    }
    @objc private func pressAgain() {
        guard let p = pending else { return }
        let base = p.key.replacingOccurrences(of: ".2", with: "")
        let slot = p.key.hasSuffix(".2") ? 1 : 0
        hideWarning()
        if let row = visible.firstIndex(where: { $0.id == base }) {
            let b = NSButton(); b.tag = row * 2 + slot
            startRecording(b)
        }
    }

    // MARK: Nút

    @objc private func resetRow(_ sender: NSButton) {
        guard visible.indices.contains(sender.tag) else { return }
        let a = visible[sender.tag]
        bindings.overrides.removeValue(forKey: a.id)
        bindings.overrides.removeValue(forKey: id(a.id, 1))
        refilter()
    }
    @objc private func presetChanged() {
        bindings = ShortcutBindings(preset: preset.indexOfSelectedItem == 0 ? .mac : .windows, overrides: bindings.overrides)
        refilter()
    }
    @objc private func ctrlChanged() { ctrlLikeWindows = ctrlSwitch.state == .on }
    @objc private func checkConflicts() {
        let c = ShortcutRegistry.conflicts(bindings.effective)
        if c.isEmpty {
            let a = NSAlert(); a.messageText = L10n.t("noConflicts")
            if let w = window { a.beginSheetModal(for: w) { _ in } }
            onlyConflicts = false
        } else {
            onlyConflicts = true
            selectedCat = 0
        }
        refilter()
    }
    @objc private func importBindings() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard let w = window else { return }
        p.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let u = p.url, let data = try? Data(contentsOf: u) else { return }
            do {
                self?.bindings = try ShortcutBindings.importJSON(data)
                self?.preset.selectItem(at: self?.bindings.preset == .mac ? 0 : 1)
                self?.refilter()
            } catch {
                let a = NSAlert(); a.messageText = L10n.t("importFailed")
                a.beginSheetModal(for: w) { _ in }
            }
        }
    }
    @objc private func exportBindings() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "MacMfile-phim-tat.json"
        guard let w = window, let data = try? bindings.exportJSON() else { return }
        p.beginSheetModal(for: w) { r in if r == .OK, let u = p.url { try? data.write(to: u) } }
    }
    @objc private func resetAll() {
        bindings = ShortcutBindings(preset: bindings.preset)
        hideWarning(); refilter()
    }
    @objc private func applyPressed() {
        Settings.shortcuts = bindings
        Settings.ctrlLikeWindows = ctrlLikeWindows
        Settings.changed()
    }
    @objc private func okPressed() { applyPressed(); close() }
    @objc private func cancelPressed() { close() }
}
