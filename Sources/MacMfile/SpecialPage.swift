import AppKit
import MfileCore

/// Trang chủ (Truy nhập nhanh, Ưa thích, Gần đây) và trang Máy Mac này (Thư mục, Thiết bị và ổ đĩa)
/// như Home và This PC của Windows 11 (FR-08, Mục 5.1). Bố cục tính bằng khung để tự xuống dòng khi đổi cỡ cửa sổ.
final class SpecialPageController: NSObject {
    let scroll = NSScrollView()
    private let doc = FlippedView()
    private(set) var path = ""
    var onOpen: ((String) -> Void)?
    var onOpenNewTab: ((String) -> Void)?
    var onOpenNewWindow: ((String) -> Void)?
    var onSelectionChange: (([String]) -> Void)?
    /// Mở thư mục chứa tệp và chọn sẵn tệp đó.
    var onReveal: ((String) -> Void)?

    private enum Block {
        case header(NSTextField)
        case tiles([TileView], NSSize)
        case rows([RecentRow])
        case empty(NSTextField)
    }
    private var blocks: [Block] = []
    private var recentQuery: NSMetadataQuery?
    private var recentPaths: [(String, Date)] = []
    private(set) var selected: Set<String> = []

    override init() {
        super.init()
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.isHidden = true
        scroll.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(relayout), name: NSView.frameDidChangeNotification, object: scroll)
        for n in [Pins.didChange, Favorites.didChange, L10n.didChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: n, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(rebuild), name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(rebuild), name: NSWorkspace.didUnmountNotification, object: nil)
        doc.onClickEmpty = { [weak self] in self?.select(nil, extend: false) }
    }

    func show(_ path: String) {
        self.path = path
        selected = []
        if path == SpecialLocation.home { startRecentQuery() }
        rebuild()
    }

    var selectedPaths: [String] { Array(selected) }

    // MARK: Nội dung

    @objc func rebuild() {
        guard !path.isEmpty else { return }
        doc.subviews.forEach { $0.removeFromSuperview() }
        blocks = []
        if path == SpecialLocation.home { buildHome() } else { buildThisMac() }
        relayout()
    }

    private func header(_ key: String, count: Int? = nil) {
        let t = label(L10n.t(key) + (count.map { " (\($0))" } ?? ""), size: 14)
        t.font = Theme.font(14, weight: .semibold)
        t.translatesAutoresizingMaskIntoConstraints = true
        doc.addSubview(t)
        blocks.append(.header(t))
    }

    private func empty(_ key: String) {
        let t = label(L10n.t(key), color: Theme.secondaryText)
        t.translatesAutoresizingMaskIntoConstraints = true
        doc.addSubview(t)
        blocks.append(.empty(t))
    }

    private func tiles(_ list: [TileView], size: NSSize) {
        for t in list {
            t.owner = self
            doc.addSubview(t)
        }
        blocks.append(.tiles(list, size))
    }

    private func knownTitle(_ p: String) -> String {
        let home = NSHomeDirectory()
        let known = ["Desktop": "desktop", "Downloads": "downloads", "Documents": "documents", "Pictures": "pictures", "Music": "music", "Movies": "videos"]
        let name = (p as NSString).lastPathComponent
        if (p as NSString).deletingLastPathComponent == home, let k = known[name] { return L10n.t(k) }
        return FileManager.default.displayName(atPath: p)
    }

    private func buildHome() {
        let pins = Pins.all.filter { FileManager.default.fileExists(atPath: $0) }
        header("quickAccess")
        tiles(pins.map { p in
            let t = TileView(path: p, title: knownTitle(p), subtitle: L10n.t("pinnedHint"))
            t.isPinned = true
            return t
        }, size: NSSize(width: 236, height: 60))

        let favs = Favorites.all.filter { FileManager.default.fileExists(atPath: $0) }
        header("favorites")
        if favs.isEmpty { empty("noFavorites") }
        else { blocks.append(.rows(favs.map { makeRow($0, date: nil) })) }

        header("recent")
        if recentPaths.isEmpty { empty("noRecent") }
        else { blocks.append(.rows(recentPaths.prefix(25).map { makeRow($0.0, date: $0.1) })) }
    }

    private func makeRow(_ p: String, date: Date?) -> RecentRow {
        let r = RecentRow(path: p, date: date)
        r.owner = self
        doc.addSubview(r)
        return r
    }

    private func buildThisMac() {
        let home = NSHomeDirectory()
        let folders = ([home] + ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Movies"].map { home + "/" + $0 })
            .filter { FileManager.default.fileExists(atPath: $0) }
        header("folders", count: folders.count)
        tiles(folders.map { TileView(path: $0, title: knownTitle($0), subtitle: L10n.t("thisMac")) }, size: NSSize(width: 236, height: 60))

        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var drives: [TileView] = []
        for u in vols {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let total = Int64(v?.volumeTotalCapacity ?? 0)
            let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
            guard total > 0 else { continue }
            let t = TileView(path: u.path, title: v?.volumeLocalizedName ?? u.lastPathComponent,
                             subtitle: L10n.f("freeOf", Formatting.size(free), Formatting.size(total)))
            t.usage = Double(total - free) / Double(total)
            drives.append(t)
        }
        header("devicesDrives", count: drives.count)
        tiles(drives, size: NSSize(width: 300, height: 72))
    }

    // MARK: Gần đây (Spotlight, không cần quyền riêng)

    private func startRecentQuery() {
        guard recentQuery == nil else { return }
        let q = NSMetadataQuery()
        let since = Date().addingTimeInterval(-30 * 86400) as NSDate
        q.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@ AND kMDItemContentType != 'public.folder'", since)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(recentUpdated), name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(recentUpdated), name: .NSMetadataQueryDidUpdate, object: q)
        recentQuery = q
        q.start()
    }

    @objc private func recentUpdated() {
        guard let q = recentQuery else { return }
        q.disableUpdates()
        var out: [(String, Date)] = []
        for i in 0..<min(q.resultCount, 60) {
            guard let it = q.result(at: i) as? NSMetadataItem,
                  let p = it.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !p.contains("/Library/"), !(p as NSString).lastPathComponent.hasPrefix(".") else { continue }
            out.append((p, it.value(forAttribute: "kMDItemLastUsedDate") as? Date ?? Date()))
            if out.count >= 25 { break }
        }
        q.enableUpdates()
        recentPaths = out
        if path == SpecialLocation.home { rebuild() }
    }

    // MARK: Bố cục

    @objc func relayout() {
        let width = max(320, scroll.contentSize.width)
        let gap: CGFloat = 8, side: CGFloat = 24
        var y: CGFloat = 16
        for b in blocks {
            switch b {
            case .header(let t):
                y += 4
                t.frame = NSRect(x: side, y: y, width: width - 2 * side, height: 22)
                y += 30
            case .empty(let t):
                t.frame = NSRect(x: side, y: y, width: width - 2 * side, height: 18)
                y += 30
            case .tiles(let list, let size):
                let cols = max(1, Int((width - 2 * side + gap) / (size.width + gap)))
                for (i, t) in list.enumerated() {
                    t.frame = NSRect(x: side + CGFloat(i % cols) * (size.width + gap),
                                     y: y + CGFloat(i / cols) * (size.height + gap), width: size.width, height: size.height)
                }
                let rows = (list.count + cols - 1) / cols
                y += CGFloat(rows) * (size.height + gap) + 12
            case .rows(let list):
                for r in list {
                    r.frame = NSRect(x: side - 8, y: y, width: width - 2 * side + 16, height: 32)
                    y += 32
                }
                y += 16
            }
        }
        doc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, scroll.contentSize.height))
    }

    // MARK: Chọn, mở, menu

    fileprivate func select(_ p: String?, extend: Bool) {
        if let p = p {
            if extend { if selected.contains(p) { selected.remove(p) } else { selected.insert(p) } }
            else { selected = [p] }
        } else { selected = [] }
        for v in doc.subviews { (v as? SelectablePageItem)?.refreshSelection(selected) }
        onSelectionChange?(selectedPaths)
    }

    fileprivate func open(_ p: String) { onOpen?(p) }

    fileprivate func menu(for p: String, pinned: Bool) -> NSMenu {
        if !selected.contains(p) { select(p, extend: false) }
        let m = NSMenu()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
        func add(_ key: String, _ action: @escaping () -> Void) {
            let it = ClosureMenuItem(title: L10n.t(key), action: action)
            m.addItem(it)
        }
        add("open") { [weak self] in self?.open(p) }
        if isDir.boolValue {
            add("openNewTab") { [weak self] in self?.onOpenNewTab?(p) }
            add("openNewWindow") { [weak self] in self?.onOpenNewWindow?(p) }
            m.addItem(.separator())
            if pinned || Pins.all.contains(p) { add("unpinQuick") { Pins.unpin(p) } }
            else { add("pinQuick") { Pins.pin(p) } }
        } else {
            add("openFileLocation") { [weak self] in self?.onReveal?(p) }
            m.addItem(.separator())
            if Favorites.contains(p) { add("removeFavorites") { Favorites.remove(p) } }
            else { add("addFavorites") { Favorites.add(p) } }
        }
        add("copyPath") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(PathParser.copyText(for: [p], quoted: true), forType: .string)
        }
        return m
    }
}

