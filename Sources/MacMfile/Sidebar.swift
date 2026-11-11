import AppKit
import MfileCore

/// Ngăn điều hướng bên trái: Trang chủ, ổ đám mây, Truy nhập nhanh (mục ghim), Máy Mac này, ổ ngoài, Thùng rác.
final class SidebarController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    struct Entry {
        var title: String
        var path: String?
        var symbol: String
        var tint: NSColor = Theme.text
        var isPin = false
        var shortcut = ""
        var separator: Bool { path == nil }
        static let sep = Entry(title: "", path: nil, symbol: "")
    }

    let table = NSTableView()
    let scroll = NSScrollView()
    var entries: [Entry] = []
    var onSelect: ((String) -> Void)?
    var onOpenNewWindow: ((String) -> Void)?
    var onOpenNewTab: ((String) -> Void)?
    private var suppressSelect = false
    private let dragType = NSPasteboard.PasteboardType("vn.macmfile.pin-row")

    override init() {
        super.init()
        let col = NSTableColumn(identifier: .init("nav"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.style = .sourceList
        table.backgroundColor = Theme.background
        table.dataSource = self
        table.delegate = self
        table.focusRingType = .none
        table.registerForDraggedTypes([dragType, .fileURL])
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        scroll.translatesAutoresizingMaskIntoConstraints = false
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: L10n.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Pins.didChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reload), name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reload), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    /// Thư mục của ứng dụng đồng bộ đám mây (OneDrive, Google Drive, Dropbox tạo trong ~/Library/CloudStorage; iCloud Drive riêng).
    static func cloudFolders() -> [(String, String)] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var out: [(String, String)] = []
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if fm.fileExists(atPath: icloud) { out.append(("iCloud Drive", icloud)) }
        let cs = home + "/Library/CloudStorage"
        if let names = try? fm.contentsOfDirectory(atPath: cs) {
            for n in names.sorted() where !n.hasPrefix(".") {
                // "OneDrive-Personal" → "OneDrive - Personal", "GoogleDrive-ten@gmail.com" → "Google Drive"
                var title = n
                if n.hasPrefix("OneDrive") { title = n.replacingOccurrences(of: "OneDrive-", with: "OneDrive - ") }
                else if n.hasPrefix("GoogleDrive") { title = "Google Drive" }
                else if n.hasPrefix("Dropbox") { title = "Dropbox" }
                out.append((title, cs + "/" + n))
            }
        }
        return out
    }

    static func volumes() -> [(String, String)] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard u.path != "/" else { return nil }
            let v = try? u.resourceValues(forKeys: Set(keys))
            return (v?.volumeLocalizedName ?? u.lastPathComponent, u.path)
        }
    }

    @objc func reload() {
        let home = NSHomeDirectory()
        let blue = NSColor(srgbRed: 0x0f / 255, green: 0x6c / 255, blue: 0xbd / 255, alpha: 1)
        let folderTint = NSColor(srgbRed: 0xe8 / 255, green: 0xb0 / 255, blue: 0x2a / 255, alpha: 1)
        var e: [Entry] = [
            Entry(title: L10n.t("home"), path: SpecialLocation.home, symbol: "house"),
        ]
        for (t, p) in Self.cloudFolders() { e.append(Entry(title: t, path: p, symbol: "cloud.fill", tint: blue)) }
        e.append(.sep)
        let known: [String: String] = ["Desktop": "desktop", "Downloads": "downloads", "Documents": "documents", "Pictures": "pictures", "Music": "music", "Movies": "videos"]
        for (i, p) in Pins.all.enumerated() {
            let name = (p as NSString).lastPathComponent
            let isKnown = (p as NSString).deletingLastPathComponent == home && known[name] != nil
            let title = isKnown ? L10n.t(known[name]!) : name
            e.append(Entry(title: title, path: p, symbol: "folder.fill", tint: folderTint, isPin: true, shortcut: i < 9 ? "⌘\(i + 1)" : ""))
        }
        e.append(.sep)
        e.append(Entry(title: L10n.t("thisMac"), path: SpecialLocation.thisMac, symbol: "desktopcomputer", tint: blue))
        for (t, p) in Self.volumes() { e.append(Entry(title: t, path: p, symbol: "externaldrive", tint: Theme.secondaryText)) }
        e.append(Entry(title: L10n.t("trash"), path: home + "/.Trash", symbol: "trash", tint: Theme.secondaryText))
        entries = e
        suppressSelect = true
        table.reloadData()
        suppressSelect = false
    }

    func select(path: String) {
        suppressSelect = true
        if let i = entries.firstIndex(where: { $0.path == path }) {
            table.selectRowIndexes([i], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        suppressSelect = false
    }

    // MARK: Bảng

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { entries[row].separator ? 9 : 28 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !entries[row].separator }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row]
        if e.separator {
            let v = ColorView(Theme.background)
            let line = ColorView(Theme.border)
            v.addSubview(line)
            NSLayoutConstraint.activate([
                line.heightAnchor.constraint(equalToConstant: 1),
                line.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                line.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
                line.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            ])
            return v
        }
        let cell = NSTableCellView()
        let icon = NSImageView(image: Theme.symbol(e.symbol, size: 13) ?? NSImage())
        icon.contentTintColor = e.tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        let t = label(e.title)
        let k = label(e.shortcut, size: 11, color: Theme.secondaryText)
        k.setContentHuggingPriority(.required, for: .horizontal)
        cell.addSubview(icon); cell.addSubview(t); cell.addSubview(k)
        cell.textField = t
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            t.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            t.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            k.leadingAnchor.constraint(greaterThanOrEqualTo: t.trailingAnchor, constant: 6),
            k.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            k.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.toolTip = e.path
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelect, table.selectedRow >= 0, let p = entries[table.selectedRow].path else { return }
        onSelect?(p)
    }

    // MARK: Kéo thả: đổi thứ tự mục ghim, thả thư mục vào để ghim

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard entries[row].isPin else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        let pinRows = entries.indices.filter { entries[$0].isPin }
        guard let first = pinRows.first, let last = pinRows.last, row >= first, row <= last + 1 else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return info.draggingPasteboard.types?.contains(dragType) == true ? .move : .link
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let firstPin = entries.firstIndex(where: { $0.isPin }) ?? 0
        if let s = info.draggingPasteboard.string(forType: dragType), let from = Int(s) {
            let to = row - firstPin
            Pins.move(from: from - firstPin, to: to > from - firstPin ? to - 1 : to)
            return true
        }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        var added = false
        for u in urls where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            Pins.pin(u.path); added = true
        }
        return added
    }

    // MARK: Menu chuột phải (Mục 5.3: Mục ở Ngăn điều hướng)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard row >= 0, let p = entries[row].path else { return }
        func add(_ key: String, _ sel: Selector) {
            let it = NSMenuItem(title: L10n.t(key), action: sel, keyEquivalent: "")
            it.target = self
            it.representedObject = p
            menu.addItem(it)
        }
        add("open", #selector(menuOpen(_:)))
        add("openNewTab", #selector(menuNewTab(_:)))
        add("openNewWindow", #selector(menuNewWindow(_:)))
        guard !SpecialLocation.isSpecial(p) else { return }
        menu.addItem(.separator())
        if entries[row].isPin { add("unpinQuick", #selector(menuUnpin(_:))) } else { add("pinQuick", #selector(menuPin(_:))) }
        add("copyPath", #selector(menuCopyPath(_:)))
    }

    @objc func menuOpen(_ s: NSMenuItem) { if let p = s.representedObject as? String { onSelect?(p) } }
    @objc func menuNewTab(_ s: NSMenuItem) { if let p = s.representedObject as? String { onOpenNewTab?(p) } }
    @objc func menuNewWindow(_ s: NSMenuItem) { if let p = s.representedObject as? String { onOpenNewWindow?(p) } }
    @objc func menuUnpin(_ s: NSMenuItem) { if let p = s.representedObject as? String { Pins.unpin(p) } }
    @objc func menuPin(_ s: NSMenuItem) { if let p = s.representedObject as? String { Pins.pin(p) } }
    @objc func menuCopyPath(_ s: NSMenuItem) {
        guard let p = s.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PathParser.copyText(for: [p]), forType: .string)
    }
}
