import AppKit
import Quartz
import UniformTypeIdentifiers
import MfileCore

/// Một tab duyệt thư mục: nút điều hướng, thanh địa chỉ, ô tìm kiếm, thanh lệnh, ngăn điều hướng,
/// vùng nội dung chế độ Chi tiết và thanh trạng thái (9 vùng ở Mục 4).
final class BrowserViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSSearchFieldDelegate, NSMenuDelegate, QLPreviewPanelDataSource,
    NSCollectionViewDataSource, NSCollectionViewDelegate {

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
    let collection = FileCollectionView()
    private let flow = NSCollectionViewFlowLayout()
    private var tableScroll: NSScrollView!
    private var collectionScroll: NSScrollView!
    private(set) var viewMode: ViewMode = .details
    private var compact = UserDefaults.standard.bool(forKey: "MacMfile.compact")
    private var detailsToggle: FlatButton!, iconsToggle: FlatButton!
    private let sidebar = SidebarController()
    private let sidePane = SidePaneController()
    private let specialPage = SpecialPageController()
    var isSpecialPage: Bool { SpecialLocation.isSpecial(currentPath) }
    private var body: NSSplitView!
    private var paneButton: FlatButton!
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
        body.addArrangedSubview(sidePane.view)
        self.body = body
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
        sidebar.onOpenNewTab = { [weak self] p in (self?.view.window?.windowController as? MainWindowController)?.addTab(path: p) }
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: L10n.didChangeNotification, object: nil)
        reloadTexts()
        setViewMode(viewPrefs.mode(for: currentPath), remember: false)
        if let k = UserDefaults.standard.string(forKey: "MacMfile.sidePane").flatMap(SidePaneKind.init(rawValue:)), k != .none {
            DispatchQueue.main.async { self.showPane(k) }
        }
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
        // Nút "Chi tiết" ở góc phải thanh lệnh như Windows 11: bật/tắt ngăn chi tiết.
        paneButton = b("details", "sidebar.right", #selector(toggleDetailsPane(_:)))
        bar.addSubview(paneButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: paneButton.leadingAnchor, constant: -10),
            paneButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            paneButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
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
        table.onProperties = { [weak self] in self?.showInfo(nil) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll = scroll

        flow.minimumInteritemSpacing = 2
        flow.minimumLineSpacing = 2
        flow.sectionInset = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        collection.collectionViewLayout = flow
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.white]
        collection.register(FileCellItem.self, forItemWithIdentifier: FileCellItem.id)
        collection.dataSource = self
        collection.delegate = self
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collection.registerForDraggedTypes([.fileURL])
        let cmenu = NSMenu()
        cmenu.delegate = self
        collection.menu = cmenu
        collection.onOpen = { [weak self] in self?.openSelected(nil) }
        collection.onTrash = { [weak self] in self?.trashSelected(nil) }
        collection.onDeleteForever = { [weak self] in self?.deleteForever(nil) }
        collection.onRename = { [weak self] in self?.renameSelected(nil) }
        collection.onQuickLook = { [weak self] in self?.quickLook(nil) }
        collection.onProperties = { [weak self] in self?.showInfo(nil) }
        let cs = NSScrollView()
        cs.documentView = collection
        cs.hasVerticalScroller = true
        cs.hasHorizontalScroller = true
        cs.autohidesScrollers = true
        cs.translatesAutoresizingMaskIntoConstraints = false
        cs.isHidden = true
        cs.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(contentResized), name: NSView.frameDidChangeNotification, object: cs)
        collectionScroll = cs

        let container = ColorView(.white)
        container.pin(scroll, insets: .init())
        container.pin(cs, insets: .init())
        container.pin(specialPage.scroll, insets: .init())
        specialPage.onOpen = { [weak self] p in self?.openPath(p) }
        specialPage.onReveal = { [weak self] p in self?.navigate(to: p) }
        specialPage.onOpenNewTab = { [weak self] p in (self?.view.window?.windowController as? MainWindowController)?.addTab(path: p) }
        specialPage.onOpenNewWindow = { p in (NSApp.delegate as? AppDelegate)?.openWindow(at: p) }
        specialPage.onSelectionChange = { [weak self] _ in self?.selectionChanged() }
        return container
    }

    // MARK: Ngăn chi tiết / xem trước (FR-07)

    var paneKind: SidePaneKind { sidePane.kind }

    func showPane(_ k: SidePaneKind) {
        let newKind = sidePane.kind == k ? SidePaneKind.none : k
        sidePane.show(newKind)
        UserDefaults.standard.set(newKind.rawValue, forKey: "MacMfile.sidePane")
        paneButton.isActive = newKind == .details
        sidePane.update(selection: selectedItems, folder: currentPath)
        body.layoutSubtreeIfNeeded()
        let w = body.bounds.width
        body.setPosition(newKind == .none ? w : max(400, w - 300), ofDividerAt: 1)
    }

    @objc func toggleDetailsPane(_ sender: Any?) { showPane(.details) }
    @objc func togglePreviewPane(_ sender: Any?) { showPane(.preview) }

    // MARK: Chế độ xem (FR-06, FR-21)

    private static let modesKey = "MacMfile.viewModes"
    private static let defaultModeKey = "MacMfile.defaultView"

    private var viewPrefs: ViewPreferences {
        get {
            let d = UserDefaults.standard
            let def = d.string(forKey: Self.defaultModeKey).flatMap(ViewMode.init(rawValue:)) ?? .details
            return ViewPreferences(defaultMode: def, perFolder: d.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:])
        }
        set {
            UserDefaults.standard.set(newValue.perFolder, forKey: Self.modesKey)
            UserDefaults.standard.set(newValue.defaultMode.rawValue, forKey: Self.defaultModeKey)
        }
    }

    /// Đổi chế độ xem cho thư mục hiện tại và ghi nhớ (như Windows nhớ theo từng thư mục).
    func setViewMode(_ mode: ViewMode, remember: Bool = true) {
        let keep = selectionIndexes
        let hadFocus = view.window?.firstResponder === table || view.window?.firstResponder === collection
        viewMode = mode
        if remember { var p = viewPrefs; p.set(mode, for: currentPath); viewPrefs = p }
        let isTable = mode == .details
        tableScroll.isHidden = !isTable || isSpecialPage
        collectionScroll.isHidden = isTable || isSpecialPage
        table.rowHeight = compact ? 24 : Theme.rowHeight
        updateFlowLayout()
        reloadContent()
        selectIndexes(keep, scroll: true)
        if hadFocus { view.window?.makeFirstResponder(isTable ? table : collection) }
        detailsToggle?.isActive = isTable
        iconsToggle?.isActive = mode == .largeIcons
    }

    @objc func setViewModeFromMenu(_ sender: NSMenuItem) {
        let all = ViewMode.allCases
        if all.indices.contains(sender.tag) { setViewMode(all[sender.tag]) }
    }
    @objc func viewDetails(_ sender: Any?) { setViewMode(.details) }
    @objc func viewLargeIcons(_ sender: Any?) { setViewMode(.largeIcons) }

    @objc func toggleCompact(_ sender: Any?) {
        compact.toggle()
        UserDefaults.standard.set(compact, forKey: "MacMfile.compact")
        setViewMode(viewMode, remember: false)
    }
    var isCompact: Bool { compact }
    var isShowingHidden: Bool { showHidden }

    @objc private func contentResized() { updateFlowLayout() }

    private func updateFlowLayout() {
        let size = viewMode.itemSize(compact: compact)
        flow.scrollDirection = viewMode.flowsInColumns ? .horizontal : .vertical
        let fullWidth = max(200, collectionScroll.contentSize.width - 18)
        flow.itemSize = NSSize(width: size.width == 0 ? fullWidth : size.width, height: size.height)
        flow.minimumLineSpacing = viewMode == .content ? 0 : 2
        flow.invalidateLayout()
    }

    private func reloadContent() {
        if viewMode == .details { table.reloadData() } else { collection.reloadData() }
    }

    /// Chỉ số các mục đang chọn, dùng chung cho bảng Chi tiết và các chế độ biểu tượng.
    private var selectionIndexes: IndexSet {
        viewMode == .details ? table.selectedRowIndexes : collection.selectedIndexes
    }

    private func selectIndexes(_ set: IndexSet, scroll: Bool = false) {
        if viewMode == .details {
            table.selectRowIndexes(set, byExtendingSelection: false)
            if scroll, let r = set.first { table.scrollRowToVisible(r) }
        } else {
            collection.select(set, scroll: scroll)
        }
        updateStatus()
    }

    private var clickedIndex: Int { viewMode == .details ? table.clickedRow : collection.clickedIndex }

    // MARK: Lưới biểu tượng

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: FileCellItem.id, for: indexPath)
        if let c = cell as? FileCellItem, items.indices.contains(indexPath.item) {
            let it = items[indexPath.item]
            c.configure(it, mode: viewMode)
            c.dimmed = Self.cutPaths.contains(it.path)
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items.indices.contains(indexPath.item) ? URL(fileURLWithPath: items[indexPath.item].path) as NSURL : nil
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let i = proposedDropIndexPath.pointee.item
        if proposedDropOperation.pointee != .on || !items.indices.contains(i) || !items[i].isDirectory {
            proposedDropOperation.pointee = .before
        }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let i = indexPath.item
        let dest = (dropOperation == .on && items.indices.contains(i) && items[i].isDirectory) ? items[i].path : currentPath
        transfer(urls.map(\.path), to: dest, move: !NSEvent.modifierFlags.contains(.option))
        return true
    }

    private func selectionChanged() {
        updateStatus()
        sidePane.update(selection: selectedItems, folder: currentPath)
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().reloadData() }
    }

    private func buildStatusBar() -> NSView {
        let bar = ColorView(.white)
        langButton.target = self
        langButton.action = #selector(toggleLanguage(_:))
        langButton.font = Theme.font(11, weight: .semibold)
        detailsToggle = FlatButton(title: "", symbol: "list.bullet", target: self, action: #selector(viewDetails(_:)))
        iconsToggle = FlatButton(title: "", symbol: "square.grid.2x2", target: self, action: #selector(viewLargeIcons(_:)))
        let stack = NSStackView(views: [status, message, NSView(), detailsToggle, iconsToggle, langButton])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.pin(stack, insets: .init(top: 0, left: 12, bottom: 0, right: 8))
        for b in [langButton, detailsToggle!, iconsToggle!] { b.fixedHeight.constant = 22 }
        return bar
    }

    // MARK: Ngôn ngữ

    @objc private func languageChanged() {
        reloadTexts()
        reloadContent()
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
        detailsToggle.toolTip = L10n.t("view_details") + " (Ctrl+Shift+6)"
        iconsToggle.toolTip = L10n.t("view_largeIcons") + " (Ctrl+Shift+2)"
        langButton.title = L10n.current == .vi ? "VI" : "EN"
        langButton.toolTip = L10n.t("language")
    }

    @objc func toggleLanguage(_ sender: Any?) { L10n.current = L10n.current.toggled }

    // MARK: Điều hướng

    func navigate(to path: String) {
        if SpecialLocation.isSpecial(path) {
            history.visit(path)
            load()
            return
        }
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
        let special = isSpecialPage
        specialPage.scroll.isHidden = !special
        if special {
            tableScroll.isHidden = true
            collectionScroll.isHidden = true
            allItems = []
            items = []
            reloadContent()
            specialPage.show(currentPath)
            updateLocationUI()
            sidebar.select(path: currentPath)
            updateStatus()
            sidePane.update(selection: selectedItems, folder: NSHomeDirectory())
            return
        }
        tableScroll.isHidden = viewMode != .details
        collectionScroll.isHidden = viewMode == .details
        let mode = viewPrefs.mode(for: currentPath)
        if mode != viewMode { setViewMode(mode, remember: false) }
        do {
            allItems = try DirectoryReader.list(currentPath, showHidden: showHidden)
        } catch {
            allItems = []
            showMessage(error.localizedDescription)
        }
        applySortAndFilter()
        if !selecting.isEmpty {
            selectIndexes(IndexSet(items.indices.filter { selecting.contains(items[$0].path) }), scroll: true)
        }
        updateLocationUI()
        sidebar.select(path: currentPath)
        updateStatus()
        sidePane.update(selection: selectedItems, folder: currentPath)
    }

    private func applySortAndFilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        var list = allItems
        if !q.isEmpty {
            list = list.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        items = FileSorting.sort(list, by: sortKey, ascending: ascending)
        reloadContent()
    }

    private func updateLocationUI() {
        let crumbs = Breadcrumb.crumbs(for: currentPath)
        address.realPath = SpecialLocation.title(currentPath) ?? currentPath
        address.displayText = crumbs.map(\.title).joined(separator: "  ›  ")
        let title = crumbs.last?.title ?? currentPath
        search.placeholderString = L10n.f("searchIn", title)
        backB.isEnabled = history.canGoBack
        fwdB.isEnabled = history.canGoForward
        upB.isEnabled = NavigationHistory.parent(of: currentPath) != nil
        self.title = title
        onLocationChange?(title, currentPath)
    }

    func reloadTitle() { updateLocationUI() }

    private func updateStatus() {
        if isSpecialPage {
            let n = specialPage.selectedPaths.count
            status.stringValue = n > 0 ? L10n.f("selected", n) : ""
            return
        }
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
    @objc func goHome(_ sender: Any?) { navigate(to: SpecialLocation.home) }
    @objc func goThisMac(_ sender: Any?) { navigate(to: SpecialLocation.thisMac) }

    // MARK: Thanh địa chỉ (Mục 5.13)

    @objc func focusAddress(_ sender: Any?) { view.window?.makeFirstResponder(address) }
    @objc func editAddress(_ sender: Any?) { focusAddress(sender) }

    @objc func addressEntered(_ sender: Any?) {
        let text = address.stringValue
        view.window?.makeFirstResponder(table)
        if let sp = SpecialLocation.fromTyped(text) { navigate(to: sp); return }
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
        NSPasteboard.general.setString(address.realPath, forType: .string)
    }

    @objc func pasteAndGo(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        address.stringValue = s
        addressEntered(nil)
    }

    @objc func focusSearch(_ sender: Any?) { view.window?.makeFirstResponder(search) }

    // MARK: Bảng Chi tiết

    var selectedItems: [FileItem] {
        if isSpecialPage { return specialPage.selectedPaths.compactMap { DirectoryReader.item(at: $0) } }
        return selectionIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    private var targetItems: [FileItem] {
        let clicked = isSpecialPage ? -1 : clickedIndex
        if clicked >= 0 && items.indices.contains(clicked) && !selectionIndexes.contains(clicked) { return [items[clicked]] }
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
        selectIndexes(IndexSet(items.indices.filter { sel.contains(items[$0].path) }))
    }

    func tableViewSelectionDidChange(_ notification: Notification) { selectionChanged() }

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
        let row = clickedIndex
        // Windows chọn luôn mục vừa nhấp chuột phải nếu nó chưa nằm trong vùng chọn.
        if row >= 0 && !selectionIndexes.contains(row) {
            selectIndexes([row])
        }
        @discardableResult
        func add(_ key: String, _ sel: Selector?, _ shortcut: String = "", to m: NSMenu? = nil, title: String? = nil) -> NSMenuItem {
            let it = NSMenuItem(title: (title ?? L10n.t(key)) + (shortcut.isEmpty ? "" : "\t" + shortcut), action: sel, keyEquivalent: "")
            it.target = self
            (m ?? menu).addItem(it)
            return it
        }
        func sub(_ key: String, _ items: (NSMenu) -> Void) {
            let m = NSMenu()
            items(m)
            let it = NSMenuItem(title: L10n.t(key), action: nil, keyEquivalent: "")
            it.submenu = m
            menu.addItem(it)
        }

        if row < 0 {
            // Vùng trống (Mục 5.3): Xem, Sắp xếp theo, Làm mới, Dán, Mới, Thuộc tính, Mở trong Terminal
            sub("view") { m in
                let d = add("details", nil, to: m)
                d.state = .on
                add("hiddenItems", #selector(toggleHidden(_:)), to: m).state = showHidden ? .on : .off
            }
            sub("sortBy") { m in
                for (k, key) in [(SortKey.name, "colName"), (.modified, "colModified"), (.type, "colType"), (.size, "colSize")] {
                    let it = add(key, #selector(sortBy(_:)), to: m)
                    it.representedObject = k.rawValue
                    it.state = sortKey == k ? .on : .off
                }
            }
            add("refresh", #selector(refresh(_:)), "F5")
            menu.addItem(.separator())
            add("paste", #selector(paste(_:)), "Cmd+V")
            sub("new") { m in
                add("newFolder", #selector(newFolder(_:)), "Cmd+Shift+N", to: m)
                add("newTextFile", #selector(newTextFile(_:)), to: m)
            }
            menu.addItem(.separator())
            add("openInTerminal", #selector(openInTerminal(_:)))
            add("copyAddress", #selector(copyAddress(_:)))
            add("properties", #selector(showInfo(_:)), "Option+Enter")
            return
        }

        let target = selectedItems
        let single = target.count == 1 ? target[0] : nil

        // Hàng biểu tượng trên cùng giống Windows 11: Cắt, Sao chép, Đổi tên, Chia sẻ, Xóa
        let iconRow = NSMenuItem()
        iconRow.view = ContextIconRow(owner: self, menu: menu, buttons: [
            ("scissors", L10n.t("cut") + " (Cmd+X)", #selector(cut(_:))),
            ("doc.on.doc", L10n.t("copy") + " (Cmd+C)", #selector(copy(_:))),
            ("character.cursor.ibeam", L10n.t("rename") + " (F2)", #selector(renameSelected(_:))),
            ("square.and.arrow.up", L10n.t("share"), #selector(shareSelected(_:))),
            ("trash", L10n.t("delete") + " (⌫)", #selector(trashSelected(_:))),
        ])
        menu.addItem(iconRow)
        menu.addItem(.separator())

        let open = add("open", #selector(openSelected(_:)), "Enter")
        open.attributedTitle = NSAttributedString(string: open.title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])

        if let f = single, !f.isDirectory {
            sub("openWith") { m in
                let url = URL(fileURLWithPath: f.path)
                let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
                var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
                if let d = defaultApp { apps.removeAll { $0 == d }; apps.insert(d, at: 0) }
                for app in apps.prefix(12) {
                    let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                    let it = add("", #selector(openWithApp(_:)), to: m, title: name + (app == defaultApp ? " (" + L10n.t("defaultApp") + ")" : ""))
                    it.representedObject = app
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    it.image = icon
                }
                m.addItem(.separator())
                add("chooseOtherApp", #selector(openWithOtherApp(_:)), to: m)
            }
        }
        if let f = single, f.isDirectory {
            add("openNewTab", #selector(openInNewTab(_:)))
            add("openNewWindow", #selector(openInNewWindow(_:)))
        }
        // Chia sẻ với ›: AirDrop, Mail, Tin nhắn… của macOS
        sub("shareWith") { m in
            let urls = target.map { URL(fileURLWithPath: $0.path) }
            for svc in NSSharingService.sharingServices(forItems: urls) {
                let it = add("", #selector(shareVia(_:)), to: m, title: svc.title)
                it.image = svc.image
                it.representedObject = svc
            }
        }
        // Thêm vào Ưa thích / Ghim vào Truy nhập nhanh (tệp và thư mục đều ghim được)
        if let f = single, Pins.all.contains(f.path) {
            add("unpinQuick", #selector(unpinSelected(_:)))
        } else {
            add(single?.isDirectory == true ? "pinQuick" : "addFavorites", #selector(pinSelected(_:)), "Cmd+Shift+P")
        }
        // Nén thành ›
        sub("compressTo") { m in
            for (fmt, key) in [("zip", "fmtZip"), ("7z", "fmt7z"), ("tar", "fmtTar"), ("tar.gz", "fmtTarGz")] {
                let it = add(key, #selector(compressAs(_:)), to: m)
                it.representedObject = fmt
            }
        }
        add("copyPath", #selector(copyPath(_:)), "Cmd+Shift+C")
        add("properties", #selector(showInfo(_:)), "Option+Enter")
        menu.addItem(.separator())

        // Nhóm lệnh theo loại tệp (như "Edit in Notepad", WinRAR trên Windows)
        if let f = single, !f.isDirectory, ["txt", "md", "csv", "log", "json", "xml", "ini", "html", "css", "js", "swift", "py"].contains(f.fileExtension.lowercased()) {
            add("editInTextEdit", #selector(editInTextEdit(_:)))
        }
        if let f = single, !f.isDirectory, ArchiveSupport.isArchive(f.name) {
            add("extractAll", #selector(extractAll(_:)))
            add("extractHere", #selector(extractHere(_:)))
            add("", #selector(extractToFolder(_:)), title: L10n.f("extractTo", ArchiveSupport.baseName(of: f.name)))
            add("testArchive", #selector(testArchive(_:)))
        }
        if let f = single, f.isDirectory {
            add("openInTerminal", #selector(openInTerminal(_:)))
        }
        if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }

        // Hiện thêm tùy chọn: menu đầy đủ kiểu cũ của Windows (thứ tự như Windows 11 › Show more options).
        sub("showMoreOptions") { m in
            add("open", #selector(openSelected(_:)), "Enter", to: m)
            if let f = single, f.isDirectory {
                add("openNewTab", #selector(openInNewTab(_:)), to: m)
                add("openNewWindow", #selector(openInNewWindow(_:)), to: m)
            }
            if let f = single, !f.isDirectory {
                add("editInTextEdit", #selector(editInTextEdit(_:)), to: m)
            }
            if let f = single, !f.isDirectory, ArchiveSupport.isArchive(f.name) {
                add("extractAll", #selector(extractAll(_:)), to: m)
                add("extractHere", #selector(extractHere(_:)), to: m)
            }
            if let f = single, Pins.all.contains(f.path) {
                add("unpinQuick", #selector(unpinSelected(_:)), to: m)
            } else {
                add(single?.isDirectory == true ? "pinQuick" : "addFavorites", #selector(pinSelected(_:)), "Cmd+Shift+P", to: m)
            }
            if let f = single, f.isDirectory {
                add("openInTerminal", #selector(openInTerminal(_:)), to: m)
            }
            m.addItem(.separator())
            add("copyPath", #selector(copyPath(_:)), "Cmd+Shift+C", to: m)
            add("share", #selector(shareSelected(_:)), to: m)
            add("showInFinder", #selector(showInFinder(_:)), to: m)
            m.addItem(.separator())
            let send = NSMenu()
            add("sendToDesktop", #selector(sendToDesktop(_:)), to: send)
            let zipIt = add("fmtZipFolder", #selector(compressAs(_:)), to: send)
            zipIt.representedObject = "zip"
            add("sendToDocuments", #selector(sendToFolder(_:)), to: send).representedObject = NSHomeDirectory() + "/Documents"
            for (t, p) in SidebarController.volumes() {
                let it = add("", #selector(sendToFolder(_:)), to: send, title: t)
                it.representedObject = p
            }
            let sendItem = NSMenuItem(title: L10n.t("sendTo"), action: nil, keyEquivalent: "")
            sendItem.submenu = send
            m.addItem(sendItem)
            m.addItem(.separator())
            add("cut", #selector(cut(_:)), "Cmd+X", to: m)
            add("copy", #selector(copy(_:)), "Cmd+C", to: m)
            m.addItem(.separator())
            add("createShortcut", #selector(createShortcut(_:)), to: m)
            add("duplicate", #selector(duplicateSelected(_:)), "Cmd+D", to: m)
            add("delete", #selector(trashSelected(_:)), "⌫", to: m)
            add("deleteForever", #selector(deleteForever(_:)), "Shift+⌫", to: m)
            add("rename", #selector(renameSelected(_:)), "F2", to: m)
            m.addItem(.separator())
            add("properties", #selector(showInfo(_:)), "Option+Enter", to: m)
        }
    }

    // MARK: Lệnh tệp và thư mục

    /// Mở một đường dẫn: thư mục thì vào trong, tệp thì mở bằng ứng dụng mặc định.
    func openPath(_ p: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir) else { showError(L10n.f("pathNotFound", p)); return }
        if isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: p) { navigate(to: p) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
    }

    @objc func openSelected(_ sender: Any?) {
        let sel = targetItems
        if sel.count == 1, sel[0].isDirectory { navigate(to: sel[0].path); return }
        for it in sel {
            if it.isDirectory { (NSApp.delegate as? AppDelegate)?.openWindow(at: it.path) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: it.path)) }
        }
    }

    @objc func openInNewTab(_ sender: Any?) {
        guard let wc = view.window?.windowController as? MainWindowController else { return }
        let dirs = targetItems.filter(\.isDirectory)
        for (n, it) in dirs.enumerated() { wc.addTab(path: it.path, activate: n == dirs.count - 1) }
    }

    @objc func openInNewWindow(_ sender: Any?) {
        for it in targetItems where it.isDirectory { (NSApp.delegate as? AppDelegate)?.openWindow(at: it.path) }
    }

    @objc func pinSelected(_ sender: Any?) {
        let sel = targetItems
        // Windows: thư mục ghim vào Truy nhập nhanh, tệp thêm vào Ưa thích (hiện ở Trang chủ).
        if sel.isEmpty { if !isSpecialPage { Pins.pin(currentPath) } }
        else { sel.forEach { $0.isDirectory ? Pins.pin($0.path) : Favorites.add($0.path) } }
    }

    @objc func openPin(_ sender: NSMenuItem) {
        let pins = Pins.all
        guard pins.indices.contains(sender.tag) else { return }
        navigate(to: pins[sender.tag])
    }

    @objc func copyPath(_ sender: Any?) {
        let paths = targetItems.isEmpty ? (isSpecialPage ? [] : [currentPath]) : targetItems.map(\.path)
        guard !paths.isEmpty else { return }
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
        guard !SpecialLocation.isSpecial(dest) else { NSSound.beep(); return }
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
        guard !isSpecialPage else { NSSound.beep(); return }
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

    // MARK: Lệnh của menu chuột phải

    @objc func unpinSelected(_ sender: Any?) {
        selectedItems.forEach { Pins.unpin($0.path) }
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        let urls = selectedItems.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openWithOtherApp(_ sender: Any?) {
        let urls = selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = L10n.t("open")
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let app = panel.url else { return }
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Mở Terminal tại thư mục (giống "Mở trong Terminal" của Windows 11).
    @objc func openInTerminal(_ sender: Any?) {
        let dir = selectedItems.first(where: \.isDirectory)?.path ?? currentPath
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: dir)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func shareVia(_ sender: NSMenuItem) {
        guard let svc = sender.representedObject as? NSSharingService else { return }
        svc.perform(withItems: selectedItems.map { URL(fileURLWithPath: $0.path) })
    }

    @objc func editInTextEdit(_ sender: Any?) {
        let app = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open(selectedItems.map { URL(fileURLWithPath: $0.path) }, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func showInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map { URL(fileURLWithPath: $0.path) })
    }

    /// Tạo lối tắt (alias của macOS) cạnh mục gốc: "Tên - Lối tắt".
    @objc func createShortcut(_ sender: Any?) {
        var made: [String] = []
        for it in selectedItems {
            let dir = (it.path as NSString).deletingLastPathComponent
            if let p = makeAlias(of: it, in: dir) { made.append(p) }
        }
        load(selecting: made)
    }

    @discardableResult
    private func makeAlias(of item: FileItem, in dir: String) -> String? {
        let dest = uniquePath(in: dir, name: item.name + L10n.t("shortcutSuffix"))
        do {
            let data = try URL(fileURLWithPath: item.path).bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(data, to: URL(fileURLWithPath: dest))
            return dest
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    /// Gửi tới › Màn hình nền (tạo lối tắt), giống Windows.
    @objc func sendToDesktop(_ sender: Any?) {
        let desktop = NSHomeDirectory() + "/Desktop"
        for it in selectedItems { makeAlias(of: it, in: desktop) }
        showMessage(L10n.t("sentToDesktop"))
    }

    /// Gửi tới › ổ đĩa: sao chép vào gốc ổ.
    @objc func sendToFolder(_ sender: NSMenuItem) {
        guard let dest = sender.representedObject as? String else { return }
        transfer(selectedItems.map(\.path), to: dest, move: false)
    }

    @objc func duplicateSelected(_ sender: Any?) {
        let sel = selectedItems
        guard !sel.isEmpty else { NSSound.beep(); return }
        transfer(sel.map(\.path), to: currentPath, move: false)
    }

    @objc func newTextFile(_ sender: Any?) {
        guard !isSpecialPage else { NSSound.beep(); return }
        let path = uniquePath(in: currentPath, name: L10n.t("newTextName"))
        if FileManager.default.createFile(atPath: path, contents: Data()) {
            load(selecting: [path])
            renameSelected(nil)
        }
    }

    // MARK: Nén và giải nén (dùng bsdtar/zip có sẵn trong macOS)

    /// Chạy công cụ dòng lệnh ở nền, xong thì gọi lại trên luồng chính.
    private func runTool(_ path: String, _ args: [String], cwd: String? = nil, done: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            var ok = false
            var message = ""
            do {
                try p.run()
                p.waitUntilExit()
                ok = p.terminationStatus == 0
                message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            } catch { message = error.localizedDescription }
            DispatchQueue.main.async { done(ok, message.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    private var archiveTarget: FileItem? {
        let t = targetItems
        guard t.count == 1, !t[0].isDirectory, ArchiveSupport.isArchive(t[0].name) else { NSSound.beep(); return nil }
        return t[0]
    }

    /// Giải nén vào thư mục đích; không ghi đè tệp đã có (-k).
    private func extract(_ item: FileItem, into dest: String, createFolder: Bool) {
        if createFolder {
            do { try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true) }
            catch { showError(error.localizedDescription); return }
        }
        showMessage(L10n.f("extracting", item.name))
        runTool("/usr/bin/tar", ["-xkf", item.path, "-C", dest]) { [weak self] ok, msg in
            guard let self else { return }
            if ok {
                self.showMessage(L10n.f("extracted", (dest as NSString).lastPathComponent))
                if dest == self.currentPath { self.refresh(nil) } else if (dest as NSString).deletingLastPathComponent == self.currentPath { self.load(selecting: [dest]) }
            } else {
                self.showError(L10n.f("archiveBad", item.name) + (msg.isEmpty ? "" : "\n\n" + msg))
                self.refresh(nil)
            }
        }
    }

    /// Giải nén tất cả…: chọn đích, mặc định là thư mục cùng tên tệp nén ở cạnh nó (giống Windows).
    @objc func extractAll(_ sender: Any?) {
        guard let item = archiveTarget, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: currentPath)
        panel.message = L10n.t("chooseDestination")
        panel.prompt = L10n.t("extract")
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            let dest = self.uniquePath(in: url.path, name: ArchiveSupport.baseName(of: item.name))
            self.extract(item, into: dest, createFolder: true)
        }
    }

    @objc func extractHere(_ sender: Any?) {
        guard let item = archiveTarget else { return }
        extract(item, into: (item.path as NSString).deletingLastPathComponent, createFolder: false)
    }

    @objc func extractToFolder(_ sender: Any?) {
        guard let item = archiveTarget else { return }
        let parent = (item.path as NSString).deletingLastPathComponent
        extract(item, into: uniquePath(in: parent, name: ArchiveSupport.baseName(of: item.name)), createFolder: true)
    }

    @objc func testArchive(_ sender: Any?) {
        guard let item = archiveTarget else { return }
        let isZip = item.name.lowercased().hasSuffix(".zip")
        let tool = isZip ? "/usr/bin/unzip" : "/usr/bin/tar"
        let args = isZip ? ["-tq", item.path] : ["-tf", item.path]
        runTool(tool, args) { [weak self] ok, msg in
            guard let self else { return }
            if ok {
                let a = NSAlert()
                a.messageText = L10n.f("archiveOK", item.name)
                a.addButton(withTitle: L10n.t("ok"))
                if let w = self.view.window { a.beginSheetModal(for: w) } else { a.runModal() }
            } else {
                self.showError(L10n.f("archiveBad", item.name) + (msg.isEmpty ? "" : "\n\n" + msg))
            }
        }
    }

    /// Nén thành tệp ZIP / 7z / TAR / TAR.GZ: tên tệp theo mục đầu tiên, đặt cạnh các mục đã chọn (giống Windows).
    @objc func compressAs(_ sender: NSMenuItem) {
        compress(format: sender.representedObject as? String ?? "zip")
    }

    @objc func compressToZip(_ sender: Any?) { compress(format: "zip") }

    private func compress(format: String) {
        let sel = targetItems
        guard let first = sel.first else { NSSound.beep(); return }
        let dir = (first.path as NSString).deletingLastPathComponent
        let base = first.isDirectory ? first.name : (first.name as NSString).deletingPathExtension
        let dest = uniquePath(in: dir, name: base + "." + format)
        let names = sel.map(\.name)
        let tool: String
        let args: [String]
        switch format {
        case "7z": tool = "/usr/bin/tar"; args = ["--format", "7zip", "-cf", dest] + names
        case "tar": tool = "/usr/bin/tar"; args = ["-cf", dest] + names
        case "tar.gz": tool = "/usr/bin/tar"; args = ["-czf", dest] + names
        default: tool = "/usr/bin/zip"; args = ["-r", "-y", "-q", dest] + names
        }
        showMessage(L10n.f("compressing", sel.count))
        runTool(tool, args, cwd: dir) { [weak self] ok, msg in
            guard let self else { return }
            if ok {
                self.showMessage(L10n.f("compressed", (dest as NSString).lastPathComponent))
                self.load(selecting: [dest])
            } else {
                try? FileManager.default.removeItem(atPath: dest)
                self.showError(msg)
            }
        }
    }

    @objc func showInfo(_ sender: Any?) {
        let sel = targetItems.map(\.path)
        let paths = sel.isEmpty ? (isSpecialPage ? [] : [currentPath]) : sel
        PropertiesWindowController.show(paths: paths) { [weak self] in self?.refresh(nil) }
    }

    @objc func selectAllItems(_ sender: Any?) { selectIndexes(IndexSet(items.indices)) }

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
        for (i, mode) in ViewMode.allCases.enumerated() {
            let it = NSMenuItem(title: L10n.t(mode.titleKey) + "\tCtrl+Shift+\(i + 1)", action: #selector(setViewModeFromMenu(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = viewMode == mode ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let c = NSMenuItem(title: L10n.t("compactView"), action: #selector(toggleCompact(_:)), keyEquivalent: "")
        c.target = self
        c.state = compact ? .on : .off
        m.addItem(c)
        let paneItem = NSMenuItem(title: L10n.t("pane"), action: nil, keyEquivalent: "")
        let pm = NSMenu()
        for (key, sel, k, sc) in [("detailsPane", #selector(toggleDetailsPane(_:)), SidePaneKind.details, "Option+Shift+P"),
                                  ("previewPane", #selector(togglePreviewPane(_:)), SidePaneKind.preview, "Option+P")] {
            let it = NSMenuItem(title: L10n.t(key) + "\t" + sc, action: sel, keyEquivalent: "")
            it.target = self
            it.state = sidePane.kind == k ? .on : .off
            pm.addItem(it)
        }
        paneItem.submenu = pm
        m.addItem(paneItem)
        let showItem = NSMenuItem(title: L10n.t("show"), action: nil, keyEquivalent: "")
        let sm = NSMenu()
        let hidden = NSMenuItem(title: L10n.t("hiddenItems"), action: #selector(toggleHidden(_:)), keyEquivalent: "")
        hidden.target = self
        hidden.state = showHidden ? .on : .off
        sm.addItem(hidden)
        showItem.submenu = sm
        m.addItem(showItem)
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
