import AppKit
import Quartz
import MfileCore

/// Ngăn bên phải: Chi tiết (Option+Shift+P) hoặc Xem trước (Option+P), như Alt+Shift+P / Alt+P của Windows (FR-07).
enum SidePaneKind: String { case none, details, preview, help }

final class SidePaneController {
    let view = ColorView(Theme.chrome)
    private(set) var kind: SidePaneKind = .none
    private let stack = NSStackView()
    private let icon = NSImageView()
    private let title = paneLabel("", size: 15)
    private let subtitle = paneLabel("", color: Theme.secondaryText)
    private let rows = NSStackView()
    private let placeholder = paneLabel("", color: Theme.secondaryText)
    private var preview: QLPreviewView?
    private var current: [FileItem] = []
    private var folderPath = ""
    let help = HelpPaneView()

    init() {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        title.font = Theme.font(15, weight: .semibold)
        title.maximumNumberOfLines = 3
        title.lineBreakMode = .byWordWrapping
        placeholder.alignment = .center
        placeholder.maximumNumberOfLines = 0
        placeholder.lineBreakMode = .byWordWrapping
        for v in [icon, title, subtitle, rows] as [NSView] { stack.addArrangedSubview(v) }
        stack.setCustomSpacing(16, after: subtitle)
        view.pin(stack, insets: .init(top: 16, left: 16, bottom: 16, right: 16))
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        for v in [title, subtitle] { v.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true }
        view.isHidden = true
        view.pin(help)
        help.isHidden = true
    }

    func show(_ k: SidePaneKind) {
        kind = k
        view.isHidden = k == .none
        help.isHidden = k != .help
        refresh()
    }

    func update(selection: [FileItem], folder: String) {
        current = selection
        folderPath = folder
        if kind != .none { refresh() }
    }

    func refresh() {
        guard kind != .none else { return }
        if kind == .help {
            stack.isHidden = true; placeholder.isHidden = true; preview?.isHidden = true
            help.reload()
            return
        }
        if kind == .preview { showPreview() } else { showDetails() }
    }

    private func showPreview() {
        stack.isHidden = true
        guard current.count == 1, !current[0].isDirectory else {
            preview?.isHidden = true
            placeholder.isHidden = false
            placeholder.stringValue = L10n.t(current.isEmpty ? "previewSelect" : (current.count > 1 ? "previewMany" : "previewNone"))
            return
        }
        if preview == nil, let p = QLPreviewView(frame: .zero, style: .normal) {
            p.autostarts = true
            view.pin(p, insets: .init(top: 8, left: 8, bottom: 8, right: 8))
            preview = p
        }
        placeholder.isHidden = true
        preview?.isHidden = false
        preview?.previewItem = URL(fileURLWithPath: current[0].path) as NSURL
    }

    private func showDetails() {
        preview?.isHidden = true
        preview?.previewItem = nil
        stack.isHidden = false
        placeholder.isHidden = true
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let fm = FileManager.default
        if current.count > 1 {
            icon.image = NSWorkspace.shared.icon(forFiles: current.map(\.path))
            title.stringValue = L10n.f("selected", current.count)
            subtitle.stringValue = ""
            let files = current.filter { !$0.isDirectory }
            addRow("colSize", Formatting.size(files.reduce(0) { $0 + $1.size }))
            return
        }
        let path = current.first?.path ?? folderPath
        let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
        icon.image = FileIcons.icon(for: path)
        let item = current.first
        title.stringValue = item?.name ?? (folderPath as NSString).lastPathComponent
        subtitle.stringValue = item?.typeDescription() ?? L10n.t("typeFolder")
        if let it = item, !it.isDirectory { addRow("colSize", Formatting.size(it.size)) }
        if let d = attrs[.modificationDate] as? Date { addRow("colModified", Formatting.date(d)) }
        if let d = attrs[.creationDate] as? Date { addRow("dateCreated", Formatting.date(d)) }
        addRow("location", (path as NSString).deletingLastPathComponent)
        if item == nil || item?.isDirectory == true,
           let n = try? fm.contentsOfDirectory(atPath: path).filter({ !$0.hasPrefix(".") }).count {
            addRow("contains", L10n.f("items", Formatting.group(Int64(n))))
        }
    }

    private func addRow(_ key: String, _ value: String) {
        let k = paneLabel(L10n.t(key), size: 11, color: Theme.secondaryText)
        let v = paneLabel(value)
        v.lineBreakMode = .byTruncatingMiddle
        v.toolTip = value
        let col = NSStackView(views: [k, v])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 1
        rows.addArrangedSubview(col)
        v.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
    }
}
