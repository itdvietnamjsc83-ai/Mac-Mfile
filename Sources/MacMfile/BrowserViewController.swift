import AppKit
import Quartz
import MfileCore

/// Một tab duyệt thư mục: nút điều hướng, thanh địa chỉ, ô tìm kiếm, thanh lệnh, ngăn điều hướng,
/// vùng nội dung chế độ Chi tiết và thanh trạng thái (9 vùng ở Mục 4).
final class BrowserViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSSearchFieldDelegate, NSMenuDelegate, QLPreviewPanelDataSource {

    private(set) var history: NavigationHistory
    var currentPath: String { history.current }
    var onLocationChange: ((String, String) -> Void)?

    private var allItems: [FileItem] = []
    private var items: [FileItem] = []
    private var sortKey: SortKey = .name
    private var ascending = true
    private var showHidden = UserDefaults.standard.bool(forKey: "MacMfile.showHidden")
    private static var cutPaths: [String] = []

    let table = FileTableView()
    private let sidebar = SidebarController()
    private let address = AddressField()
    private let search = NSSearchField()
    private let status = label("")
    private let message = label("", color: Theme.accent)
    private let langButton = FlatButton(title: "VI", symbol: nil, target: nil, action: nil)
    private var backB: FlatButton!, fwdB: FlatButton!, upB: FlatButton!, refreshB: FlatButton!
    private var commandButtons: [(FlatButton, String)] = []
    private var messageTimer: Timer?

