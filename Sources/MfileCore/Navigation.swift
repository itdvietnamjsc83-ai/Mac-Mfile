import Foundation

/// Lịch sử Quay lại / Tiến của một tab.
public struct NavigationHistory: Sendable {
    public private(set) var current: String
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    public init(start: String) { current = start }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public mutating func visit(_ path: String) {
        guard path != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = path
    }

    @discardableResult public mutating func back() -> String? {
        guard let p = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = p
        return p
    }

    @discardableResult public mutating func forward() -> String? {
        guard let p = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = p
        return p
    }

    /// Thư mục cha; từ ổ gốc đi lên trang Máy Mac này (như C:\ lên This PC); nil ở các trang đặc biệt.
    public static func parent(of path: String) -> String? {
        if SpecialLocation.isSpecial(path) { return nil }
        if path == "/" { return SpecialLocation.thisMac }
        let p = (path as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
    }
}

/// Trang không phải thư mục thật: Trang chủ và Máy Mac này (FR-08, Mục 5.1).
public enum SpecialLocation {
    public static let home = "mfile:home"
    public static let thisMac = "mfile:thismac"

    public static func isSpecial(_ path: String) -> Bool { path.hasPrefix("mfile:") }

    public static func title(_ path: String, lang: AppLanguage = L10n.current) -> String? {
        switch path {
        case home: return L10n.t("home", lang)
        case thisMac: return L10n.t("thisMac", lang)
        default: return nil
        }
    }

    /// Gõ "Trang chủ", "Home", "Máy Mac này", "This Mac" vào thanh địa chỉ.
    public static func fromTyped(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        for p in [home, thisMac] {
            if AppLanguage.allCases.contains(where: { L10n.t(p == home ? "home" : "thisMac", $0).lowercased() == t }) || t == p { return p }
        }
        return nil
    }
}

/// Breadcrumb hiển thị theo ngôn ngữ, đường dẫn thật giữ nguyên khi sao chép (Mục 5.13).
public struct Crumb: Equatable, Sendable {
    public let title: String
    public let path: String
}

public enum Breadcrumb {
    static let known: [String: String] = [
        "Desktop": "desktop", "Downloads": "downloads", "Documents": "documents",
        "Pictures": "pictures", "Music": "music", "Movies": "videos"
    ]

    public static var rootVolumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Macintosh HD"
    }

    public static func crumbs(for path: String, home: String = NSHomeDirectory(), lang: AppLanguage = L10n.current) -> [Crumb] {
        if let t = SpecialLocation.title(path, lang: lang), path == SpecialLocation.home { return [Crumb(title: t, path: path)] }
        var result = [Crumb(title: L10n.t("thisMac", lang), path: SpecialLocation.thisMac)]
        if path == SpecialLocation.thisMac { return result }
        if path == "/" { return result + [Crumb(title: rootVolumeName, path: "/")] }
        var base = ""
        var rest = path
        if path == home || path.hasPrefix(home + "/") {
            base = home
            rest = String(path.dropFirst(home.count))
            result.append(Crumb(title: (home as NSString).lastPathComponent, path: home))
        }
        var current = base
        for comp in rest.split(separator: "/") {
            current += "/" + comp
            let name = String(comp)
            var title = name
            if base == home, current == home + "/" + name, let key = known[name] {
                title = L10n.t(key, lang)
            }
            result.append(Crumb(title: title, path: current))
        }
        return result
    }
}
