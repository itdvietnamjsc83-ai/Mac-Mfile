import AppKit
import Security
import MfileCore

/// Hộp "Nén thành tệp ZIP" có đặt mật khẩu (bản mẫu bảng 25).
final class CompressDialog: NSObject, NSTextFieldDelegate {
    struct Choice { let name: String; let format: String; let password: String?; let encryption: ZipEncryption }

    private let nameField = NSTextField()
    private let format = NSPopUpButton()
    private let usePassword = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let pw1 = NSSecureTextField(), pw2 = NSSecureTextField()
    private let pw1Plain = NSTextField(), pw2Plain = NSTextField()
    private let eye = NSButton()
    private let strength = NSProgressIndicator()
    private let strengthLabel = label("")
    private let encryption = NSPopUpButton()
    private let warn = label("", color: Theme.text)
    private let error = label("", color: Theme.closeHover)
    private static let formats = [("zip", "fmtZip"), ("7z", "fmt7z"), ("tar", "fmtTar"), ("tar.gz", "fmtTarGz")]
    private var showing = false

    static func run(count: Int, defaultName: String, password: Bool, on window: NSWindow, done: @escaping (Choice) -> Void) {
        let d = CompressDialog()
        d.present(count: count, defaultName: defaultName, password: password, on: window, done: done)
    }

    private func present(count: Int, defaultName: String, password: Bool, on window: NSWindow, done: @escaping (Choice) -> Void) {
        let a = NSAlert()
        a.messageText = L10n.f("compressTitle", count)
        a.addButton(withTitle: L10n.t("compressButton"))
        a.addButton(withTitle: L10n.t("cancel"))
        nameField.stringValue = defaultName + ".zip"
        for (_, key) in Self.formats { format.addItem(withTitle: L10n.t(key)) }
        format.target = self; format.action = #selector(formatChanged)
        usePassword.title = L10n.t("setPassword")
        usePassword.state = password ? .on : .off
        usePassword.target = self; usePassword.action = #selector(refresh)
        for f in [pw1, pw2, pw1Plain, pw2Plain] { f.delegate = self; f.translatesAutoresizingMaskIntoConstraints = false }
        eye.image = Theme.symbol("eye")
        eye.bezelStyle = .rounded
        eye.target = self; eye.action = #selector(toggleShow)
        eye.toolTip = L10n.t("showPassword")
        strength.style = .bar; strength.isIndeterminate = false; strength.minValue = 0; strength.maxValue = 3
        encryption.addItems(withTitles: [L10n.t("encAES"), L10n.t("encZipCrypto")])
        warn.stringValue = L10n.t("rememberPassword")
        warn.maximumNumberOfLines = 0
        warn.lineBreakMode = .byWordWrapping
        error.maximumNumberOfLines = 0

        func row(_ key: String, _ v: NSView) -> NSStackView {
            let l = label(L10n.t(key))
            l.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let s = NSStackView(views: [l, v])
            s.spacing = 8
            return s
        }
        let pwBox1 = NSView(), pwBox2 = NSView()
        for (box, a1, a2) in [(pwBox1, pw1, pw1Plain), (pwBox2, pw2, pw2Plain)] {
            box.translatesAutoresizingMaskIntoConstraints = false
            for f in [a1, a2] as [NSTextField] {
                box.addSubview(f)
                NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: box.leadingAnchor), f.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                                             f.topAnchor.constraint(equalTo: box.topAnchor), f.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
            }
            a2.isHidden = true
            box.widthAnchor.constraint(equalToConstant: 230).isActive = true
        }
        let pwRow = row("passwordLabel", pwBox1)
        pwRow.addArrangedSubview(eye)
        let strengthRow = row("strengthLabel", strength)
        strengthRow.addArrangedSubview(strengthLabel)
        strength.widthAnchor.constraint(equalToConstant: 200).isActive = true
        nameField.widthAnchor.constraint(equalToConstant: 270).isActive = true
        let stack = NSStackView(views: [row("archiveName", nameField), row("formatLabel", format), usePassword, pwRow,
                                        row("confirmPassword", pwBox2), strengthRow, row("encryptionLabel", encryption), warn, error])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        warn.widthAnchor.constraint(equalToConstant: 410).isActive = true
        error.widthAnchor.constraint(equalToConstant: 410).isActive = true
        a.accessoryView = stack
        refresh()
        a.window.initialFirstResponder = password ? pw1 : nameField