    init(startPath: String) {
        history = NavigationHistory(start: startPath)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Dựng giao diện

    override func loadView() {
        let root = ColorView(.white)
        root.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)

        let nav = buildNavBar()
        let cmd = buildCommandBar()
        let body = NSSplitView()
        body.isVertical = true
        body.dividerStyle = .thin
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(sidebar.scroll)
        body.addArrangedSubview(buildTable())
        sidebar.scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        let statusBar = buildStatusBar()

        for v in [nav, cmd, body, statusBar] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: root.topAnchor),
            nav.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            nav.heightAnchor.constraint(equalToConstant: 44),
            cmd.topAnchor.constraint(equalTo: nav.bottomAnchor),
            cmd.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            cmd.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            cmd.heightAnchor.constraint(equalToConstant: 46),
            body.topAnchor.constraint(equalTo: cmd.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
        view = root
        body.setPosition(220, ofDividerAt: 0)

        sidebar.onSelect = { [weak self] p in self?.navigate(to: p) }
        sidebar.onOpenNewWindow = { p in (NSApp.delegate as? AppDelegate)?.openWindow(at: p) }
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: L10n.didChangeNotification, object: nil)
        reloadTexts()
        load()
    }

    private func buildNavBar() -> NSView {
        let bar = ColorView(Theme.chrome)
        backB = FlatButton(title: "", symbol: "arrow.left", target: self, action: #selector(goBack(_:)))
        fwdB = FlatButton(title: "", symbol: "arrow.right", target: self, action: #selector(goForward(_:)))
        upB = FlatButton(title: "", symbol: "arrow.up", target: self, action: #selector(goUp(_:)))
        refreshB = FlatButton(title: "", symbol: "arrow.clockwise", target: self, action: #selector(refresh(_:)))
        for b in [backB!, fwdB!, upB!, refreshB!] { b.widthAnchor.constraint(equalToConstant: 32).isActive = true }

        address.font = Theme.font(12)
        address.bezelStyle = .roundedBezel
        address.focusRingType = .exterior
        address.delegate = self
        address.target = self
        address.action = #selector(addressEntered(_:))
        address.cell?.sendsActionOnEndEditing = false
        address.lineBreakMode = .byTruncatingHead
        address.translatesAutoresizingMaskIntoConstraints = false
        let addrMenu = NSMenu()
        addrMenu.addItem(NSMenuItem(title: "", action: #selector(copyAddress(_:)), keyEquivalent: ""))
        addrMenu.addItem(NSMenuItem(title: "", action: #selector(editAddress(_:)), keyEquivalent: ""))
        addrMenu.addItem(NSMenuItem(title: "", action: #selector(pasteAndGo(_:)), keyEquivalent: ""))
        addrMenu.items.forEach { $0.target = self }
        address.menu = addrMenu

        search.font = Theme.font(12)
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.translatesAutoresizingMaskIntoConstraints = false
        search.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let stack = NSStackView(views: [backB, fwdB, upB, refreshB, address, search])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.pin(stack, insets: .init(top: 7, left: 10, bottom: 7, right: 10))
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return bar
    }

    private func buildCommandBar() -> NSView {
        let bar = ColorView(Theme.chrome)
        bar.bottomBorder = true
        func b(_ key: String, _ symbol: String, _ sel: Selector) -> FlatButton {
            let x = FlatButton(title: L10n.t(key), symbol: symbol, target: self, action: sel)
            commandButtons.append((x, key))
            return x
        }
        func sep() -> NSView {
            let v = ColorView(Theme.border)
            v.widthAnchor.constraint(equalToConstant: 1).isActive = true
            v.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return v
        }
        let newB = b("new", "plus.circle.fill", #selector(showNewMenu(_:)))
        newB.contentTintColor = Theme.accent
        let views: [NSView] = [
            newB, sep(),
            b("cut", "scissors", #selector(cut(_:))),
            b("copy", "doc.on.doc", #selector(copy(_:))),
            b("paste", "doc.on.clipboard", #selector(paste(_:))),
            b("rename", "character.cursor.ibeam", #selector(renameSelected(_:))),
            b("share", "square.and.arrow.up", #selector(shareSelected(_:))),
            b("delete", "trash", #selector(trashSelected(_:))),
            sep(),
            b("sort", "arrow.up.arrow.down", #selector(showSortMenu(_:))),
            b("view", "list.bullet", #selector(showViewMenu(_:))),
            b("seeMore", "ellipsis", #selector(showMoreMenu(_:))),
        ]
        let stack = NSStackView(views: views)
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -10),
        ])
        return bar
    }

    private func buildTable() -> NSView {
        let columns: [(String, String, CGFloat)] = [("name", "colName", 380), ("modified", "colModified", 150), ("type", "colType", 140), ("size", "colSize", 90)]
        for (id, _, w) in columns {
            let c = NSTableColumn(identifier: .init(id))
            c.width = w
            c.minWidth = 60
            c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(c)
        }
        table.rowHeight = Theme.rowHeight
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected(_:))
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        table.registerForDraggedTypes([.fileURL])
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        table.onOpen = { [weak self] in self?.openSelected(nil) }
        table.onTrash = { [weak self] in self?.trashSelected(nil) }
        table.onDeleteForever = { [weak self] in self?.deleteForever(nil) }
        table.onRename = { [weak self] in self?.renameSelected(nil) }
        table.onQuickLook = { [weak self] in self?.quickLook(nil) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    private func buildStatusBar() -> NSView {
        let bar = ColorView(.white)
        langButton.target = self
        langButton.action = #selector(toggleLanguage(_:))
        langButton.font = Theme.font(11, weight: .semibold)
        let stack = NSStackView(views: [status, message, NSView(), langButton])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.pin(stack, insets: .init(top: 0, left: 12, bottom: 0, right: 8))
        langButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return bar
    }

    // MARK: Ngôn ngữ

    @objc private func languageChanged() {
        reloadTexts()
        table.reloadData()
        updateLocationUI()
        updateStatus()
    }

    private func reloadTexts() {
        for (b, key) in commandButtons { b.title = L10n.t(key); b.toolTip = L10n.t(key); b.invalidateIntrinsicContentSize() }
        backB.toolTip = L10n.t("back") + " (Cmd+[)"
        fwdB.toolTip = L10n.t("forward") + " (Cmd+])"
        upB.toolTip = L10n.t("up") + " (Cmd+↑)"
        refreshB.toolTip = L10n.t("refresh") + " (F5)"
        let headers = ["name": "colName", "modified": "colModified", "type": "colType", "size": "colSize"]
        for c in table.tableColumns { c.title = L10n.t(headers[c.identifier.rawValue] ?? "") }
        if let m = address.menu {
            m.items[0].title = L10n.t("copyAddress")
            m.items[1].title = L10n.t("editAddress")
            m.items[2].title = L10n.t("pasteAndGo")
        }
        langButton.title = L10n.current == .vi ? "VI" : "EN"
        langButton.toolTip = L10n.t("language")
    }

    @objc func toggleLanguage(_ sender: Any?) { L10n.current = L10n.current.toggled }

    // MARK: Điều hướng

    func navigate(to path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            showError(L10n.f("pathNotFound", path)); return
        }
        if !isDir.boolValue {
            // Dán đường dẫn của tệp: mở thư mục chứa và chọn sẵn tệp đó.
            let parent = (path as NSString).deletingLastPathComponent
            history.visit(parent)
            load(selecting: [path])
            return
        }
        history.visit(path)
        load()
    }

    func load(selecting: [String] = []) {
        search.stringValue = ""
        do {
            allItems = try DirectoryReader.list(currentPath, showHidden: showHidden)
        } catch {
            allItems = []
            showMessage(error.localizedDescription)
        }
        applySortAndFilter()
        if !selecting.isEmpty {
            let rows = IndexSet(items.indices.filter { selecting.contains(items[$0].path) })
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if let r = rows.first { table.scrollRowToVisible(r) }
        }
        updateLocationUI()
        sidebar.select(path: currentPath)
        updateStatus()
    }

    private func applySortAndFilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        var list = allItems
        if !q.isEmpty {
            list = list.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        items = FileSorting.sort(list, by: sortKey, ascending: ascending)
        table.reloadData()
    }

    private func updateLocationUI() {
        let crumbs = Breadcrumb.crumbs(for: currentPath)
        address.realPath = currentPath
        address.displayText = crumbs.map(\.title).joined(separator: "  ›  ")
        let title = crumbs.last?.title ?? currentPath
        search.placeholderString = L10n.f("searchIn", title)
        backB.isEnabled = history.canGoBack
        fwdB.isEnabled = history.canGoForward
        upB.isEnabled = NavigationHistory.parent(of: currentPath) != nil
        onLocationChange?(title, currentPath)
    }

    func reloadTitle() { updateLocationUI() }

    private func updateStatus() {
        var s = L10n.f("items", Formatting.group(Int64(items.count)))
        let sel = selectedItems
        if !sel.isEmpty {
            s += "    " + L10n.f("selected", sel.count)
            let files = sel.filter { !$0.isDirectory }
            if !files.isEmpty { s += " · " + Formatting.size(files.reduce(0) { $0 + $1.size }) }
        }
        status.stringValue = s
        if items.isEmpty && search.stringValue.isEmpty { status.stringValue += "    " + L10n.t("emptyFolder") }
    }

    private func showMessage(_ text: String) {
        message.stringValue = text
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.message.stringValue = ""
        }
    }

    private func showError(_ text: String) {
        let a = NSAlert()
        a.messageText = L10n.t("errorTitle")
        a.informativeText = text
        a.addButton(withTitle: L10n.t("ok"))
        if let w = view.window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    @objc func goBack(_ sender: Any?) { if history.back() != nil { load() } }
    @objc func goForward(_ sender: Any?) { if history.forward() != nil { load() } }
    @objc func goUp(_ sender: Any?) {
        let old = currentPath
        if let p = NavigationHistory.parent(of: currentPath) { history.visit(p); load(selecting: [old]) }
    }
    @objc func refresh(_ sender: Any?) {
        let sel = selectedItems.map(\.path)
        load(selecting: sel)
    }
    @objc func goHome(_ sender: Any?) { navigate(to: NSHomeDirectory()) }
    @objc func goThisMac(_ sender: Any?) { navigate(to: "/") }

    // MARK: Thanh địa chỉ (Mục 5.13)

    @objc func focusAddress(_ sender: Any?) { view.window?.makeFirstResponder(address) }
    @objc func editAddress(_ sender: Any?) { focusAddress(sender) }

    @objc func addressEntered(_ sender: Any?) {
        let text = address.stringValue
        view.window?.makeFirstResponder(table)
        switch PathParser.parse(text) {
        case .empty: address.restoreDisplay()
        case .remote(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
            address.restoreDisplay()
        case .local(let p):
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
                navigate(to: p)
            } else {
                showError(L10n.f("pathNotFound", p))
                address.restoreDisplay()
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? AddressField) === address { address.restoreDisplay() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === address, commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            address.restoreDisplay()
            view.window?.makeFirstResponder(table)
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === search {
            applySortAndFilter()
            updateStatus()
        }
    }

    @objc func copyAddress(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentPath, forType: .string)
    }

    @objc func pasteAndGo(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        address.stringValue = s
        addressEntered(nil)
    }

    @objc func focusSearch(_ sender: Any?) { view.window?.makeFirstResponder(search) }

    // MARK: Bảng Chi tiết

    var selectedItems: [FileItem] { table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil } }

    private var targetItems: [FileItem] {
        let clicked = table.clickedRow
        if clicked >= 0 && !table.selectedRowIndexes.contains(clicked) { return [items[clicked]] }
        return selectedItems
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let it = items[row]
        let cell = NSTableCellView()
        let t: NSTextField
        switch id {
        case "name":
            t = label(it.name)
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: it.path))
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            ])
            if Self.cutPaths.contains(it.path) { icon.alphaValue = 0.5 }
        case "modified": t = label(Formatting.date(it.modified), color: Theme.secondaryText)
        case "type": t = label(it.typeDescription(), color: Theme.secondaryText)
        default:
            t = label(it.isDirectory ? "" : Formatting.size(it.size), color: Theme.secondaryText)
            t.alignment = .right
        }
        cell.addSubview(t)
        cell.textField = t
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: id == "name" ? 34 : 8),
            t.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            t.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let d = tableView.sortDescriptors.first, let key = d.key, let k = SortKey(rawValue: key) else { return }
        sortKey = k
        ascending = d.ascending
        let sel = selectedItems.map(\.path)
        applySortAndFilter()
        table.selectRowIndexes(IndexSet(items.indices.filter { sel.contains(items[$0].path) }), byExtendingSelection: false)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().reloadData() }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        URL(fileURLWithPath: items[row].path) as NSURL
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        if op == .on, items.indices.contains(row), !items[row].isDirectory { tableView.setDropRow(-1, dropOperation: .on) }
        if op == .above { tableView.setDropRow(-1, dropOperation: .on) }
        // Windows: cùng ổ thì di chuyển, khác ổ thì sao chép; giữ Option để sao chép.
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let dest = (row >= 0 && items.indices.contains(row) && items[row].isDirectory) ? items[row].path : currentPath
        transfer(urls.map(\.path), to: dest, move: !NSEvent.modifierFlags.contains(.option))
        return true
    }

    // MARK: Menu chuột phải (Mục 5.3)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        func add(_ key: String, _ sel: Selector, _ shortcut: String = "") {
            let it = NSMenuItem(title: L10n.t(key) + (shortcut.isEmpty ? "" : "\t" + shortcut), action: sel, keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }
        if row < 0 {
            // Vùng trống
            add("refresh", #selector(refresh(_:)), "F5")
            add("paste", #selector(paste(_:)), "Cmd+V")
            add("newFolderName", #selector(newFolder(_:)), "Cmd+Shift+N")
            menu.addItem(.separator())
            add("copyAddress", #selector(copyAddress(_:)))
            return
        }
        let target = targetItems
        add("open", #selector(openSelected(_:)), "Enter")
        if target.count == 1, target[0].isDirectory {
            add("openNewWindow", #selector(openInNewWindow(_:)))
            add("pinQuick", #selector(pinSelected(_:)), "Cmd+Shift+P")
        }
        menu.addItem(.separator())
        add("cut", #selector(cut(_:)), "Cmd+X")
        add("copy", #selector(copy(_:)), "Cmd+C")
        add("rename", #selector(renameSelected(_:)), "F2")
        add("share", #selector(shareSelected(_:)))
        add("delete", #selector(trashSelected(_:)), "⌫")
        menu.addItem(.separator())
        add("copyPath", #selector(copyPath(_:)), "Cmd+Shift+C")
        add("properties", #selector(showInfo(_:)), "Option+Enter")
    }

    // MARK: Lệnh tệp và thư mục

    @objc func openSelected(_ sender: Any?) {
        let sel = targetItems
        if sel.count == 1, sel[0].isDirectory { navigate(to: sel[0].path); return }
        for it in sel {
            if it.isDirectory { (NSApp.delegate as? AppDelegate)?.openWindow(at: it.path) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: it.path)) }
        }
    }

    @objc func openInNewWindow(_ sender: Any?) {
        for it in targetItems where it.isDirectory { (NSApp.delegate as? AppDelegate)?.openWindow(at: it.path) }
    }

    @objc func pinSelected(_ sender: Any?) {
        let dirs = targetItems.filter(\.isDirectory)
        if dirs.isEmpty { Pins.pin(currentPath) } else { dirs.forEach { Pins.pin($0.path) } }
    }

    @objc func openPin(_ sender: NSMenuItem) {
        let pins = Pins.all
        guard pins.indices.contains(sender.tag) else { return }
        navigate(to: pins[sender.tag])
    }

    @objc func copyPath(_ sender: Any?) {
        let paths = targetItems.isEmpty ? [currentPath] : targetItems.map(\.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PathParser.copyText(for: paths), forType: .string)
        showMessage(L10n.f("copiedPaths", paths.count))
    }

    @objc func copy(_ sender: Any?) { writeToPasteboard(cut: false) }
    @objc func cut(_ sender: Any?) { writeToPasteboard(cut: true) }

    private func writeToPasteboard(cut: Bool) {
        let sel = targetItems
        guard !sel.isEmpty else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(sel.map { URL(fileURLWithPath: $0.path) as NSURL })
        Self.cutPaths = cut ? sel.map(\.path) : []
        table.reloadData()
    }

    @objc func paste(_ sender: Any?) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { NSSound.beep(); return }
        let paths = urls.map(\.path)
        let move = !Self.cutPaths.isEmpty && Set(Self.cutPaths) == Set(paths)
        transfer(paths, to: currentPath, move: move)
        if move { Self.cutPaths = [] }
    }

    /// Sao chép hoặc di chuyển; trùng tên thì giữ cả hai bằng cách thêm " (2)" (hộp thoại trùng tên đầy đủ ở bước sau).
    private func transfer(_ paths: [String], to dest: String, move: Bool) {
        let fm = FileManager.default
        var done: [String] = []
        for src in paths {
            let name = (src as NSString).lastPathComponent
            if move && (src as NSString).deletingLastPathComponent == dest { continue }
            if move && (dest == src || dest.hasPrefix(src + "/")) { continue }
            let target = uniquePath(in: dest, name: name)
            do {
                if move { try fm.moveItem(atPath: src, toPath: target) } else { try fm.copyItem(atPath: src, toPath: target) }
                done.append(target)
            } catch {
                showError(error.localizedDescription)
                break
            }
        }
        if dest == currentPath { load(selecting: done) } else { refresh(nil) }
    }

    private func uniquePath(in dir: String, name: String) -> String {
        let fm = FileManager.default
        var candidate = (dir as NSString).appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate) else { return candidate }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = (dir as NSString).appendingPathComponent(newName)
            n += 1
        } while fm.fileExists(atPath: candidate)
        return candidate
    }

    @objc func newFolder(_ sender: Any?) {
        let path = uniquePath(in: currentPath, name: L10n.t("newFolderName"))
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            load(selecting: [path])
            renameSelected(nil)
        } catch { showError(error.localizedDescription) }
    }

    @objc func renameSelected(_ sender: Any?) {
        guard let it = targetItems.first, let window = view.window else { NSSound.beep(); return }
        let a = NSAlert()
        a.messageText = L10n.f("renameTitle", it.name)
        let field = NSTextField(string: it.name)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        a.accessoryView = field
        a.addButton(withTitle: L10n.t("ok"))
        a.addButton(withTitle: L10n.t("cancel"))
        a.window.initialFirstResponder = field
        a.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
            guard !newName.isEmpty, newName != it.name else { return }
            let dest = ((it.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(atPath: it.path, toPath: dest)
                self.load(selecting: [dest])
            } catch { self.showError(error.localizedDescription) }
        }
        // Chọn sẵn phần tên, không chọn phần mở rộng, giống Windows.
        DispatchQueue.main.async {
            let ext = (it.name as NSString).pathExtension
            let len = it.isDirectory || ext.isEmpty ? (it.name as NSString).length : (it.name as NSString).length - (ext as NSString).length - 1
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: max(0, len))
        }
    }

    @objc func shareSelected(_ sender: Any?) {
        let urls = targetItems.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { NSSound.beep(); return }
        let picker = NSSharingServicePicker(items: urls)
        let anchor = (sender as? NSView) ?? table
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// Phím delete (⌫): chuyển vào Thùng rác.
    @objc func trashSelected(_ sender: Any?) {
        let sel = targetItems
        guard !sel.isEmpty else { NSSound.beep(); return }
        let defaultsKey = "MacMfile.skipTrashConfirm"
        let perform = { [weak self] in
            guard let self else { return }
            var moved = 0
            for it in sel {
                do { try FileManager.default.trashItem(at: URL(fileURLWithPath: it.path), resultingItemURL: nil); moved += 1 }
                catch { self.showError(error.localizedDescription); break }
            }
            self.load()
            self.showMessage(L10n.f("movedToTrash", moved))
        }
        if UserDefaults.standard.bool(forKey: defaultsKey) || sel.count == 1 { perform(); return }
        let a = NSAlert()
        a.messageText = L10n.f("confirmTrash", sel.count)
        a.addButton(withTitle: L10n.t("yes"))
        a.addButton(withTitle: L10n.t("no"))
        a.showsSuppressionButton = true
        guard let w = view.window else { return }
        a.beginSheetModal(for: w) { resp in
            if a.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: defaultsKey) }
            if resp == .alertFirstButtonReturn { perform() }
        }
    }

    /// Shift+delete: xóa vĩnh viễn, luôn hỏi xác nhận.
    @objc func deleteForever(_ sender: Any?) {
        let sel = targetItems
        guard !sel.isEmpty, let w = view.window else { NSSound.beep(); return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L10n.f("confirmDeleteForever", sel.count)
        a.informativeText = L10n.t("deleteForeverNote")
        a.addButton(withTitle: L10n.t("cancel"))
        a.addButton(withTitle: L10n.t("deleteForever"))
        a.beginSheetModal(for: w) { [weak self] resp in
            guard let self, resp == .alertSecondButtonReturn else { return }
            for it in sel {
                do { try FileManager.default.removeItem(atPath: it.path) } catch { self.showError(error.localizedDescription); break }
            }
            self.load()
        }
    }

    @objc func showInfo(_ sender: Any?) {
        // Hộp thoại Thuộc tính kiểu Windows (Mục 5.11) làm ở bước sau; tạm mở bảng Thông tin của macOS.
        let urls = targetItems.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func selectAllItems(_ sender: Any?) { table.selectAll(sender) }

    // MARK: Menu thả của thanh lệnh

    private func popUp(_ menu: NSMenu, from sender: Any?) {
        guard let v = sender as? NSView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: v.bounds.height + 4), in: v)
    }

    @objc func showNewMenu(_ sender: Any?) {
        let m = NSMenu()
        let it = NSMenuItem(title: L10n.t("newFolder") + "\tCmd+Shift+N", action: #selector(newFolder(_:)), keyEquivalent: "")
        it.target = self
        m.addItem(it)
        popUp(m, from: sender)
    }

    @objc func showSortMenu(_ sender: Any?) {
        let m = NSMenu()
        for (k, key) in [(SortKey.name, "colName"), (.modified, "colModified"), (.type, "colType"), (.size, "colSize")] {
            let it = NSMenuItem(title: L10n.t(key), action: #selector(sortBy(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = k.rawValue
            it.state = sortKey == k ? .on : .off
            m.addItem(it)
        }
        popUp(m, from: sender)
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let k = SortKey(rawValue: raw) else { return }
        if sortKey == k { ascending.toggle() } else { sortKey = k; ascending = true }
        table.sortDescriptors = [NSSortDescriptor(key: k.rawValue, ascending: ascending)]
    }

    @objc func showViewMenu(_ sender: Any?) {
        let m = NSMenu()
        let details = NSMenuItem(title: L10n.t("details"), action: nil, keyEquivalent: "")
        details.state = .on
        m.addItem(details)
        m.addItem(.separator())
        let hidden = NSMenuItem(title: L10n.current == .vi ? "Mục ẩn" : "Hidden items", action: #selector(toggleHidden(_:)), keyEquivalent: "")
        hidden.target = self
        hidden.state = showHidden ? .on : .off
        m.addItem(hidden)
        popUp(m, from: sender)
    }

    @objc func toggleHidden(_ sender: Any?) {
        showHidden.toggle()
        UserDefaults.standard.set(showHidden, forKey: "MacMfile.showHidden")
        refresh(nil)
    }

    @objc func showMoreMenu(_ sender: Any?) {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            m.addItem(it)
        }
        add(L10n.t("pinQuick") + "\tCmd+Shift+P", #selector(pinSelected(_:)))
        add(L10n.t("selectAll") + "\tCmd+A", #selector(selectAllItems(_:)))
        add(L10n.t("copyPath") + "\tCmd+Shift+C", #selector(copyPath(_:)))
        add(L10n.t("properties") + "\tOption+Enter", #selector(showInfo(_:)))
        m.addItem(.separator())
        add(L10n.t("language"), #selector(toggleLanguage(_:)))
        popUp(m, from: sender)
    }

    // MARK: Xem nhanh bằng phím cách (Quick Look)

    @objc func quickLook(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedItems.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        URL(fileURLWithPath: selectedItems[index].path) as NSURL
    }
}
