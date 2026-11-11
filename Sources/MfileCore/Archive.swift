import Foundation

/// Nhận diện tệp nén và đặt tên thư mục giải nén kiểu Windows (Mục 5.3: menu chuột phải của tệp nén).
public enum ArchiveSupport {
    /// Đuôi nhiều phần phải xét trước đuôi một phần.
    static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz"]
    static let extensions = ["zip", "tar", "tgz", "tbz", "tbz2", "txz", "gz", "bz2", "xz", "7z", "rar"]

    public static func isArchive(_ name: String) -> Bool {
        archiveExtension(of: name) != nil
    }

    static func archiveExtension(of name: String) -> String? {
        let lower = name.lowercased()
        for e in compoundExtensions where lower.hasSuffix("." + e) { return e }
        for e in extensions where lower.hasSuffix("." + e) { return e }
        return nil
    }

    /// "Hồ sơ dự thầu.zip" → "Hồ sơ dự thầu", "data.tar.gz" → "data".
    public static func baseName(of name: String) -> String {
        guard let e = archiveExtension(of: name) else { return name }
        let base = String(name.dropLast(e.count + 1))
        return base.isEmpty ? name : base
    }
}
