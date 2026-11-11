import AppKit
import MfileCore

/// Thông tin nhà phát triển hiện trong cửa sổ Giới thiệu (bản mẫu bảng 27).
enum Developer {
    static let company = "Công ty cổ phần Công nghệ ITD Việt Nam"
    static let phone = "0988095867"
    static let email = "vanthu.itdvn@gmail.com"
    static let website = "itdvietnam.com.vn"
    static let address = "Số 1 Ngõ 30 đường Lý Sơn, Hà Nội"
    static let year = "2026"
    static var copyright: String { "© \(year) \(company). " + L10n.t("allRightsReserved") }
}

final class AboutWindowController: NSWindowController {
    private static var shared: AboutWindowController?

    static func show() {
        if shared == nil { shared = AboutWindowController() }
        shared?.rebuild()
        shared?.window?.center()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return L10n.f("versionFmt", i?["CFBundleShortVersionString"] as? String ?? "0.1.0", i?["CFBundleVersion"] as? String ?? "dev")
    }

    private func rebuild() {
        guard let w = window else { return }
        w.title = L10n.t("aboutTitle")
        let root = ColorView(.white)
        w.contentView = root

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = label("Mac Mfile", size: 22)
        name.font = Theme.font(22, weight: .semibold)
        let tag = label(L10n.t("tagline"), color: Theme.text)
        let ver = label(version, color: Theme.secondaryText)
        ver.isSelectable = true
        let titles = NSStackView(views: [name, tag, ver])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let head = NSStackView(views: [icon, titles])
        head.spacing = 16

        let cap = label(L10n.t("developerCap").uppercased(), size: 11, color: Theme.secondaryText)
        cap.font = Theme.font(11, weight: .semibold)
        let company = label(Developer.company, size: 15)
        company.font = Theme.font(15, weight: .semibold)
        company.isSelectable = true

        func row(_ key: String, _ value: String, link: URL? = nil) -> NSView {
            let k = label(L10n.t(key), color: Theme.text)
            k.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let v: NSView
            if let link {
                let b = NSButton(title: value, target: self, action: #selector(openLink(_:)))
                b.isBordered = false
                b.attributedTitle = NSAttributedString(string: value, attributes: [.foregroundColor: Theme.accent, .font: Theme.font(12, weight: .semibold)])
                b.toolTip = link.absoluteString
                b.identifier = .init(link.absoluteString)
                v = b
            } else {
                let t = label(value)
                t.font = Theme.font(12, weight: .semibold)
                t.isSelectable = true
                v = t
            }
            let s = NSStackView(views: [k, v])
            s.spacing = 0
            return s
        }

        let copyright = label(Developer.copyright)
        copyright.isSelectable = true
        let credits = label(L10n.t("credits"), size: 11, color: Theme.secondaryText)

        func line() -> NSView {
            let v = ColorView(Theme.border)
            v.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return v
        }
        let l1 = line(), l2 = line()
        let stack = NSStackView(views: [head, l1, cap, company,
                                        row("phoneZalo", Developer.phone, link: URL(string: "https://zalo.me/" + Developer.phone)),
                                        row("emailLabel", Developer.email, link: URL(string: "mailto:" + Developer.email)),
                                        row("websiteLabel", Developer.website, link: URL(string: "https://" + Developer.website)),
                                        row("addressLabel", Developer.address), l2, copyright, credits])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: head)
        stack.setCustomSpacing(10, after: l1)
        stack.setCustomSpacing(8, after: company)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let copyB = NSButton(title: L10n.t("copyInfo"), target: self, action: #selector(copyInfo))
        let webB = NSButton(title: L10n.t("openWebsite"), target: self, action: #selector(openWebsite))
        let ok = NSButton(title: L10n.t("ok"), target: self, action: #selector(closeIt))
        ok.keyEquivalent = "\r"
        let bar = ColorView(Theme.chrome)
        let buttons = NSStackView(views: [copyB, webB, NSView(), ok])
        bar.pin(buttons, insets: .init(top: 10, left: 16, bottom: 10, right: 16))
        root.addSubview(stack)
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            l1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            l2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bar.topAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor, constant: 16),
            ok.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    var infoText: String {
        [
            "Mac Mfile – " + version,
            L10n.t("developerCap") + ": " + Developer.company,
            L10n.t("phoneZalo") + ": " + Developer.phone,
            L10n.t("emailLabel") + ": " + Developer.email,
            L10n.t("websiteLabel") + ": " + Developer.website,
            L10n.t("addressLabel") + ": " + Developer.address,
            Developer.copyright,
        ].joined(separator: "\n")
    }

    @objc private func openLink(_ sender: NSButton) {
        if let s = sender.identifier?.rawValue, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
    @objc private func openWebsite() { if let u = URL(string: "https://" + Developer.website) { NSWorkspace.shared.open(u) } }
    @objc private func copyInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(infoText, forType: .string)
    }
    @objc private func closeIt() { close() }
}
