import AppKit
import UniformTypeIdentifiers
import MfileCore

/// Hộp thoại Thuộc tính kiểu Windows (Mục 5.11): tab Chung và Chi tiết, nút OK / Hủy / Áp dụng.
/// Không chặn cửa sổ chính, mở được nhiều hộp cùng lúc như Windows.
final class PropertiesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var open: [PropertiesWindowController] = []
    private let paths: [String]
    private var onChange: (() -> Void)?

    private let nameField = NSTextField()
    private let readOnly = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var sizeValue: NSTextField!, diskValue: NSTextField!, containsValue: NSTextField?
    private var sizeWork: DispatchWorkItem?
    private var detailRows: [(key: String, label: String, value: String, editable: Bool)] = []
    private let detailTable = NSTableView()
    private var edits: [String: String] = [:]

    static func show(paths: [String], onChange: @escaping () -> Void) {
        guard !paths.isEmpty else { return }
        let c = PropertiesWindowController(paths: paths)
        c.onChange = onChange
        open.append(c)
        c.window?.center()
        c.showWindow(nil)
    }

    private init(paths: [String]) {
        self.paths = paths
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isFloatingPanel = false
        w.hidesOnDeactivate = false
        super.init(window: w)
        w.delegate = self
        let title = paths.count == 1 ? FileManager.default.displayName(atPath: paths[0]) : L10n.f("filesFolders", fileCount, folderCount)
        w.title = L10n.f("propsTitle", title)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        sizeWork?.cancel()
        Self.open.removeAll { $0 === self }
    }

    private var isDir: (String) -> Bool = { p in
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue && !NSWorkspace.shared.isFilePackage(atPath: p)
    }
    private var fileCount: Int { paths.filter { !isDir($0) }.count }
    private var folderCount: Int { paths.filter { isDir($0) }.count }

    // MARK: Dựng giao diện

    private func build() {
        guard let content = window?.contentView else { return }
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let general = NSTabViewItem(identifier: "general")
        general.label = L10n.t("general")
        general.view = buildGeneral()
        tabs.addTabViewItem(general)
        if paths.count == 1 {
            let det = NSTabViewItem(identifier: "details")
            det.label = L10n.t("detailsTab")
            det.view = buildDetails()
            tabs.addTabViewItem(det)
        }
        let ok = NSButton(title: L10n.t("ok"), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: L10n.t("cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: L10n.t("apply"), target: self, action: #selector(applyPressed))
        let buttons = NSStackView(views: [ok, cancel, apply])
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            tabs.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        for b in [ok, cancel, apply] { b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true }
    }

    private func row(_ key: String, _ value: String, selectable: Bool = true) -> (NSView, NSTextField) {
        let k = label(L10n.t(key) + ":", color: Theme.text)
        k.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let v = label(value)
        v.isSelectable = selectable
        v.lineBreakMode = .byTruncatingMiddle
        v.toolTip = value
        let s = NSStackView(views: [k, v])
        s.alignment = .firstBaseline
        s.spacing = 8
        return (s, v)
    }

    private func line() -> NSView {
        let v = ColorView(Theme.border)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func buildGeneral() -> NSView {
        let fm = FileManager.default
        let v = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
        ])
        var views: [NSView] = []

        let icon = NSImageView(image: paths.count == 1 ? NSWorkspace.shared.icon(forFile: paths[0]) : (NSWorkspace.shared.icon(forFiles: paths) ?? NSImage()))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        nameField.stringValue = paths.count == 1 ? (paths[0] as NSString).lastPathComponent : L10n.f("filesFolders", fileCount, folderCount)
        nameField.isEditable = paths.count == 1
        nameField.font = Theme.font(12)
        let head = NSStackView(views: [icon, nameField])
        head.spacing = 12
        views += [head, line()]
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        if paths.count == 1 {
            let p = paths[0]
            let item = DirectoryReader.item(at: p)
            views.append(row("typeOfFile", item?.typeDescription() ?? "").0)
            if !isDir(p) {
                let app = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: p))
                let appName = app.map { fm.displayName(atPath: $0.path) } ?? "—"
                let (r, _) = row("opensWith", appName)
                let change = NSButton(title: L10n.t("change") + "…", target: self, action: #selector(changeApp))
                change.controlSize = .small
                (r as? NSStackView)?.addArrangedSubview(change)
                views.append(r)
            }
            views.append(line())
            views.append(row("location", (p as NSString).deletingLastPathComponent).0)
        } else {
            let types = Set(paths.compactMap { DirectoryReader.item(at: $0)?.typeDescription() })
            views.append(row("typeOfFile", types.count == 1 ? L10n.f("allOfType", types.first!) : L10n.t("variousTypes")).0)
            let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
            views.append(row("location", parents.count == 1 ? L10n.f("allIn", parents.first!) : L10n.t("variousFolders")).0)
        }
        let (sr, sv) = row("sizeLabel", L10n.t("calculating"))
        let (dr, dv) = row("sizeOnDisk", L10n.t("calculating"))
        sizeValue = sv; diskValue = dv
        views += [sr, dr]
        if paths.count > 1 || isDir(paths[0]) {
            let (cr, cv) = row("contains", L10n.t("calculating"))
            containsValue = cv
            views.append(cr)
        }
        views.append(line())
        if paths.count == 1 {
            let attrs = (try? fm.attributesOfItem(atPath: paths[0])) ?? [:]
            if let d = attrs[.creationDate] as? Date { views.append(row("dateCreated", Formatting.date(d)).0) }
            if let d = attrs[.modificationDate] as? Date { views.append(row("colModified", Formatting.date(d)).0) }
            if let d = (try? URL(fileURLWithPath: paths[0]).resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate {
                views.append(row("dateAccessed", Formatting.date(d)).0)
            }
            views.append(line())
        }
        readOnly.title = L10n.t("readOnly")
        hidden.title = L10n.t("hidden")
        readOnly.allowsMixedState = paths.count > 1
        hidden.allowsMixedState = paths.count > 1
        readOnly.state = mixedState(paths.map { isLocked($0) })
        hidden.state = mixedState(paths.map { isHiddenItem($0) })
        let attrRow = NSStackView(views: [label(L10n.t("attributes") + ":"), readOnly, hidden])
        attrRow.spacing = 12
        (attrRow.arrangedSubviews[0] as? NSTextField)?.widthAnchor.constraint(equalToConstant: 110).isActive = true
        views.append(attrRow)
        for x in views { stack.addArrangedSubview(x) }
        for x in stack.arrangedSubviews where x is ColorView { x.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        startSizeCalculation()
        return v
    }

    private func mixedState(_ values: [Bool]) -> NSControl.StateValue {
        if values.allSatisfy({ $0 }) { return .on }
        if values.allSatisfy({ !$0 }) { return .off }
        return .mixed
    }

    private func isLocked(_ p: String) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: p))?[.immutable] as? Bool) ?? false
    }

    private func isHiddenItem(_ p: String) -> Bool {
        (try? URL(fileURLWithPath: p).resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false
    }

    /// Tính kích thước dần dần như Windows (thư mục lớn không làm treo hộp thoại).
    private func startSizeCalculation() {
        let paths = self.paths
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            var size: Int64 = 0, disk: Int64 = 0, files = 0, folders = 0
            var last = Date()
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            func add(_ u: URL) {
                let v = try? u.resourceValues(forKeys: Set(keys))
                if v?.isDirectory == true { folders += 1 } else {
                    files += 1
                    size += Int64(v?.fileSize ?? 0)
                    disk += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                }
            }
            for p in paths {
                let u = URL(fileURLWithPath: p)
                var d: ObjCBool = false
                FileManager.default.fileExists(atPath: p, isDirectory: &d)
                if d.boolValue {
                    if paths.count > 1 { folders += 1 }
                    let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
                    while let x = e?.nextObject() as? URL {
                        if work.isCancelled { return }
                        add(x)
                        if Date().timeIntervalSince(last) > 0.25 {
                            last = Date()
                            let (s, k, f, o) = (size, disk, files, folders)
                            DispatchQueue.main.async { self?.showSizes(s, k, f, o) }
                        }
                    }
                } else { add(u) }
            }
            let (s, k, f, o) = (size, disk, files, folders)
            DispatchQueue.main.async { self?.showSizes(s, k, f, o) }
        }
        sizeWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func showSizes(_ size: Int64, _ disk: Int64, _ files: Int, _ folders: Int) {
        sizeValue.stringValue = L10n.f("bytesFmt", Formatting.size(size), Formatting.group(size))
        diskValue.stringValue = L10n.f("bytesFmt", Formatting.size(disk), Formatting.group(disk))
        containsValue?.stringValue = L10n.f("filesFolders", files, folders)
    }

    // MARK: Tab Chi tiết

    private func buildDetails() -> NSView {
        let p = paths[0]
        let u = URL(fileURLWithPath: p)
        var rows: [(String, String, String, Bool)] = []
        let tags = (try? u.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        rows.append(("tags", L10n.t("tags"), tags.joined(separator: "; "), true))
        rows.append(("comments", L10n.t("comments"), finderComment(p), true))
        if let md = NSMetadataItem(url: u) {
            let pairs: [(String, String)] = [
                ("kMDItemTitle", "propTitle"), ("kMDItemAuthors", "authors"), ("kMDItemPixelWidth", "width"),
                ("kMDItemPixelHeight", "height"), ("kMDItemDurationSeconds", "duration"), ("kMDItemAcquisitionMake", "cameraMaker"),
                ("kMDItemAcquisitionModel", "cameraModel"), ("kMDItemLatitude", "gpsLatitude"), ("kMDItemLongitude", "gpsLongitude"),
                ("kMDItemWhereFroms", "whereFrom"), ("kMDItemNumberOfPages", "pages"), ("kMDItemVersion", "version"),
            ]
            for (attr, key) in pairs {
                guard let val = md.value(forAttribute: attr) else { continue }
                let text: String
                if let a = val as? [Any] { text = a.map { "\($0)" }.joined(separator: "; ") }
                else if let d = val as? Double, attr == "kMDItemDurationSeconds" { text = String(format: "%d:%02d", Int(d) / 60, Int(d) % 60) }
                else { text = "\(val)" }
                if !text.isEmpty { rows.append((attr, L10n.t(key), text, false)) }
            }
        }
        detailRows = rows.map { (key: $0.0, label: $0.1, value: $0.2, editable: $0.3) }

        let v = NSView()
        for (id, title, w) in [("p", L10n.t("property"), CGFloat(130)), ("v", L10n.t("value"), CGFloat(210))] {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = w
            detailTable.addTableColumn(c)
        }
        detailTable.dataSource = self
        detailTable.delegate = self
        detailTable.rowHeight = 22
        detailTable.style = .plain
        let sc = NSScrollView()
        sc.documentView = detailTable
        sc.hasVerticalScroller = true
        sc.borderType = .bezelBorder
        sc.translatesAutoresizingMaskIntoConstraints = false
        let link = NSButton(title: L10n.t("removeProps"), target: self, action: #selector(removeProps))
        link.isBordered = false
        link.contentTintColor = Theme.accent
        link.attributedTitle = NSAttributedString(string: L10n.t("removeProps"), attributes: [.foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .font: Theme.font(12)])
        link.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sc)
        v.addSubview(link)
        NSLayoutConstraint.activate([
            sc.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            sc.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            sc.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            sc.bottomAnchor.constraint(equalTo: link.topAnchor, constant: -10),
            link.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            link.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -12),
        ])
        return v
    }

    func numberOfRows(in tableView: NSTableView) -> Int { detailRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = detailRows[row]
        if tableColumn?.identifier.rawValue == "p" {
            let l = label(r.label, color: Theme.secondaryText)
            l.translatesAutoresizingMaskIntoConstraints = true
            return l
        }
        let f = NSTextField(string: edits[r.key] ?? r.value)
        f.isBordered = false
        f.drawsBackground = false
        f.font = Theme.font(12)
        f.isEditable = r.editable
        f.isSelectable = true
        f.placeholderString = r.editable ? L10n.t("addValue") : nil
        f.identifier = .init(r.key)
        f.target = self
        f.action = #selector(detailEdited(_:))
        return f
    }

    @objc private func detailEdited(_ f: NSTextField) {
        if let k = f.identifier?.rawValue { edits[k] = f.stringValue }
    }

    private func finderComment(_ p: String) -> String {
        let name = "com.apple.metadata:kMDItemFinderComment"
        let len = getxattr(p, name, nil, 0, 0, 0)
        guard len > 0 else { return "" }
        var data = Data(count: len)
        _ = data.withUnsafeMutableBytes { getxattr(p, name, $0.baseAddress, len, 0, 0) }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? String ?? ""
    }

    private func setFinderComment(_ p: String, _ text: String) {
        let name = "com.apple.metadata:kMDItemFinderComment"
        if text.isEmpty { removexattr(p, name, 0); return }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: text, format: .binary, options: 0) else { return }
        _ = data.withUnsafeBytes { setxattr(p, name, $0.baseAddress, data.count, 0, 0) }
    }

    // MARK: Nút

    @objc private func okPressed() { if applyChanges() { close() } }
    @objc private func cancelPressed() { close() }
    @objc private func applyPressed() { _ = applyChanges() }

    @objc private func changeApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard let w = window else { return }
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let app = panel.url, let p = self?.paths.first else { return }
            // Như Windows "Thay đổi…": đặt ứng dụng mặc định cho cả loại tệp này.
            if let type = (try? URL(fileURLWithPath: p).resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { _ in }
            }
        }
    }

    private func applyChanges() -> Bool {
        let fm = FileManager.default
        var paths = self.paths
        for p in paths {
            if readOnly.state != .mixed {
                try? fm.setAttributes([.immutable: readOnly.state == .on], ofItemAtPath: p)
            }
            if hidden.state != .mixed {
                var u = URL(fileURLWithPath: p)
                var v = URLResourceValues()
                v.isHidden = hidden.state == .on
                try? u.setResourceValues(v)
            }
        }
        if paths.count == 1 {
            window?.makeFirstResponder(nil)
            if let t = edits["tags"] {
                let u = URL(fileURLWithPath: paths[0])
                let list = t.split(whereSeparator: { $0 == ";" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                try? (u as NSURL).setResourceValue(list, forKey: .tagNamesKey)
            }
            if let c = edits["comments"] { setFinderComment(paths[0], c) }
            let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            let old = paths[0]
            if !newName.isEmpty, newName != (old as NSString).lastPathComponent {
                if isLocked(old) { try? fm.setAttributes([.immutable: false], ofItemAtPath: old) }
                let dst = ((old as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
                do {
                    try fm.moveItem(atPath: old, toPath: dst)
                    paths = [dst]
                    window?.title = L10n.f("propsTitle", newName)
                } catch {
                    let a = NSAlert(error: error)
                    a.runModal()
                    return false
                }
            }
        }
        onChange?()
        return true
    }

    // MARK: Xóa thuộc tính và thông tin cá nhân

    @objc private func removeProps() {
        guard let w = window, let p = paths.first else { return }
        RemovePropertiesSheet.present(for: [p], on: w) { [weak self] in self?.onChange?() }
    }
}

/// Hộp "Xóa thuộc tính": tạo bản sao đã xóa, hoặc xóa ngay trên tệp này (giống Windows).
enum RemovePropertiesSheet {
    static func present(for paths: [String], on window: NSWindow, done: @escaping () -> Void) {
        let supported = paths.filter(MetadataCleaner.canClean)
        let a = NSAlert()
        a.messageText = L10n.t("removeProps")
        if supported.isEmpty {
            a.informativeText = L10n.t("cleanUnsupported")
            a.beginSheetModal(for: window) { _ in }
            return
        }
        a.informativeText = L10n.t("removePropsInfo")
        let copy = NSButton(radioButtonWithTitle: L10n.t("removeCopy"), target: nil, action: nil)
        let inPlace = NSButton(radioButtonWithTitle: L10n.t("removeFromThis"), target: RadioGroup.shared, action: #selector(RadioGroup.pick(_:)))
        copy.target = RadioGroup.shared
        copy.action = #selector(RadioGroup.pick(_:))
        copy.state = .on
        let box = NSStackView(views: [copy, inPlace])
        box.orientation = .vertical
        box.alignment = .leading
        box.frame = NSRect(x: 0, y: 0, width: 360, height: 48)
        a.accessoryView = box
        a.addButton(withTitle: L10n.t("ok"))
        a.addButton(withTitle: L10n.t("cancel"))
        a.beginSheetModal(for: window) { r in
            guard r == .alertFirstButtonReturn else { return }
            var failed: [String] = []
            for p in supported {
                do {
                    if copy.state == .on {
                        let dir = (p as NSString).deletingLastPathComponent
                        var dst = dir + "/" + MetadataCleaner.copyName(for: p)
                        var n = 2
                        while FileManager.default.fileExists(atPath: dst) {
                            let base = (MetadataCleaner.copyName(for: p) as NSString).deletingPathExtension
                            dst = dir + "/" + base + " (\(n))." + (p as NSString).pathExtension
                            n += 1
                        }
                        try MetadataCleaner.clean(p, to: dst)
                    } else {
                        try MetadataCleaner.cleanInPlace(p)
                    }
                } catch { failed.append((p as NSString).lastPathComponent) }
            }
            done()
            let b = NSAlert()
            b.messageText = failed.isEmpty ? L10n.t("cleanedDone") : L10n.f("cleanFailed", failed.joined(separator: ", "))
            b.runModal()
        }
    }
}

/// Nhóm nút radio trong cùng một hộp (AppKit tự nhóm theo cùng action và cùng superview).
final class RadioGroup: NSObject {
    static let shared = RadioGroup()
    @objc func pick(_ sender: NSButton) {}
}
