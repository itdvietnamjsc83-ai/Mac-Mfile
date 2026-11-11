import AppKit
import MfileCore

/// Cửa sổ Tùy chọn (bản mẫu bảng 17–18): danh mục bên trái, thẻ cài đặt bên phải, tìm cài đặt, OK / Hủy / Áp dụng.
final class OptionsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static var shared: OptionsWindowController?

    static func show(section: Int = 0) {
        if shared == nil { shared = OptionsWindowController() }
        shared?.select(section)
        shared?.window?.center()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private struct Row { let section: Int; let title: String; let view: NSView }
    private let sectionKeys = ["optGeneral", "optView", "optNavPane", "optSearch", "optPrivacy", "optPaths", "optRemoveInfo", "optShortcuts"]
    private let sectionList = NSTableView()
    private let search = NSSearchField()
    private let content = NSStackView()
    private let heading = label("", size: 20)
    private var rows: [Row] = []
    private var commits: [() -> Void] = []
    private var current = 0
    private var pins: [String] = Pins.all
    private var cleanFolders: [String] = AutoCleanWatcher.folders
    private let pinTable = NSTableView(), cleanTable = NSTableView()

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 760, height: 520)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { Self.shared = nil }

    // MARK: Khung

    private func build() {
        guard let w = window else { return }
        w.title = L10n.t("optionsTitle")
        let root = ColorView(.white)
        w.contentView = root
        let left = ColorView(Theme.chrome)
        search.placeholderString = L10n.t("searchSettings")
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        let col = NSTableColumn(identifier: .init("s"))
        sectionList.addTableColumn(col)
        sectionList.headerView = nil
        sectionList.rowHeight = 36
        sectionList.style = .sourceList
        sectionList.dataSource = self
        sectionList.delegate = self
        sectionList.backgroundColor = .clear
        let ls = NSScrollView()
        ls.documentView = sectionList
        ls.drawsBackground = false
        ls.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(search)
        left.addSubview(ls)

        heading.font = Theme.font(20, weight: .semibold)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(content)
        let rs = NSScrollView()
        rs.documentView = doc
        rs.hasVerticalScroller = true
        rs.drawsBackground = false
        rs.translatesAutoresizingMaskIntoConstraints = false

        let reset = NSButton(title: L10n.t("restoreDefaults"), target: self, action: #selector(resetDefaults))
        let ok = NSButton(title: L10n.t("ok"), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: L10n.t("cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: L10n.t("apply"), target: self, action: #selector(applyPressed))
        let bar = ColorView(Theme.chrome)
        let bs = NSStackView(views: [reset, NSView(), ok, cancel, apply])
        bar.pin(bs, insets: .init(top: 12, left: 16, bottom: 12, right: 16))
        for b in [ok, cancel, apply] { b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true }

        for v in [left, rs, bar] as [NSView] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: 232),
            search.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            ls.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            ls.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            ls.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            ls.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            rs.topAnchor.constraint(equalTo: root.topAnchor),
            rs.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            rs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rs.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            doc.leadingAnchor.constraint(equalTo: rs.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: rs.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: rs.contentView.topAnchor),
            content.topAnchor.constraint(equalTo: doc.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
        ])
        buildRows()
        sectionList.reloadData()
    }

    // MARK: Hàng cài đặt

    private func card(_ title: String, _ subtitle: String?, _ control: NSView?) -> NSView {
        let box = ColorView(Theme.chrome)
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        let t = label(title)
        t.font = Theme.font(13)
        var texts: [NSView] = [t]
        if let s = subtitle { texts.append(label(s, size: 11, color: Theme.secondaryText)) }
        let ts = NSStackView(views: texts)
        ts.orientation = .vertical
        ts.alignment = .leading
        ts.spacing = 2
        let row = NSStackView(views: [ts, NSView()] + (control.map { [$0] } ?? []))
        row.alignment = .centerY
        box.pin(row, insets: .init(top: 12, left: 16, bottom: 12, right: 16))
        box.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return box
    }

    private func add(_ section: Int, _ titleKey: String, _ subKey: String? = nil, _ control: NSView?) {
        let title = L10n.t(titleKey)
        rows.append(Row(section: section, title: title + " " + (subKey.map(L10n.t) ?? ""), view: card(title, subKey.map(L10n.t), control)))
    }

    private func toggle(_ section: Int, _ titleKey: String, _ subKey: String? = nil, get: Bool, set: @escaping (Bool) -> Void) {
        let s = NSSwitch()
        s.state = get ? .on : .off
        commits.append { set(s.state == .on) }
        add(section, titleKey, subKey, s)
    }

    private func popup(_ section: Int, _ titleKey: String, _ subKey: String? = nil, items: [String], selected: Int, set: @escaping (Int) -> Void) {
        let p = NSPopUpButton()
        p.addItems(withTitles: items.map(L10n.t))
        p.selectItem(at: selected)
        p.widthAnchor.constraint(equalToConstant: 160).isActive = true
        commits.append { set(p.indexOfSelectedItem) }
        add(section, titleKey, subKey, p)
    }

    private func button(_ section: Int, _ titleKey: String, _ subKey: String?, buttonKey: String, action: Selector) {
        let b = NSButton(title: L10n.t(buttonKey), target: self, action: action)
        add(section, titleKey, subKey, b)
    }

    private func buildRows() {
        rows = []; commits = []
        // Chung
        popup(0, "language", "languageSub", items: ["langVI", "langEN"], selected: L10n.current == .vi ? 0 : 1) { i in
            let l: AppLanguage = i == 0 ? .vi : .en
            if L10n.current != l { L10n.current = l }
        }
        popup(0, "density", "densitySub", items: ["densityComfort", "densityCompact"], selected: UserDefaults.standard.bool(forKey: "MacMfile.compact") ? 1 : 0) {
            UserDefaults.standard.set($0 == 1, forKey: "MacMfile.compact")
        }
        popup(0, "openAt", nil, items: ["home", "thisMac"], selected: Settings.startPage == SpecialLocation.thisMac ? 1 : 0) {
            Settings.startPage = $0 == 1 ? SpecialLocation.thisMac : SpecialLocation.home
        }
        popup(0, "openFoldersIn", nil, items: ["sameWindow", "newWindowOpt"], selected: Settings.openFoldersInNewWindow ? 1 : 0) {
            Settings.openFoldersInNewWindow = $0 == 1
        }
        toggle(0, "hotkeyToggle", "hotkeyToggleSub", get: Settings.hotKeyEnabled) { Settings.hotKeyEnabled = $0 }
        toggle(0, "restoreWindows", "restoreWindowsSub", get: Settings.restoreSession) { Settings.restoreSession = $0 }
        toggle(0, "tipsAtLaunch", nil, get: Settings.showTips) { Settings.showTips = $0 }
        // Xem
        toggle(1, "hiddenItems", nil, get: UserDefaults.standard.bool(forKey: "MacMfile.showHidden")) { UserDefaults.standard.set($0, forKey: "MacMfile.showHidden") }
        toggle(1, "hideExtensions", nil, get: Settings.hideExtensions) { Settings.hideExtensions = $0 }
        toggle(1, "fullPathTitle", nil, get: Settings.fullPathInTitle) { Settings.fullPathInTitle = $0 }
        toggle(1, "confirmTrashOpt", nil, get: Settings.confirmTrash) { Settings.confirmTrash = $0 }
        popup(1, "backspaceKey", "backspaceKeySub", items: ["backspaceBack", "backspaceTrash"], selected: DeleteKeys.backspaceGoesBack ? 0 : 1) {
            DeleteKeys.backspaceGoesBack = $0 == 0
        }
        button(1, "folderViews", "folderViewsSub", buttonKey: "applyToFolders", action: #selector(applyViewToAll))
        button(1, "resetFolderViews", nil, buttonKey: "resetFolders", action: #selector(resetFolderViews))
        // Ngăn điều hướng
        toggle(2, "showCloud", nil, get: Settings.showCloudInSidebar) { Settings.showCloudInSidebar = $0 }
        toggle(2, "showVolumes", nil, get: Settings.showVolumesInSidebar) { Settings.showVolumesInSidebar = $0 }
        rows.append(Row(section: 2, title: L10n.t("pinnedFolders"), view: listEditor(pinTable, titleKey: "pinnedFolders", add: #selector(addPin), remove: #selector(removePin), up: #selector(pinUp), down: #selector(pinDown))))
        commits.append { [weak self] in if let p = self?.pins, p != Pins.all { Pins.all = p } }
        // Tìm kiếm
        toggle(3, "searchSubfoldersOpt", "searchSubfoldersSub", get: Settings.searchSubfolders) { Settings.searchSubfolders = $0 }
        // Quyền riêng tư
        toggle(4, "showRecentOpt", nil, get: Settings.showRecent) { Settings.showRecent = $0 }
        toggle(4, "showFavoritesOpt", nil, get: Settings.showFavorites) { Settings.showFavorites = $0 }
        button(4, "clearHistory", "clearHistorySub", buttonKey: "clear", action: #selector(clearHistory))
        // Đường dẫn và sao chép
        toggle(5, "quotePathsOpt", "quotePathsSub", get: Settings.quotePaths) { Settings.quotePaths = $0 }
        // Xóa thông tin cá nhân
        rows.append(Row(section: 6, title: L10n.t("autoCleanFolders"), view: listEditor(cleanTable, titleKey: "autoCleanFolders", subKey: "autoCleanSub", add: #selector(addClean), remove: #selector(removeClean))))
        commits.append { [weak self] in if let c = self?.cleanFolders, c != AutoCleanWatcher.folders { AutoCleanWatcher.folders = c } }
        // Phím tắt
        button(7, "shortcutSettings", "shortcutSettingsSub", buttonKey: "openShortcutSettings", action: #selector(openShortcuts))
        toggle(7, "ctrlLikeWindows", "ctrlLikeWindowsSub", get: Settings.ctrlLikeWindows) { Settings.ctrlLikeWindows = $0 }
    }

    private func listEditor(_ table: NSTableView, titleKey: String, subKey: String? = nil, add: Selector, remove: Selector, up: Selector? = nil, down: Selector? = nil) -> NSView {
        let c = NSTableColumn(identifier: .init("p"))
        c.width = 520
        table.addTableColumn(c)
        table.headerView = nil
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        let sc = NSScrollView()
        sc.documentView = table
        sc.hasVerticalScroller = true
        sc.borderType = .bezelBorder
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.heightAnchor.constraint(equalToConstant: 150).isActive = true
        var buttons: [NSView] = [NSButton(title: L10n.t("addFolder"), target: self, action: add),
                                 NSButton(title: L10n.t("removeItem"), target: self, action: remove)]
        if let up, let down {
            buttons += [NSButton(title: L10n.t("moveUp"), target: self, action: up), NSButton(title: L10n.t("moveDown"), target: self, action: down)]
        }
        let t = label(L10n.t(titleKey))
        t.font = Theme.font(13)
        var views: [NSView] = [t]
        if let subKey { views.append(label(L10n.t(subKey), size: 11, color: Theme.secondaryText)) }
        views += [sc, NSStackView(views: buttons)]
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        sc.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true
        let box = ColorView(Theme.chrome)
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        box.pin(s, insets: .init(top: 12, left: 16, bottom: 12, right: 16))
        return box
    }

    private func select(_ section: Int) {
        current = section
        if sectionList.selectedRow != section { sectionList.selectRowIndexes([section], byExtendingSelection: false) }
        showRows()
    }

    private func showRows() {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        let list: [Row]
        if q.isEmpty {
            heading.stringValue = L10n.t(sectionKeys[current])
            list = rows.filter { $0.section == current }
        } else {
            heading.stringValue = L10n.f("searchResultsFor", q)
            list = rows.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        content.addArrangedSubview(heading)
        content.setCustomSpacing(16, after: heading)
        for r in list {
            content.addArrangedSubview(r.view)
            r.view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        if list.isEmpty { content.addArrangedSubview(label(L10n.t("noSettingsFound"), color: Theme.secondaryText)) }
    }

    func controlTextDidChange(_ obj: Notification) { showRows() }

    // MARK: Bảng

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === sectionList { return sectionKeys.count }
        return tableView === pinTable ? pins.count : cleanFolders.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableView === sectionList { text = L10n.t(sectionKeys[row]) }
        else { text = tableView === pinTable ? pins[row] : cleanFolders[row] }
        let l = label(text)
        l.font = Theme.font(tableView === sectionList ? 13 : 12)
        l.lineBreakMode = .byTruncatingMiddle
        let c = NSTableCellView()
        c.addSubview(l)
        NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
                                     l.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8),
                                     l.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
        return c
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === sectionList, sectionList.selectedRow >= 0 else { return }
        search.stringValue = ""
        current = sectionList.selectedRow
        showRows()
    }

    // MARK: Hành động

    private func chooseFolder(_ done: @escaping (String) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        guard let w = window else { return }
        p.beginSheetModal(for: w) { r in if r == .OK, let u = p.url { done(u.path) } }
    }
    @objc private func addPin() { chooseFolder { [weak self] p in if self?.pins.contains(p) == false { self?.pins.append(p); self?.pinTable.reloadData() } } }
    @objc private func removePin() { let r = pinTable.selectedRow; if r >= 0 { pins.remove(at: r); pinTable.reloadData() } }
    @objc private func pinUp() { let r = pinTable.selectedRow; if r > 0 { pins.swapAt(r, r - 1); pinTable.reloadData(); pinTable.selectRowIndexes([r - 1], byExtendingSelection: false) } }
    @objc private func pinDown() { let r = pinTable.selectedRow; if r >= 0 && r < pins.count - 1 { pins.swapAt(r, r + 1); pinTable.reloadData(); pinTable.selectRowIndexes([r + 1], byExtendingSelection: false) } }
    @objc private func addClean() { chooseFolder { [weak self] p in if self?.cleanFolders.contains(p) == false { self?.cleanFolders.append(p); self?.cleanTable.reloadData() } } }
    @objc private func removeClean() { let r = cleanTable.selectedRow; if r >= 0 { cleanFolders.remove(at: r); cleanTable.reloadData() } }

    private var activeBrowser: BrowserViewController? {
        (NSApp.mainWindow?.windowController as? MainWindowController)?.browser
            ?? (NSApp.windows.compactMap { $0.windowController as? MainWindowController }.first)?.browser
    }
    @objc private func applyViewToAll() {
        guard let b = activeBrowser else { return }
        UserDefaults.standard.set(b.viewMode.rawValue, forKey: "MacMfile.defaultView")
        UserDefaults.standard.removeObject(forKey: "MacMfile.viewModes")
        Settings.changed()
    }
    @objc private func resetFolderViews() {
        UserDefaults.standard.removeObject(forKey: "MacMfile.viewModes")
        UserDefaults.standard.removeObject(forKey: "MacMfile.defaultView")
        Settings.changed()
    }
    @objc private func clearHistory() {
        Settings.recentClearedAt = Date()
        Settings.changed()
    }
    @objc private func openShortcuts() { ShortcutsWindowController.show() }

    @objc private func okPressed() { applyPressed(); close() }
    @objc private func cancelPressed() { close() }
    @objc private func applyPressed() {
        commits.forEach { $0() }
        Settings.changed()
    }
    @objc private func resetDefaults() {
        let a = NSAlert()
        a.messageText = L10n.t("restoreDefaultsAsk")
        a.addButton(withTitle: L10n.t("restoreDefaults"))
        a.addButton(withTitle: L10n.t("cancel"))
        guard let w = window else { return }
        a.beginSheetModal(for: w) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            Settings.resetAll()
            self.pins = Pins.all
            self.cleanFolders = AutoCleanWatcher.folders
            self.buildRows()
            self.pinTable.reloadData(); self.cleanTable.reloadData()
            self.showRows()
        }
    }
}
