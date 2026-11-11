import Foundation

/// Kết quả phân tích chữ người dùng gõ hoặc dán vào thanh địa chỉ (Mục 5.13).
public enum PathInput: Equatable {
    case local(String)
    case remote(String)
    case empty
}

public enum PathParser {
    /// Chuẩn hóa đường dẫn dán từ Finder, Terminal, Windows-style "Copy as path", file:// URL.
    public static func parse(_ raw: String, home: String = NSHomeDirectory()) -> PathInput {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nhiều dòng: chỉ lấy dòng đầu.
        if let nl = s.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            s = String(s[..<nl]).trimmingCharacters(in: .whitespaces)
        }
        if s.isEmpty { return .empty }
        // Bỏ ngoặc kép hoặc ngoặc đơn bao quanh.
        if s.count >= 2, let f = s.first, let l = s.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let lower = s.lowercased()
        if lower.hasPrefix("smb://") || lower.hasPrefix("afp://") || lower.hasPrefix("nfs://") {
            return .remote(s.precomposedStringWithCanonicalMapping)
        }
        if lower.hasPrefix("file://") {
            if let url = URL(string: s), url.isFileURL {
                s = url.path
            } else {
                s = String(s.dropFirst("file://".count)).removingPercentEncoding ?? s
            }
        } else {
            s = unescapeShell(s)
        }
        if s == "~" { s = home } else if s.hasPrefix("~/") { s = home + String(s.dropFirst(1)) }
        // Bỏ dấu / thừa ở cuối (trừ thư mục gốc).
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return .local(s.precomposedStringWithCanonicalMapping)
    }

    /// Terminal chèn dấu \ trước dấu cách và ký tự đặc biệt: "Hợp\ đồng" → "Hợp đồng".
    static func unescapeShell(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var escaping = false
        for c in s {
            if escaping { out.append(c); escaping = false }
            else if c == "\\" { escaping = true }
            else { out.append(c) }
        }
        if escaping { out.append("\\") }
        return out
    }

    /// Sao chép đường dẫn của nhiều mục: mỗi đường dẫn một dòng, có ngoặc kép như Windows nếu bật.
    public static func copyText(for paths: [String], quoted: Bool = true) -> String {
        paths.map { quoted ? "\"\($0)\"" : $0 }.joined(separator: "\n")
    }
}
