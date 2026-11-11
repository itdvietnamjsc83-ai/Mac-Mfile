import AppKit
import MfileCore

/// Vùng nội dung cho 7 chế độ xem không phải Chi tiết (FR-06, Mục 5.2):
/// biểu tượng cực lớn/lớn/trung bình/nhỏ, danh sách, ô xếp, nội dung.
final class FileCollectionView: NSCollectionView {
    var onOpen: (() -> Void)?
    var onTrash: (() -> Void)?
    var onDeleteForever: (() -> Void)?
    var onRename: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onProperties: (() -> Void)?
    var onBack: (() -> Void)?
    /// Chỉ số mục vừa nhấp chuột phải (-1 nếu nhấp vào chỗ trống).
    private(set) var clickedIndex = -1

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76: if flags.contains(.option) { onProperties?() } else { onOpen?() }
        case 51, 117:
            switch DeleteKeys.action(keyCode: event.keyCode, flags: flags) {
            case .back: onBack?()
            case .trash: onTrash?()
            case .deleteForever: onDeleteForever?()
            case .none: super.keyDown(with: event)
            }
        case 120: onRename?()
        case 49 where flags.isEmpty: onQuickLook?()
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            let p = convert(event.locationInWindow, from: nil)
            if indexPathForItem(at: p) != nil { onOpen?() }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: p) {
            clickedIndex = ip.item
            // Như Windows: nhấp chuột phải vào mục chưa chọn thì chọn riêng mục đó.
            if !selectionIndexPaths.contains(ip) {
                let old = selectionIndexPaths
                deselectItems(at: old)
                delegate?.collectionView?(self, didDeselectItemsAt: old)
                selectItems(at: [ip], scrollPosition: [])
                delegate?.collectionView?(self, didSelectItemsAt: [ip])
            }
        } else {
            clickedIndex = -1
        }
        return menu
    }

    var selectedIndexes: IndexSet { IndexSet(selectionIndexPaths.map(\.item)) }

    func select(_ indexes: IndexSet, scroll: Bool) {
        let ips = Set(indexes.map { IndexPath(item: $0, section: 0) })
        deselectItems(at: selectionIndexPaths)
        selectItems(at: ips, scrollPosition: scroll ? .nearestHorizontalEdge.union(.nearestVerticalEdge) : [])
    }
}

/// Một ô trong vùng nội dung; tự bố trí theo chế độ xem.
final class FileCellItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("FileCell")
    private let icon = NSImageView()
    private let name = label("")
    private let line2 = label("", color: Theme.secondaryText)
    private let line3 = label("", color: Theme.secondaryText)
    private let right1 = label("", color: Theme.secondaryText)
    private let right2 = label("", color: Theme.secondaryText)
    private var mode: ViewMode = .mediumIcons
    var dimmed = false { didSet { icon.alphaValue = dimmed ? 0.5 : 1 } }

    override func loadView() {
        let v = CellView()
        v.owner = self
        for s in [icon, name, line2, line3, right1, right2] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = true
            v.addSubview(s)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        view = v
    }

    func configure(_ it: FileItem, mode: ViewMode) {
        self.mode = mode
        icon.image = NSWorkspace.shared.icon(forFile: it.path)
        name.stringValue = Settings.displayName(it)
        name.toolTip = it.name
        let size = it.isDirectory ? "" : Formatting.size(it.size)
        let date = Formatting.date(it.modified)
        line2.stringValue = ""; line3.stringValue = ""; right1.stringValue = ""; right2.stringValue = ""
        switch mode {
        case .tiles:
            line2.stringValue = it.typeDescription()
            line3.stringValue = size
        case .content:
            line2.stringValue = it.typeDescription()
            right1.stringValue = L10n.t("colModified") + ": " + date
            right2.stringValue = size.isEmpty ? "" : L10n.t("colSize") + ": " + size
        default: break
        }
        let below = mode.showsLabelBelowIcon
        name.alignment = below ? .center : .left
        name.maximumNumberOfLines = below ? 2 : 1
        name.lineBreakMode = below ? .byWordWrapping : .byTruncatingTail
        name.cell?.truncatesLastVisibleLine = true
        view.needsLayout = true
        view.needsDisplay = true
    }

    override var isSelected: Bool { didSet { view.needsDisplay = true } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { view.needsDisplay = true } }

    fileprivate func layoutCell(in b: NSRect) {
        let s = CGFloat(mode.iconSize)
        let hidden = { (v: NSView, h: Bool) in v.isHidden = h }
        switch mode {
        case .extraLargeIcons, .largeIcons, .mediumIcons:
            icon.frame = NSRect(x: (b.width - s) / 2, y: b.height - s - 8, width: s, height: s)
            name.frame = NSRect(x: 4, y: 4, width: b.width - 8, height: b.height - s - 14)
            [line2, line3, right1, right2].forEach { hidden($0, true) }
        case .smallIcons, .list, .details:
            icon.frame = NSRect(x: 6, y: (b.height - s) / 2, width: s, height: s)
            name.frame = NSRect(x: 30, y: (b.height - 16) / 2, width: b.width - 36, height: 16)
            [line2, line3, right1, right2].forEach { hidden($0, true) }
        case .tiles:
            icon.frame = NSRect(x: 8, y: (b.height - s) / 2, width: s, height: s)
            let x = s + 18, w = b.width - x - 8
            let top = (b.height - 48) / 2
            name.frame = NSRect(x: x, y: top + 32, width: w, height: 16)
            line2.frame = NSRect(x: x, y: top + 16, width: w, height: 16)
            line3.frame = NSRect(x: x, y: top, width: w, height: 16)
            [line2, line3].forEach { hidden($0, false) }
            [right1, right2].forEach { hidden($0, true) }
        case .content:
            icon.frame = NSRect(x: 12, y: (b.height - s) / 2, width: s, height: s)
            let x = s + 24, mid = b.height / 2
            let colW = min(260, b.width * 0.35)
            let nameW = max(80, b.width - x - colW - 16)
            name.frame = NSRect(x: x, y: mid + 1, width: nameW, height: 16)
            line2.frame = NSRect(x: x, y: mid - 17, width: nameW, height: 16)
            right1.frame = NSRect(x: b.width - colW - 8, y: mid + 1, width: colW, height: 16)
            right2.frame = NSRect(x: b.width - colW - 8, y: mid - 17, width: colW, height: 16)
            [line2, right1, right2].forEach { hidden($0, false) }
            hidden(line3, true)
        }
        name.isHidden = false
    }

    fileprivate func drawBackground(in b: NSRect) {
        if isSelected {
            Theme.selection.setFill()
            NSBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        } else if highlightState == .forSelection {
            Theme.selection.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        if mode == .content {
            Theme.border.setFill()
            NSRect(x: 0, y: 0, width: b.width, height: 1).fill()
        }
    }
}

private final class CellView: NSView {
    weak var owner: FileCellItem?
    override var isFlipped: Bool { false }
    override func layout() {
        super.layout()
        owner?.layoutCell(in: bounds)
    }
    override func draw(_ dirtyRect: NSRect) {
        owner?.drawBackground(in: bounds)
    }
}
