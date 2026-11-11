import Foundation

/// Một tổ hợp phím, lưu dạng chữ "cmd+shift+n" (Mục 5.7).
public struct KeyCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    public var key: String
    public var command = false, shift = false, option = false, control = false

    public init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command; self.shift = shift; self.option = option; self.control = control
    }

    public init?(_ string: String) {
        let parts = string.lowercased().split(separator: "+").map(String.init)
        guard let k = parts.last, !k.isEmpty else { return nil }
        key = k
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command": command = true
            case "shift": shift = true
            case "opt", "option", "alt": option = true
            case "ctrl", "control": control = true
            default: return nil
            }
        }
    }

    public var stringValue: String {
        var p: [String] = []
        if control { p.append("ctrl") }
        if option { p.append("opt") }
        if shift { p.append("shift") }
        if command { p.append("cmd") }
        return (p + [key]).joined(separator: "+")
    }

    static let keyNames: [String: String] = [
        "up": "↑", "down": "↓", "left": "←", "right": "→", "return": "Enter", "delete": "⌫", "space": "Space",
        "tab": "Tab", "esc": "Esc", "[": "[", "]": "]",
    ]

    /// Cách viết hiện trên màn hình: "Cmd+Shift+N", "Option+←".
    public var description: String {
        var p: [String] = []
        if command { p.append("Cmd") }
        if control { p.append("Ctrl") }
        if option { p.append("Option") }
        if shift { p.append("Shift") }
        let k = Self.keyNames[key] ?? key.uppercased()
        return (p + [k]).joined(separator: "+")
    }

    public var hasModifier: Bool { command || option || control }
}

public struct ShortcutAction: Sendable {
    public let id: String
    public let titleKey: String
    public let category: String
    public let mac: KeyCombo?
    public let windows: KeyCombo?
    public let isGlobal: Bool
}

public enum ShortcutPreset: String, CaseIterable, Sendable { case mac, windows }

/// Danh sách mọi lệnh có phím tắt, phím mặc định kiểu Mac và kiểu Windows (Mục 5.7).
public enum ShortcutRegistry {
    private static func a(_ id: String, _ cat: String, _ mac: String?, _ win: String? = "same", title: String? = nil, global: Bool = false) -> ShortcutAction {
        let m = mac.flatMap(KeyCombo.init)
        let w: KeyCombo? = win == "same" ? m : win.flatMap(KeyCombo.init)
        return ShortcutAction(id: id, titleKey: title ?? id, category: cat, mac: m, windows: w, isGlobal: global)
    }

    public static let actions: [ShortcutAction] = [
        a("openApp", "catGeneral", "cmd+e", title: "openAppAnywhere", global: true),
        a("newWindow", "catFile", "cmd+n"),
        a("newTab", "catFile", "cmd+t"),
        a("newFolderName", "catFile", "cmd+shift+n"),
        a("open", "catFile", "cmd+o"),
        a("properties", "catFile", "cmd+i"),
        a("closeTab", "catFile", "cmd+w"),
        a("closeWindow", "catFile", "cmd+shift+w"),
        a("cut", "catEdit", "cmd+x"),
        a("copy", "catEdit", "cmd+c"),
        a("paste", "catEdit", "cmd+v"),
        a("copyPath", "catEdit", "cmd+shift+c"),
        a("pasteAndGo", "catEdit", nil),
        a("selectAll", "catEdit", "cmd+a"),
        a("search", "catEdit", "cmd+f"),
        a("undo", "catEdit", "cmd+z"),
        a("redo", "catEdit", "cmd+y"),
        a("refresh", "catView", "cmd+r"),
        a("compactView", "catView", nil),
        a("hiddenItems", "catView", "cmd+shift+."),
        a("previewPane", "catView", "opt+p"),
        a("detailsPane", "catView", "opt+shift+p"),
        a("back", "catGo", "cmd+[", "opt+left"),
        a("forward", "catGo", "cmd+]", "opt+right"),
        a("up", "catGo", "cmd+up", "opt+up"),
        a("home", "catGo", "cmd+shift+h"),
        a("thisMac", "catGo", nil),
        a("goToFolder", "catGo", "cmd+l"),
        a("pinQuick", "catGo", "cmd+shift+p"),
        a("minimize", "catWindow", "cmd+m"),
        a("nextTab", "catWindow", "ctrl+tab"),
        a("previousTab", "catWindow", "ctrl+shift+tab"),
        a("duplicateTab", "catWindow", nil),
        a("snapLeft", "catWindow", "cmd+left"),
        a("snapRight", "catWindow", "cmd+right"),
        a("userGuide", "catHelp", "f1"),
        a("shortcuts", "catHelp", "cmd+/"),
        a("settings", "catGeneral", "cmd+,"),
    ]

