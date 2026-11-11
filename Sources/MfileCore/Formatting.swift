import Foundation

/// Định dạng dung lượng và ngày theo ngôn ngữ đang chọn (Mục 3: "4,2 MB", dd/MM/yyyy).
public enum Formatting {
    /// Kích cỡ kiểu Windows: dưới 1 KB hiện byte, tới 1 MB hiện KB làm tròn lên, sau đó 1 chữ số thập phân.
    public static func size(_ bytes: Int64, lang: AppLanguage = L10n.current) -> String {
        let sep = lang == .vi ? "," : "."
        if bytes < 1024 {
            return lang == .vi ? "\(bytes) byte" : "\(bytes) bytes"
        }
        if bytes < 1024 * 1024 {
            let kb = (bytes + 1023) / 1024
            return "\(group(kb, lang: lang)) KB"
        }
        let units = ["MB", "GB", "TB"]
        var value = Double(bytes) / (1024 * 1024)
        var i = 0
        while value >= 1024 && i < units.count - 1 { value /= 1024; i += 1 }
        let rounded = (value * 10).rounded() / 10
        var text = String(format: "%.1f", rounded)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text.replacingOccurrences(of: ".", with: sep) + " " + units[i]
    }

    /// Nhóm hàng nghìn: vi dùng dấu chấm (1.234), en dùng dấu phẩy (1,234).
    public static func group(_ n: Int64, lang: AppLanguage = L10n.current) -> String {
        let sep: Character = lang == .vi ? "." : ","
        let digits = String(abs(n))
        var out = ""
        for (i, c) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(sep) }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    public static func date(_ d: Date, lang: AppLanguage = L10n.current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = lang == .vi ? "dd/MM/yyyy HH:mm" : "M/d/yyyy h:mm a"
        return f.string(from: d)
    }
}