        // Nút Nén chỉ đóng hộp khi hợp lệ.
        let okButton = a.buttons[0]
        okButton.target = self
        okButton.action = #selector(okPressed(_:))
        objc_setAssociatedObject(a, &Self.key, self, .OBJC_ASSOCIATION_RETAIN)
        self.alert = a
        a.beginSheetModal(for: window) { [self] r in
            guard r == .alertFirstButtonReturn else { return }
            let fmt = Self.formats[self.format.indexOfSelectedItem].0
            var name = self.nameField.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.lowercased().hasSuffix("." + fmt) { name += "." + fmt }
            let pw = self.passwordAllowed && self.usePassword.state == .on ? self.currentPw1 : nil
            done(Choice(name: name, format: fmt, password: pw, encryption: self.encryption.indexOfSelectedItem == 0 ? .aes256 : .zipCrypto))
        }
    }
    private static var key = 0
    private weak var alert: NSAlert?

    private var currentPw1: String { showing ? pw1Plain.stringValue : pw1.stringValue }
    private var currentPw2: String { showing ? pw2Plain.stringValue : pw2.stringValue }
    private var passwordAllowed: Bool { format.indexOfSelectedItem == 0 }

    @objc private func okPressed(_ sender: NSButton) {
        if passwordAllowed && usePassword.state == .on {
            if currentPw1.isEmpty { error.stringValue = L10n.t("passwordEmpty"); return }
            if currentPw1 != currentPw2 { error.stringValue = L10n.t("passwordMismatch"); return }
        }
        if nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { NSSound.beep(); return }
        guard let a = alert else { return }
        a.window.sheetParent?.endSheet(a.window, returnCode: .alertFirstButtonReturn)
    }

    @objc private func formatChanged() {
        let fmt = Self.formats[format.indexOfSelectedItem].0
        let base = ArchiveSupport.baseName(of: nameField.stringValue)
        nameField.stringValue = base + "." + fmt
        refresh()
    }

    @objc private func toggleShow() {
        showing.toggle()
        if showing { pw1Plain.stringValue = pw1.stringValue; pw2Plain.stringValue = pw2.stringValue }
        else { pw1.stringValue = pw1Plain.stringValue; pw2.stringValue = pw2Plain.stringValue }
        pw1.isHidden = showing; pw2.isHidden = showing
        pw1Plain.isHidden = !showing; pw2Plain.isHidden = !showing
        eye.image = Theme.symbol(showing ? "eye.slash" : "eye")
    }

    func controlTextDidChange(_ obj: Notification) { error.stringValue = ""; refresh() }

    @objc private func refresh() {
        let allowed = passwordAllowed
        usePassword.isEnabled = allowed
        if !allowed { usePassword.toolTip = L10n.t("passwordZipOnly") }
        let on = allowed && usePassword.state == .on
        for c in [pw1, pw2, pw1Plain, pw2Plain, eye, encryption] as [NSControl] { c.isEnabled = on }
        warn.isHidden = !on
        let s = PasswordStrength.score(currentPw1)
        strength.doubleValue = currentPw1.isEmpty ? 0 : Double(s + 1)
        strengthLabel.stringValue = currentPw1.isEmpty || !on ? "" : L10n.t(["strengthWeak", "strengthMedium", "strengthStrong"][s])
    }
}

/// Hỏi mật khẩu khi giải nén (bản mẫu bảng 26); có thể nhớ trong Chuỗi khóa.
enum PasswordPrompt {
    static func ask(for archive: String, wrong: Bool, on window: NSWindow?, done: @escaping (String?, Bool) -> Void) {
        let a = NSAlert()
        a.messageText = L10n.t("archiveProtected")
        a.informativeText = L10n.f("enterPasswordFor", (archive as NSString).lastPathComponent) + (wrong ? "\n\n" + L10n.t("wrongPassword") : "")
        a.icon = Theme.symbol("lock.fill", size: 32)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 24))
        let remember = NSButton(checkboxWithTitle: L10n.t("rememberInKeychain"), target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 300, height: 20)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 54))
        box.addSubview(field)
        box.addSubview(remember)
        a.accessoryView = box
        a.addButton(withTitle: L10n.t("ok"))
        a.addButton(withTitle: L10n.t("cancel"))
        a.window.initialFirstResponder = field
        let handler: (NSApplication.ModalResponse) -> Void = { r in
            done(r == .alertFirstButtonReturn ? field.stringValue : nil, remember.state == .on)
        }
        if let w = window { a.beginSheetModal(for: w, completionHandler: handler) } else { handler(a.runModal()) }
    }
}

/// Lưu mật khẩu tệp nén trong Chuỗi khóa của macOS (không lưu ở chỗ khác).
enum ArchiveKeychain {
    private static let service = "Mac Mfile – mật khẩu tệp nén"

    static func password(for path: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: path, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ pw: String, for path: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: path]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(pw.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