    public static func action(_ id: String) -> ShortcutAction? { actions.first { $0.id == id } }

    /// Phím macOS giữ riêng, không gán được (chụp màn hình, Spotlight, chuyển ứng dụng).
    public static let systemReserved: [String: String] = [
        "shift+cmd+3": "Chụp màn hình / Screenshot", "shift+cmd+4": "Chụp màn hình / Screenshot",
        "shift+cmd+5": "Chụp màn hình / Screenshot", "cmd+space": "Spotlight", "cmd+tab": "App Switcher",
        "cmd+q": "Thoát / Quit", "cmd+h": "Ẩn / Hide", "ctrl+cmd+q": "Khóa màn hình / Lock Screen",
    ]

    public static func defaults(_ preset: ShortcutPreset) -> [String: KeyCombo] {
        var d: [String: KeyCombo] = [:]
        for x in actions { if let c = preset == .mac ? x.mac : x.windows { d[x.id] = c } }
        return d
    }

    /// Các lệnh dùng chung một phím.
    public static func conflicts(_ bindings: [String: KeyCombo]) -> [KeyCombo: [String]] {
        var by: [KeyCombo: [String]] = [:]
        for (id, c) in bindings { by[c, default: []].append(id) }
        return by.filter { $0.value.count > 1 }.mapValues { $0.sorted() }
    }

    /// Ai đang dùng phím này (lệnh khác hoặc hệ thống).
    public static func owner(of combo: KeyCombo, in bindings: [String: KeyCombo], except id: String) -> String? {
        if let s = systemReserved[combo.stringValue] { return "system:" + s }
        return bindings.first { $0.key != id && $0.value == combo }?.key
    }

    /// Gợi ý phím còn trống gần giống phím người dùng muốn: thêm Shift, Option, Ctrl.
    public static func suggest(for combo: KeyCombo, in bindings: [String: KeyCombo], except id: String) -> KeyCombo? {
        var tries: [KeyCombo] = []
        var c = combo
        if !c.shift { c.shift = true; tries.append(c) }
        c = combo
        if !c.option { c.option = true; tries.append(c) }
        c = combo
        if !c.control { c.control = true; tries.append(c) }
        c = combo
        c.shift = true; c.option = true; tries.append(c)
        return tries.first { owner(of: $0, in: bindings, except: id) == nil }
    }
}

/// Phím người dùng đã đổi so với bộ mặc định; xuất/nhập được ra tệp JSON.
public struct ShortcutBindings: Codable, Equatable, Sendable {
    public var preset: ShortcutPreset = .mac
    public var overrides: [String: String] = [:]   // id -> "cmd+k" hoặc "" (không dùng phím)

    public init(preset: ShortcutPreset = .mac, overrides: [String: String] = [:]) {
        self.preset = preset
        self.overrides = overrides
    }

    enum CodingKeys: String, CodingKey { case preset, overrides }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = ShortcutPreset(rawValue: (try? c.decode(String.self, forKey: .preset)) ?? "mac") ?? .mac
        overrides = (try? c.decode([String: String].self, forKey: .overrides)) ?? [:]
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset.rawValue, forKey: .preset)
        try c.encode(overrides, forKey: .overrides)
    }

    public var effective: [String: KeyCombo] {
        var d = ShortcutRegistry.defaults(preset)
        for (id, s) in overrides {
            if s.isEmpty { d.removeValue(forKey: id) } else if let k = KeyCombo(s) { d[id] = k }
        }
        return d
    }

    public func combo(for id: String) -> KeyCombo? { effective[id] }

    public mutating func set(_ combo: KeyCombo?, for id: String) {
        let def = ShortcutRegistry.defaults(preset)[id]
        if combo == def { overrides.removeValue(forKey: id) } else { overrides[id] = combo?.stringValue ?? "" }
    }

    public func exportJSON() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func importJSON(_ data: Data) throws -> ShortcutBindings {
        try JSONDecoder().decode(ShortcutBindings.self, from: data)
    }
}
