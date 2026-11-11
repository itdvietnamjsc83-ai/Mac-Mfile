import AppKit
import Carbon.HIToolbox
import MfileCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [MainWindowController] = []
    private let viewMenuStates = ViewMenuStates()
    private var hotKey: GlobalHotKey?
    private let hotKeyEnabledKey = "MacMfile.hotKeyEnabled"
    private let firstRunKey = "MacMfile.firstRunDone"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.apply()
        buildMainMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: L10n.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: Pins.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.didChange, object: nil)
        restoreSession()
        installViewModeKeys()
        installCtrlLikeWindows()
        AutoCleanWatcher.shared.restart()
        NSApp.activate(ignoringOtherApps: true)
        if UserDefaults.standard.bool(forKey: firstRunKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { TipsWindowController.show() }
        }
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            UserDefaults.standard.set(true, forKey: firstRunKey)
            DispatchQueue.main.async { self.askAboutHotKey() }
        } else if Settings.hotKeyEnabled {
            registerHotKey()
        }
    }

    /// Áp dụng Tùy chọn / Phím tắt vừa đổi: dựng lại menu, đăng ký lại phím toàn hệ thống.
    @objc private func settingsChanged() {
        buildMainMenu()
        hotKey = nil
        if Settings.hotKeyEnabled { registerHotKey(quiet: true) }
    }

    @objc func showOptions(_ sender: Any?) { OptionsWindowController.show() }
    @objc func showShortcutSettings(_ sender: Any?) { ShortcutsWindowController.show() }

    /// "Dùng phím Ctrl như Windows": Ctrl+chữ cái làm như Cmd+chữ cái (Ctrl+C sao chép…).
    private func installCtrlLikeWindows() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Settings.ctrlLikeWindows else { return event }
            let f = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard f.contains(.control), !f.contains(.command), !f.contains(.option),
                  let ch = event.charactersIgnoringModifiers?.lowercased(), ch.count == 1,
                  let c = ch.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(c) else { return event }
            var nf = event.modifierFlags
            nf.remove(.control)
            nf.insert(.command)
            return NSEvent.keyEvent(with: .keyDown, location: event.locationInWindow, modifierFlags: nf, timestamp: event.timestamp,
                                    windowNumber: event.windowNumber, context: nil, characters: ch,
                                    charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? ch,
                                    isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
        }
    }

    // MARK: Khôi phục phiên: mở lại các cửa sổ và tab lần trước (FR-02)

    private let sessionKey = "MacMfile.session"

    private func restoreSession() {
        let saved = UserDefaults.standard.array(forKey: sessionKey) as? [[String]] ?? []
        let fm = FileManager.default
        let valid = saved.map { $0.filter { SpecialLocation.isSpecial($0) || fm.fileExists(atPath: $0) } }.filter { !$0.isEmpty }
        if valid.isEmpty || !Settings.restoreSession { openWindow(at: Settings.startPage); return }
        for paths in valid { openWindow(paths: paths) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(windows.map(\.tabPaths), forKey: sessionKey)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(at: Settings.startPage) }
        return true
    }

    /// Đóng cửa sổ cuối vẫn chạy nền để Cmd+E còn mở được cửa sổ mới.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @discardableResult
    func openWindow(at path: String) -> MainWindowController { openWindow(paths: [path]) }

    @discardableResult
    func openWindow(paths: [String]) -> MainWindowController {
        let wc = MainWindowController(paths: paths)
        if let last = windows.last?.window {
            wc.window?.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + 24, y: last.frame.maxY - 24))
        }
        windows.append(wc)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        return wc
    }

    func windowClosed(_ wc: MainWindowController) {
        windows.removeAll { $0 === wc }
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow(at: Settings.startPage)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Cmd+E toàn hệ thống

    private func registerHotKey(quiet: Bool = false) {
        let combo = Settings.shortcuts.combo(for: "openApp") ?? KeyCombo("cmd+e")!
        guard let code = combo.keyCode else { return }
        var mods = 0
        if combo.command { mods |= cmdKey }
        if combo.shift { mods |= shiftKey }
        if combo.option { mods |= optionKey }
        if combo.control { mods |= controlKey }
        hotKey = GlobalHotKey(keyCode: code, modifiers: mods) { [weak self] in
            self?.newWindow(nil)
        }
        if hotKey == nil && !quiet {
            let a = NSAlert()
            a.messageText = L10n.current == .vi
                ? "Không thể dùng Cmd+E vì đã có ứng dụng khác sử dụng. Hãy chọn phím khác."
                : "Cmd+E is already used by another app. Choose a different shortcut."
            a.runModal()
        }
    }

    /// Hộp thoại lần đầu chạy (màn 8 của bản mẫu): giải thích xung đột Cmd+E.
    private func askAboutHotKey() {
        let vi = L10n.current == .vi
        let a = NSAlert()
        a.messageText = vi ? "Mở Mac Mfile bằng Cmd+E từ bất kỳ đâu?" : "Open Mac Mfile with Cmd+E from anywhere?"
        a.informativeText = vi
            ? "Giống Windows+E. Lưu ý: Safari, Pages, Xcode đang dùng Cmd+E cho “Dùng vùng chọn để tìm”; khi bật, các ứng dụng đó sẽ không nhận Cmd+E nữa. Bạn đổi phím được trong Cài đặt › Phím tắt."
            : "Just like Windows+E. Note: Safari, Pages and Xcode use Cmd+E for “Use Selection for Find”; they won't receive Cmd+E while this is on. You can change it in Settings › Shortcuts."
        a.addButton(withTitle: vi ? "Dùng Cmd+E" : "Use Cmd+E")
        a.addButton(withTitle: vi ? "Không dùng" : "Don't use")
        let use = a.runModal() == .alertFirstButtonReturn
        UserDefaults.standard.set(use, forKey: hotKeyEnabledKey)
        if use { registerHotKey() }
    }

    /// Ctrl+Shift+1…8 đổi chế độ xem như Windows; bắt theo mã phím để không phụ thuộc bố cục bàn phím.
    private func installViewModeKeys() {
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28]
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard flags == [.control, .shift], let i = digitKeys.firstIndex(of: event.keyCode),
                  let wc = NSApp.keyWindow?.windowController as? MainWindowController else { return event }
            wc.browser.setViewMode(ViewMode.allCases[i])
            return nil
        }
    }

    // MARK: Thanh menu macOS (Mục 5.4)

    @objc private func languageChanged() { buildMainMenu() }

    @objc func toggleLanguage(_ sender: Any?) { L10n.current = L10n.current.toggled }

    @objc func showAbout(_ sender: Any?) { AboutWindowController.show() }
    @objc func showTipNow(_ sender: Any?) { TipsWindowController.show(force: true) }
    @objc func toggleTips(_ sender: Any?) { Settings.showTips.toggle(); buildMainMenu() }
    @objc func showWhatsNew(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = L10n.t("whatsNew")
        a.informativeText = L10n.t("whatsNewText")
        a.runModal()
    }
    @objc func sendFeedback(_ sender: Any?) {
        let subject = "Góp ý Mac Mfile".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "mailto:\(Developer.email)?subject=\(subject)") { NSWorkspace.shared.open(u) }
    }

    @objc func showShortcuts(_ sender: Any?) {
        let vi = L10n.current == .vi
        let rows: [(String, String)] = [
            (L10n.t("back") + " / " + L10n.t("forward"), "Cmd+[ / Cmd+]"),
            (L10n.t("up"), "Cmd+↑"),
            (vi ? "Thanh địa chỉ" : "Address bar", "Cmd+L"),
            (L10n.t("search"), "Cmd+F"),
            (L10n.t("open"), "Enter"),
            (L10n.t("rename"), "F2"),
            (L10n.t("newFolderName"), "Cmd+Shift+N"),
            (vi ? "Quay lại (như Backspace)" : "Back (like Backspace)", DeleteKeys.backspaceGoesBack ? "⌫" : "Cmd+["),
            (vi ? "Chuyển vào Thùng rác" : "Move to Recycle Bin", DeleteKeys.backspaceGoesBack ? "Delete / fn+⌫ / Cmd+⌫" : "⌫"),
            (L10n.t("deleteForever"), "Shift+Delete / Shift+⌫"),
            (L10n.t("copyPath"), "Cmd+Shift+C"),
            (L10n.t("pinQuick"), "Cmd+Shift+P"),
            (vi ? "Mở mục ghim 1–9" : "Open pinned item 1–9", "Cmd+1…9"),
            (vi ? "Xem nhanh" : "Quick look", "Space"),
            (L10n.t("snapLeft") + " / " + L10n.t("snapRight"), "Cmd+← / Cmd+→"),
            (vi ? "Mở Mac Mfile từ bất kỳ đâu" : "Open Mac Mfile from anywhere", "Cmd+E"),
        ]
        let a = NSAlert()
        a.messageText = L10n.t("shortcuts")
        a.informativeText = rows.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")
        a.runModal()
    }

    /// Mục menu; phím lấy theo Cài đặt phím tắt nếu lệnh có trong danh sách phím (Mục 5.7).
    private func item(_ key: String, _ action: Selector?, _ equiv: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        var e = equiv, m = mods
        if ShortcutRegistry.action(key) != nil {
            let c = Settings.shortcuts.combo(for: key)
            e = c?.menuKey ?? ""
            m = c?.modifierFlags ?? []
        }
        let it = NSMenuItem(title: L10n.t(key), action: action, keyEquivalent: e)
        it.keyEquivalentModifierMask = m
        it.tag = tag
        return it
    }

    /// Phím phụ: mục ẩn cùng lệnh, vẫn nhận phím.
    private func secondaryItems(_ items: [NSMenuItem]) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        let b = Settings.shortcuts
        for it in items {
            out.append(it)
            guard let action = it.action,
                  let id = ShortcutRegistry.actions.first(where: { L10n.t($0.titleKey) == it.title && $0.id != "" })?.id,
                  let c = b.combo(for: id + ".2") else { continue }
            let alt = NSMenuItem(title: it.title, action: action, keyEquivalent: c.menuKey)
            alt.keyEquivalentModifierMask = c.modifierFlags
            alt.tag = it.tag
            alt.isHidden = true
            alt.allowsKeyEquivalentWhenHidden = true
            out.append(alt)
        }
        return out
    }

    private func submenu(_ titleKey: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem()
        let m = NSMenu(title: L10n.t(titleKey))
        secondaryItems(items).forEach { m.addItem($0) }
        top.submenu = m
        return top
    }

    func buildMainMenu() {
        let main = NSMenu()
        let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        let upArrow = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let f5 = String(Character(UnicodeScalar(NSF5FunctionKey)!))

        let appMenu = NSMenuItem()
        let am = NSMenu()
        am.addItem(item("about", #selector(showAbout(_:)), ""))
        am.addItem(.separator())
        am.addItem(item("settings", #selector(showOptions(_:)), ","))
        am.addItem(item("shortcutSettings", #selector(showShortcutSettings(_:)), ""))
        am.addItem(item("language", #selector(toggleLanguage(_:)), ""))
        am.addItem(.separator())
        am.addItem(item("hide", #selector(NSApplication.hide(_:)), "h"))
        am.addItem(item("quit", #selector(NSApplication.terminate(_:)), "q"))
        appMenu.submenu = am
        main.addItem(appMenu)

        main.addItem(submenu("menuFile", [
            item("newWindow", #selector(newWindow(_:)), "n"),
            item("newTab", #selector(MainWindowController.newTab(_:)), "t"),
            item("newFolderName", #selector(BrowserViewController.newFolder(_:)), "n", [.command, .shift]),
            item("open", #selector(BrowserViewController.openSelected(_:)), "o"),
            .separator(),
            item("properties", #selector(BrowserViewController.showInfo(_:)), "i"),
            .separator(),
            item("closeTab", #selector(MainWindowController.closeCurrentTab(_:)), "w"),
            item("closeWindow", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
        ]))

        main.addItem(submenu("menuEdit", [
            item("undo", Selector(("undo:")), "z"),
            item("redo", Selector(("redo:")), "y"),
            .separator(),
            item("cut", #selector(BrowserViewController.cut(_:)), "x"),
            item("copy", #selector(BrowserViewController.copy(_:)), "c"),
            item("paste", #selector(BrowserViewController.paste(_:)), "v"),
            item("copyPath", #selector(BrowserViewController.copyPath(_:)), "c", [.command, .shift]),
            item("pasteAndGo", #selector(BrowserViewController.pasteAndGo(_:)), ""),
            item("selectAll", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("search", #selector(BrowserViewController.focusSearch(_:)), "f"),
        ]))

        // Windows: Ctrl+Shift+1…8 đổi chế độ xem. Giữ đúng phím Ctrl (Cmd+Shift+3/4/5 là chụp màn hình của macOS).
        var viewItems: [NSMenuItem] = ViewMode.allCases.enumerated().map { i, mode in
            item(mode.titleKey, #selector(BrowserViewController.setViewModeFromMenu(_:)), "\(i + 1)", [.control, .shift], tag: i)
        }
        viewItems += [
            item("compactView", #selector(BrowserViewController.toggleCompact(_:)), ""),
            item("hiddenItems", #selector(BrowserViewController.toggleHidden(_:)), ".", [.command, .shift]),
            item("toggleTheme", #selector(BrowserViewController.toggleTheme(_:)), "l", [.command, .shift]),
            item("previewPane", #selector(BrowserViewController.togglePreviewPane(_:)), "p", [.option]),
            item("detailsPane", #selector(BrowserViewController.toggleDetailsPane(_:)), "p", [.option, .shift]),
            .separator(),
            item("refresh", #selector(BrowserViewController.refresh(_:)), "r"),
            item("refresh", #selector(BrowserViewController.refresh(_:)), f5, []),
        ]
        let viewMenu = submenu("menuView", viewItems)
        viewMenu.submenu?.delegate = viewMenuStates
        main.addItem(viewMenu)

        var go: [NSMenuItem] = [
            item("back", #selector(BrowserViewController.goBack(_:)), "["),
            item("forward", #selector(BrowserViewController.goForward(_:)), "]"),
            item("up", #selector(BrowserViewController.goUp(_:)), upArrow),
            .separator(),
            item("home", #selector(BrowserViewController.goHome(_:)), "h", [.command, .shift]),
            item("thisMac", #selector(BrowserViewController.goThisMac(_:)), ""),
            item("goToFolder", #selector(BrowserViewController.focusAddress(_:)), "l"),
            .separator(),
            item("pinQuick", #selector(BrowserViewController.pinSelected(_:)), "p", [.command, .shift]),
        ]
        for (i, p) in Pins.all.prefix(9).enumerated() {
            let it = NSMenuItem(title: (p as NSString).lastPathComponent, action: #selector(BrowserViewController.openPin(_:)), keyEquivalent: "\(i + 1)")
            it.tag = i
            go.append(it)
        }
        main.addItem(submenu("menuGo", go))

        main.addItem(submenu("menuWindow", [
            item("minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("maximize", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            item("nextTab", #selector(MainWindowController.nextTab(_:)), "\t", [.control]),
            item("previousTab", #selector(MainWindowController.previousTab(_:)), "\t", [.control, .shift]),
            item("duplicateTab", #selector(MainWindowController.duplicateTab(_:)), ""),
            .separator(),
            item("snapLeft", #selector(MainWindowController.snapLeft(_:)), left),
            item("snapRight", #selector(MainWindowController.snapRight(_:)), right),
        ]))

        let tipsItem = item("tipsAtLaunchMenu", #selector(toggleTips(_:)), "")
        tipsItem.state = Settings.showTips ? .on : .off
        let help = submenu("menuHelp", [
            item("userGuide", #selector(BrowserViewController.showHelp(_:)), String(Character(UnicodeScalar(NSF1FunctionKey)!)), []),
            item("shortcuts", #selector(showShortcuts(_:)), "/"),
            item("windowsUsers", #selector(BrowserViewController.showWindowsGuide(_:)), ""),
            item("tipOfDay", #selector(showTipNow(_:)), ""),
            tipsItem,
            .separator(),
            item("whatsNew", #selector(showWhatsNew(_:)), ""),
            item("sendFeedback", #selector(sendFeedback(_:)), ""),
            item("aboutTitle", #selector(showAbout(_:)), ""),
        ])
        main.addItem(help)

        NSApp.mainMenu = main
        NSApp.windowsMenu = main.item(at: 5)?.submenu
        NSApp.helpMenu = help.submenu
    }
}


/// Đánh dấu chế độ xem đang dùng trong menu Xem của thanh menu macOS.
final class ViewMenuStates: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let browser = (NSApp.keyWindow?.windowController as? MainWindowController)?.browser
        for it in menu.items {
            if it.action == #selector(BrowserViewController.setViewModeFromMenu(_:)) {
                it.state = browser?.viewMode == ViewMode.allCases[it.tag] ? .on : .off
            } else if it.action == #selector(BrowserViewController.toggleCompact(_:)) {
                it.state = browser?.isCompact == true ? .on : .off
            } else if it.action == #selector(BrowserViewController.togglePreviewPane(_:)) {
                it.state = browser?.paneKind == .preview ? .on : .off
            } else if it.action == #selector(BrowserViewController.toggleDetailsPane(_:)) {
                it.state = browser?.paneKind == .details ? .on : .off
            } else if it.action == #selector(BrowserViewController.toggleHidden(_:)) {
                it.state = browser?.isShowingHidden == true ? .on : .off
            }
        }
    }
}