protocol SelectablePageItem { func refreshSelection(_ s: Set<String>) }

/// Mục menu chạy một closure (giữ chính nó làm target).
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}

final class FlippedView: NSView {
    var onClickEmpty: (() -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { onClickEmpty?() }
}

/// Ô thư mục / ổ đĩa (biểu tượng, tên, dòng phụ, thanh dung lượng).
final class TileView: NSView, SelectablePageItem {
    let path: String
    weak var owner: SpecialPageController?
    var isPinned = false
    var usage: Double? { didSet { needsLayout = true; needsDisplay = true } }
    private let icon = NSImageView()
    private let title = label("")
    private let subtitle = label("", size: 11, color: Theme.secondaryText)
    private var isSel = false { didSet { needsDisplay = true } }
    private var hover = false { didSet { needsDisplay = true } }

    init(path: String, title t: String, subtitle s: String) {
        self.path = path
        super.init(frame: .zero)
        icon.image = NSWorkspace.shared.icon(forFile: path)
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = t
        subtitle.stringValue = s
        toolTip = path
        for v in [icon, title, subtitle] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = true; addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let s: CGFloat = 40
        icon.frame = NSRect(x: 10, y: (bounds.height - s) / 2, width: s, height: s)
        let x: CGFloat = 60, w = bounds.width - x - 10
        if usage != nil {
            title.frame = NSRect(x: x, y: 10, width: w, height: 17)
            subtitle.frame = NSRect(x: x, y: 44, width: w, height: 16)
        } else {
            title.frame = NSRect(x: x, y: bounds.height / 2 - 18, width: w, height: 17)
            subtitle.frame = NSRect(x: x, y: bounds.height / 2 + 1, width: w, height: 16)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSel { Theme.selection.setFill() } else if hover { NSColor(white: 0.95, alpha: 1).setFill() } else { NSColor.clear.setFill() }
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        if let u = usage {
            let bar = NSRect(x: 60, y: 32, width: bounds.width - 70, height: 8)
            Theme.border.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            // Windows: thanh xanh, chuyển đỏ khi còn dưới 10% dung lượng.
            (u > 0.9 ? NSColor(srgbRed: 0xc4 / 255, green: 0x2b / 255, blue: 0x1c / 255, alpha: 1) : Theme.accent).setFill()
            NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(min(1, max(0, u))), height: bar.height), xRadius: 2, yRadius: 2).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }

