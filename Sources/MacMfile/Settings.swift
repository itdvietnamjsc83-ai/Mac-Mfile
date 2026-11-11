import AppKit
import MfileCore

/// Tùy chọn của người dùng (Mục 5.5, bản mẫu bảng 17–18). Mọi thay đổi phát `didChange` để cửa sổ cập nhật ngay.
enum Settings {
    static let didChange = Notification.Name("MacMfile.settingsDidChange")
    private static var d: UserDefaults { .standard }

    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }

    static var startPage: String {
        get { d.string(forKey: "MacMfile.startPage") ?? SpecialLocation.home }
        set { d.set(newValue, forKey: "MacMfile.startPage") }
    }
    static var openFoldersInNewWindow: Bool { get { bool("MacMfile.openInNewWindow", false) } set { d.set(newValue, forKey: "MacMfile.openInNewWindow") } }
    static var restoreSession: Bool { get { bool("MacMfile.restoreSession", true) } set { d.set(newValue, forKey: "MacMfile.restoreSession") } }
    static var hotKeyEnabled: Bool { get { bool("MacMfile.hotKeyEnabled", true) } set { d.set(newValue, forKey: "MacMfile.hotKeyEnabled") } }
    static var hideExtensions: Bool { get { bool("MacMfile.hideExtensions", false) } set { d.set(newValue, forKey: "MacMfile.hideExtensions") } }
    static var fullPathInTitle: Bool { get { bool("MacMfile.fullPathInTitle", false) } set { d.set(newValue, forKey: "MacMfile.fullPathInTitle") } }
    static var confirmTrash: Bool { get { !bool("MacMfile.skipTrashConfirm", false) } set { d.set(!newValue, forKey: "MacMfile.skipTrashConfirm") } }
    static var showRecent: Bool { get { bool("MacMfile.showRecent", true) } set { d.set(newValue, forKey: "MacMfile.showRecent") } }
    static var showFavorites: Bool { get { bool("MacMfile.showFavorites", true) } set { d.set(newValue, forKey: "MacMfile.showFavorites") } }
    static var recentClearedAt: Date? { get { d.object(forKey: "MacMfile.recentClearedAt") as? Date } set { d.set(newValue, forKey: "MacMfile.recentClearedAt") } }
    static var showCloudInSidebar: Bool { get { bool("MacMfile.sidebarCloud", true) } set { d.set(newValue, forKey: "MacMfile.sidebarCloud") } }
    static var showVolumesInSidebar: Bool { get { bool("MacMfile.sidebarVolumes", true) } set { d.set(newValue, forKey: "MacMfile.sidebarVolumes") } }
    static var searchSubfolders: Bool { get { bool("MacMfile.searchSubfolders", true) } set { d.set(newValue, forKey: "MacMfile.searchSubfolders") } }
    static var quotePaths: Bool { get { bool("MacMfile.quotePaths", true) } set { d.set(newValue, forKey: "MacMfile.quotePaths") } }
    static var showTips: Bool { get { bool("MacMfile.showTips", true) } set { d.set(newValue, forKey: "MacMfile.showTips") } }
    static var ctrlLikeWindows: Bool { get { bool("MacMfile.ctrlLikeWindows", false) } set { d.set(newValue, forKey: "MacMfile.ctrlLikeWindows") } }

    static var shortcuts: ShortcutBindings {
        get {
            guard let data = d.data(forKey: "MacMfile.shortcuts"), let b = try? ShortcutBindings.importJSON(data) else { return ShortcutBindings() }
            return b
        }
        set { d.set(try? newValue.exportJSON(), forKey: "MacMfile.shortcuts") }
    }

    /// Tên hiển thị: ẩn đuôi tệp nếu người dùng chọn (như "Ẩn phần mở rộng" của Windows).
    static func displayName(_ item: FileItem) -> String {
        guard hideExtensions, !item.isDirectory, !item.fileExtension.isEmpty else { return item.name }
        return (item.name as NSString).deletingPathExtension
    }

    static func changed() { NotificationCenter.default.post(name: didChange, object: nil) }

    static func resetAll() {
        for k in d.dictionaryRepresentation().keys where k.hasPrefix("MacMfile.") &&
            !["MacMfile.session", "MacMfile.pins", "MacMfile.favorites", "MacMfile.firstRunDone"].contains(k) {
            d.removeObject(forKey: k)
        }
        changed()
    }
}

extension KeyCombo {
    /// Ký tự keyEquivalent cho NSMenuItem.
    var menuKey: String {
        func fn(_ k: Int) -> String { String(Character(UnicodeScalar(k)!)) }
        switch key {
        case "up": return fn(NSUpArrowFunctionKey)
        case "down": return fn(NSDownArrowFunctionKey)
        case "left": return fn(NSLeftArrowFunctionKey)
        case "right": return fn(NSRightArrowFunctionKey)
        case "return": return "\r"
        case "tab": return "\t"
        case "space": return " "
        case "delete": return "\u{8}"
        case "esc": return "\u{1b}"
        default:
            if key.count >= 2, key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...20).contains(n) { return fn(NSF1FunctionKey + n - 1) }
            return key
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }
        if shift { f.insert(.shift) }
        if option { f.insert(.option) }
        if control { f.insert(.control) }
        return f
    }

    /// Đọc tổ hợp từ một lần bấm phím (bảng ghi phím trong Cài đặt phím tắt).
    init?(event: NSEvent) {
        let special: [UInt16: String] = [126: "up", 125: "down", 123: "left", 124: "right", 36: "return", 48: "tab", 49: "space",
                                         51: "delete", 53: "esc", 122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
                                         98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"]
        let f = event.modifierFlags
        let k: String
        if let s = special[event.keyCode] { k = s }
        else if let c = KeyCombo.ansiKeys.first(where: { $0.value == Int(event.keyCode) })?.key { k = c }
        else if let c = event.charactersIgnoringModifiers?.lowercased(), !c.isEmpty { k = c }
        else { return nil }
        self.init(key: k, command: f.contains(.command), shift: f.contains(.shift), option: f.contains(.option), control: f.contains(.control))
    }

    /// Mã phím vật lý (bố cục ANSI) cho phím toàn hệ thống.
    static let ansiKeys: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    var keyCode: Int? {
        if let c = Self.ansiKeys[key] { return c }
        let special: [String: Int] = ["up": 126, "down": 125, "left": 123, "right": 124, "return": 36, "tab": 48, "space": 49, "delete": 51,
                                      "esc": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
                                      "f9": 101, "f10": 109, "f11": 103, "f12": 111]
        return special[key]
    }
}
