import Foundation

/// Một mục trong thư mục đang xem.
public struct FileItem: Equatable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date
    public let isHidden: Bool

    public init(path: String, name: String, isDirectory: Bool, size: Int64, modified: Date, isHidden: Bool = false) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.isHidden = isHidden
    }

    public var fileExtension: String {
        guard !isDirectory, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    /// Cột Loại kiểu Windows: "Thư mục tệp", "Tệp PDF".
    public func typeDescription(lang: AppLanguage = L10n.current) -> String {
        if isDirectory { return L10n.t("typeFolder", lang) }
        let ext = fileExtension.uppercased()
        return L10n.f("typeFile", ext.isEmpty ? "" : ext, lang: lang).trimmingCharacters(in: .whitespaces)
    }
}

public enum SortKey: String, Sendable { case name, modified, type, size }

public enum FileSorting {
    /// Thư mục luôn đứng trước tệp; tên so theo quy tắc tiếng Việt, số theo giá trị (a2 trước a10).
    public static func sort(_ items: [FileItem], by key: SortKey = .name, ascending: Bool = true) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let order: ComparisonResult
            switch key {
            case .name: order = compareNames(a.name, b.name)
            case .modified: order = a.modified == b.modified ? compareNames(a.name, b.name) : (a.modified < b.modified ? .orderedAscending : .orderedDescending)
            case .size: order = a.size == b.size ? compareNames(a.name, b.name) : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .type:
                let t = compareNames(a.fileExtension, b.fileExtension)
                order = t == .orderedSame ? compareNames(a.name, b.name) : t
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    public static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        let vi = Locale(identifier: "vi_VN")
        return a.compare(b, options: [.caseInsensitive, .numeric, .widthInsensitive], range: nil, locale: vi)
    }
}

/// Đọc nội dung thư mục từ ổ đĩa.
public enum DirectoryReader {
    public static func list(_ path: String, showHidden: Bool = false, fileManager: FileManager = .default) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isPackageKey]
        let urls = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.map { item(for: $0) }
    }

    /// Một mục bất kỳ theo đường dẫn (dùng cho Trang chủ, ngăn chi tiết).
    public static func item(at path: String) -> FileItem? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return item(for: URL(fileURLWithPath: path))
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isPackageKey]

    private static func item(for u: URL) -> FileItem {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isPackage = v?.isPackage ?? false
            return FileItem(
                path: u.path,
                name: u.lastPathComponent.precomposedStringWithCanonicalMapping,
                isDirectory: (v?.isDirectory ?? false) && !isPackage,
                size: Int64(v?.fileSize ?? 0),
                modified: v?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                isHidden: v?.isHidden ?? false
            )
    }
}
