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

    /// Thư mục cha; nil khi đã ở gốc.
    public static func parent(of path: String) -> String? {
        guard path != "/" else { return nil }
        let p = (path as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
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

    public static func crumbs(for path: String, home: String = NSHomeDirectory(), lang: AppLanguage = L10n.current) -> [Crumb] {
        var result = [Crumb(title: L10n.t("thisMac", lang), path: "/")]
        if path == "/" { return result }
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
