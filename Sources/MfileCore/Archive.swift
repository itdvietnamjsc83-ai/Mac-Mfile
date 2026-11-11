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

/// Kiểu mã hóa ZIP khi đặt mật khẩu: AES-256 (an toàn) hoặc ZipCrypto (mở được bằng trình giải nén có sẵn của Windows).
public enum ZipEncryption: String, CaseIterable, Sendable { case aes256, zipCrypto }

/// Đánh giá độ mạnh mật khẩu cho thanh "Độ mạnh" (0 yếu, 1 trung bình, 2 mạnh).
public enum PasswordStrength {
    public static func score(_ p: String) -> Int {
        var kinds = 0
        if p.rangeOfCharacter(from: .lowercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .uppercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .decimalDigits) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { kinds += 1 }
        if p.count >= 12 && kinds >= 3 { return 2 }
        if p.count >= 8 && kinds >= 2 { return 1 }
        return 0
    }
}

#if os(macOS)
/// Gọi công cụ nén có sẵn của macOS (bsdtar, zip, unzip). Chạy đồng bộ: gọi từ luồng nền.
public enum ArchiveTool {
    public struct Outcome: Sendable {
        public let ok: Bool
        public let message: String
        /// Kiểu mã hóa thực sự đã dùng (có thể lùi về ZipCrypto nếu máy không hỗ trợ AES).
        public let encryption: ZipEncryption?
    }

    @discardableResult
    public static func run(_ tool: String, _ args: [String], cwd: String? = nil) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let msg = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (p.terminationStatus == 0, msg)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Nén các mục `names` (nằm trong `dir`) thành ZIP, có thể đặt mật khẩu.
    public static func createZip(names: [String], in dir: String, dest: String, password: String?, encryption: ZipEncryption = .aes256) -> Outcome {
        guard let pw = password, !pw.isEmpty else {
            let r = run("/usr/bin/zip", ["-r", "-y", "-q", dest] + names, cwd: dir)
            return Outcome(ok: r.0, message: r.1, encryption: nil)
        }
        if encryption == .aes256 {
            let r = run("/usr/bin/tar", ["--format", "zip", "--options", "zip:encryption=aes256", "--passphrase", pw, "-cf", dest] + names, cwd: dir)
            if r.0 { return Outcome(ok: true, message: "", encryption: .aes256) }
            try? FileManager.default.removeItem(atPath: dest)
        }
        let r = run("/usr/bin/zip", ["-r", "-y", "-q", "-P", pw, dest] + names, cwd: dir)
        return Outcome(ok: r.0, message: r.1, encryption: r.0 ? .zipCrypto : nil)
    }

    /// Lỗi do tệp nén có mật khẩu (thiếu hoặc sai).
    public static func needsPassword(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["passphrase", "password", "encrypt", "incorrect"].contains { m.contains($0) }
    }

    /// Giải nén, không ghi đè tệp đã có. Có mật khẩu thì thử bsdtar rồi unzip.
    public static func extract(_ archive: String, to dest: String, password: String? = nil) -> (Bool, String) {
        var args = ["-xkf", archive, "-C", dest]
        if let pw = password { args = ["--passphrase", pw] + args }
        let r = run("/usr/bin/tar", args)
        if r.0 || password == nil || !archive.lowercased().hasSuffix(".zip") { return r }
        let u = run("/usr/bin/unzip", ["-n", "-q", "-P", password!, archive, "-d", dest])
        return u.0 ? u : r
    }

    /// Kiểm tra tệp nén (đọc toàn bộ dữ liệu, có mật khẩu nếu cần).
    public static func test(_ archive: String, password: String? = nil) -> (Bool, String) {
        if archive.lowercased().hasSuffix(".zip") {
            return run("/usr/bin/unzip", ["-tq"] + (password.map { ["-P", $0] } ?? []) + [archive])
        }
        return run("/usr/bin/tar", (password.map { ["--passphrase", $0] } ?? []) + ["-tf", archive])
    }
}
#endif
