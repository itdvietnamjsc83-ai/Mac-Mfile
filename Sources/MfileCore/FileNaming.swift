import Foundation

/// Đặt tên khi sao chép/trùng tên theo kiểu Windows 11 (Mục 5.10).
public enum FileNaming {
    /// Dán vào chính thư mục nguồn: "Báo cáo - Bản sao.docx", rồi "Báo cáo - Bản sao (2).docx".
    public static func copyName(_ name: String, lang: AppLanguage = L10n.current, exists: (String) -> Bool) -> String {
        let (base, ext) = split(name)
        let suffix = lang == .vi ? " - Bản sao" : " - Copy"
        var candidate = base + suffix + ext
        var n = 2
        while exists(candidate) {
            candidate = base + suffix + " (\(n))" + ext
            n += 1
        }
        return candidate
    }

    /// "Giữ cả hai": "Báo cáo (2).docx".
    public static func keepBothName(_ name: String, exists: (String) -> Bool) -> String {
        let (base, ext) = split(name)
        var n = 2
        var candidate = name
        while exists(candidate) {
            candidate = base + " (\(n))" + ext
            n += 1
        }
        return candidate
    }

    static func split(_ name: String) -> (String, String) {
        let ext = (name as NSString).pathExtension
        if ext.isEmpty || name.hasPrefix(".") && !name.dropFirst().contains(".") { return (name, "") }
        return ((name as NSString).deletingPathExtension, "." + ext)
    }
}

/// Ước lượng thời gian còn lại và tốc độ như hộp tiến trình của Windows.
public struct TransferStats: Sendable {
    public var totalBytes: Int64 = 0
    public var doneBytes: Int64 = 0
    public var totalItems = 0
    public var doneItems = 0
    public let started: Date

    public init(started: Date = Date()) { self.started = started }

    public var fraction: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : (totalItems > 0 ? Double(doneItems) / Double(totalItems) : 0) }

    public func bytesPerSecond(now: Date = Date()) -> Double {
        let t = now.timeIntervalSince(started)
        return t > 0.2 ? Double(doneBytes) / t : 0
    }

    public func secondsRemaining(now: Date = Date()) -> Double? {
        let s = bytesPerSecond(now: now)
        guard s > 0 else { return nil }
        return Double(totalBytes - doneBytes) / s
    }

    /// "Khoảng 2 phút" / "About 2 minutes".
    public static func describe(seconds: Double, lang: AppLanguage = L10n.current) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return L10n.f("aboutSeconds", max(1, s), lang: lang) }
        if s < 3600 { return L10n.f("aboutMinutes", (s + 30) / 60, lang: lang) }
        return L10n.f("aboutHours", s / 3600, (s % 3600) / 60, lang: lang)
    }
}