    override func mouseDown(with event: NSEvent) {
        owner?.select(path, extend: event.modifierFlags.contains(.command))
        if event.clickCount == 2 { owner?.open(path) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.menu(for: path, pinned: isPinned) }
    func refreshSelection(_ s: Set<String>) { isSel = s.contains(path) }
}

/// Dòng tệp ở mục Ưa thích / Gần đây: tên, ngày truy cập, vị trí.
final class RecentRow: NSView, SelectablePageItem {
    let path: String
    weak var owner: SpecialPageController?
    private let icon = NSImageView()
    private let name = label("")
    private let date = label("", color: Theme.secondaryText)
    private let location = label("", color: Theme.secondaryText)
    private var isSel = false { didSet { needsDisplay = true } }

    init(path: String, date d: Date?) {
        self.path = path
        super.init(frame: .zero)
        icon.image = NSWorkspace.shared.icon(forFile: path)
        name.stringValue = (path as NSString).lastPathComponent
        date.stringValue = d.map { Formatting.date($0) } ?? ""
        let parent = (path as NSString).deletingLastPathComponent
        location.stringValue = parent.hasPrefix(NSHomeDirectory()) ? "~" + parent.dropFirst(NSHomeDirectory().count) : parent
        location.lineBreakMode = .byTruncatingMiddle
        toolTip = path
        for v in [icon, name, date, location] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = true; addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width
        icon.frame = NSRect(x: 8, y: 8, width: 16, height: 16)
        name.frame = NSRect(x: 32, y: 8, width: w * 0.45 - 32, height: 16)
        date.frame = NSRect(x: w * 0.47, y: 8, width: w * 0.18, height: 16)
        location.frame = NSRect(x: w * 0.67, y: 8, width: w * 0.33 - 8, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSel {
            Theme.selection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        owner?.select(path, extend: event.modifierFlags.contains(.command))
        if event.clickCount == 2 { owner?.open(path) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.menu(for: path, pinned: false) }
    func refreshSelection(_ s: Set<String>) { isSel = s.contains(path) }
}
