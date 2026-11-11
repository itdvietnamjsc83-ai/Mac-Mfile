import Foundation

/// Thuộc tính tài liệu Word, Excel, PowerPoint (định dạng Office Open XML: .docx, .xlsx, .pptx…), như tab Chi tiết của Windows:
/// đọc, sửa (Tiêu đề, Chủ đề, Tác giả, Thẻ, Thể loại, Chú thích, Công ty, Người quản lý) và xóa thông tin cá nhân.
public enum OfficeMetadata {
    public static let extensions: Set<String> = ["docx", "docm", "dotx", "xlsx", "xlsm", "xltx", "pptx", "pptm", "potx", "ppsx"]

    public static func isOffice(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Một thuộc tính: thẻ XML, nằm ở tệp nào trong gói, có cho sửa không.
    public struct Field: Sendable, Equatable {
        public let id: String
        public let tag: String
        public let part: Part
        public let editable: Bool
        public var l10nKey: String { "office." + id }
    }
    public enum Part: String, Sendable { case core = "docProps/core.xml", app = "docProps/app.xml" }

    public static let fields: [Field] = [
        Field(id: "title", tag: "dc:title", part: .core, editable: true),
        Field(id: "subject", tag: "dc:subject", part: .core, editable: true),
        Field(id: "creator", tag: "dc:creator", part: .core, editable: true),
        Field(id: "keywords", tag: "cp:keywords", part: .core, editable: true),
        Field(id: "category", tag: "cp:category", part: .core, editable: true),
        Field(id: "description", tag: "dc:description", part: .core, editable: true),
        Field(id: "company", tag: "Company", part: .app, editable: true),
        Field(id: "manager", tag: "Manager", part: .app, editable: true),
        Field(id: "lastModifiedBy", tag: "cp:lastModifiedBy", part: .core, editable: false),
        Field(id: "revision", tag: "cp:revision", part: .core, editable: false),
        Field(id: "created", tag: "dcterms:created", part: .core, editable: false),
        Field(id: "modified", tag: "dcterms:modified", part: .core, editable: false),
        Field(id: "lastPrinted", tag: "cp:lastPrinted", part: .core, editable: false),
        Field(id: "totalTime", tag: "TotalTime", part: .app, editable: false),
        Field(id: "template", tag: "Template", part: .app, editable: false),
        Field(id: "application", tag: "Application", part: .app, editable: false),
    ]

    /// Các thuộc tính bị xóa khi chọn "Xóa thuộc tính và thông tin cá nhân". Giữ ngày tạo/sửa và tên ứng dụng.
    public static let personalIDs: Set<String> = ["title", "subject", "creator", "keywords", "category", "description",
                                                   "company", "manager", "lastModifiedBy", "lastPrinted", "template", "totalTime"]

    // MARK: XML (tách riêng để kiểm thử, không cần tệp)

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
    private static func pattern(_ tag: String) -> NSRegularExpression {
        let t = NSRegularExpression.escapedPattern(for: tag)
        return try! NSRegularExpression(pattern: "<\(t)(\\s[^>]*)?(/>|>([\\s\\S]*?)</\(t)>)")
    }

    public static func value(of tag: String, in xml: String) -> String? {
        let ns = xml as NSString
        guard let m = pattern(tag).firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let r = m.range(at: 3)
        return r.location == NSNotFound ? "" : unescape(ns.substring(with: r))
    }

    /// Đặt giá trị (nil = xóa hẳn thẻ). Thẻ chưa có thì chèn trước thẻ đóng của phần tử gốc.
    public static func setting(_ tag: String, to newValue: String?, in xml: String, rootClose: String) -> String {
        let ns = xml as NSString
        let re = pattern(tag)
        if let m = re.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let attrs = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1))
            let repl = newValue.map { "<\(tag)\(attrs)>\(escape($0))</\(tag)>" } ?? ""
            return ns.replacingCharacters(in: m.range, with: repl)
        }
        guard let v = newValue, !v.isEmpty, let close = xml.range(of: rootClose, options: .backwards) else { return xml }
        var out = xml
        out.insert(contentsOf: "<\(tag)>\(escape(v))</\(tag)>", at: close.lowerBound)
        return out
    }

    static func rootClose(_ part: Part) -> String { part == .core ? "</cp:coreProperties>" : "</Properties>" }

    /// Xóa thông tin cá nhân khỏi nội dung core.xml / app.xml.
    public static func cleaned(_ xml: String, part: Part) -> String {
        var out = xml
        for f in fields where f.part == part && personalIDs.contains(f.id) {
            out = setting(f.tag, to: f.id == "lastPrinted" ? nil : (f.id == "totalTime" ? "0" : ""), in: out, rootClose: rootClose(part))
        }
        if part == .core { out = setting("cp:revision", to: "1", in: out, rootClose: rootClose(part)) }
        return out
    }

    /// Bỏ mọi thuộc tính tùy chỉnh (docProps/custom.xml) nhưng giữ phần tử gốc để tệp vẫn hợp lệ.
    public static func cleanedCustom(_ xml: String) -> String {
        guard let open = xml.range(of: "<Properties"), let openEnd = xml[open.upperBound...].firstIndex(of: ">") else { return xml }
        if xml[..<xml.index(after: openEnd)].hasSuffix("/>") { return xml }
        return String(xml[..<xml.index(after: openEnd)]) + "</Properties>"
    }

    // MARK: Xóa sâu bên trong nội dung (như "Kiểm tra tài liệu" của Office)

    /// Tên thay cho người thật trong ghi chú, theo dõi thay đổi: "Tác giả" / "Author", như Office tự làm.
    public static var anonymousName: String { L10n.t("anonAuthor") }
    public static var anonymousInitials: String { L10n.t("anonInitials") }

    /// Đổi giá trị các thuộc tính `names` (ví dụ w:author="Nguyễn Văn A") thành `value`.
    static func replacingAttributes(_ names: [String], with value: String, in xml: String) -> String {
        guard !names.isEmpty else { return xml }
        let alt = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let re = try! NSRegularExpression(pattern: "(\\s(?:\(alt))=\")[^\"]*(\")")
        let tpl = "$1" + NSRegularExpression.escapedTemplate(for: escape(value)) + "$2"
        return re.stringByReplacingMatches(in: xml, range: NSRange(location: 0, length: (xml as NSString).length), withTemplate: tpl)
    }

    /// Bỏ hẳn các thuộc tính `names` (ví dụ w:date: giờ sửa, giờ ghi chú).
    static func removingAttributes(_ names: [String], in xml: String) -> String {
        let alt = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let re = try! NSRegularExpression(pattern: "\\s(?:\(alt))=\"[^\"]*\"")
        return re.stringByReplacingMatches(in: xml, range: NSRange(location: 0, length: (xml as NSString).length), withTemplate: "")
    }

    /// Bỏ các phần tử (rỗng hoặc có nội dung) theo tên thẻ.
    static func removingElements(_ tag: String, in xml: String) -> String {
        let t = NSRegularExpression.escapedPattern(for: tag)
        let re = try! NSRegularExpression(pattern: "<\(t)(\\s[^>]*)?(/>|>[\\s\\S]*?</\(t)>)")
        return re.stringByReplacingMatches(in: xml, range: NSRange(location: 0, length: (xml as NSString).length), withTemplate: "")
    }

    /// Đổi nội dung các phần tử <tag>…</tag> thành `value`; giữ nguyên nội dung bắt đầu bằng `keepingPrefix`
    /// (Excel ghi "tc={…}" làm khóa nối ghi chú cũ với bình luận mới, đổi đi sẽ hỏng liên kết).
    static func replacingElementText(_ tag: String, with value: String, in xml: String, keepingPrefix: String? = nil) -> String {
        let t = NSRegularExpression.escapedPattern(for: tag)
        let re = try! NSRegularExpression(pattern: "(<\(t)(?:\\s[^>]*)?>)([\\s\\S]*?)(</\(t)>)")
        let ns = xml as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let inner = ns.substring(with: m.range(at: 2))
            if let k = keepingPrefix, inner.hasPrefix(k) { out += ns.substring(with: m.range) }
            else { out += ns.substring(with: m.range(at: 1)) + escape(value) + ns.substring(with: m.range(at: 3)) }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Thêm thuộc tính vào thẻ mở đầu tiên `<tag` nếu thẻ đó chưa có.
    static func addingAttribute(_ attr: String, _ value: String, toFirst tag: String, in xml: String) -> String {
        guard let r = xml.range(of: "<" + tag), let end = xml[r.upperBound...].firstIndex(of: ">") else { return xml }
        let next = xml[r.upperBound]
        guard next == " " || next == ">" || next == "/" || next == "\n" || next == "\r" || next == "\t" else { return xml }
        let openTag = xml[r.lowerBound..<end]
        if openTag.contains(" " + attr + "=") { return xml }
        var out = xml
        out.insert(contentsOf: " \(attr)=\"\(value)\"", at: r.upperBound)
        return out
    }

    /// Word: bật "Xóa thông tin cá nhân khỏi thuộc tính tệp khi lưu" và "xóa ngày giờ" trong settings.xml,
    /// đặt đúng thứ tự lược đồ (sau w:writeProtection, w:view, w:zoom) để Word không báo lỗi tệp.
    static func wordSettingsWithPrivacy(_ xml: String) -> String {
        var out = xml
        let flags = ["w:removePersonalInformation", "w:removeDateAndTime"].filter { !out.contains("<" + $0) }
        guard !flags.isEmpty, let open = out.range(of: "<w:settings"), let openEnd = out[open.upperBound...].firstIndex(of: ">") else { return xml }
        var insertAt = out.index(after: openEnd)
        for prev in ["w:writeProtection", "w:view", "w:zoom"] {
            let t = NSRegularExpression.escapedPattern(for: prev)
            let re = try! NSRegularExpression(pattern: "<\(t)(\\s[^>]*)?(/>|>[\\s\\S]*?</\(t)>)")
            if let m = re.firstMatch(in: out, range: NSRange(location: 0, length: (out as NSString).length)),
               let r = Range(m.range, in: out), r.upperBound > insertAt { insertAt = r.upperBound }
        }
        out.insert(contentsOf: flags.map { "<\($0)/>" }.joined(), at: insertAt)
        return out
    }

    /// Làm sạch một phần XML trong gói theo đường dẫn của nó (word/…, xl/…, ppt/…).
    public static func deepCleaned(_ xml: String, part: String) -> String {
        let name = anonymousName, ini = anonymousInitials
        let lower = part.lowercased()
        guard lower.hasSuffix(".xml") else { return xml }
        var x = xml
        if lower.hasPrefix("word/") {
            // Ghi chú, theo dõi thay đổi (w:ins, w:del, w:rPrChange…), danh sách người dùng (people.xml).
            x = replacingAttributes(["w:author", "w15:author"], with: name, in: x)
            x = replacingAttributes(["w:initials"], with: ini, in: x)
            x = removingAttributes(["w:date", "w16du:dateUtc"], in: x)
            x = removingElements("w15:presenceInfo", in: x)
            if lower == "word/settings.xml" { x = wordSettingsWithPrivacy(x) }
        } else if lower.hasPrefix("xl/") {
            if lower.hasPrefix("xl/comments") { x = replacingElementText("author", with: name, in: x, keepingPrefix: "tc=") }
            if lower.hasPrefix("xl/persons/") {
                x = replacingAttributes(["displayName"], with: name, in: x)
                x = replacingAttributes(["userId"], with: "", in: x)
                x = replacingAttributes(["providerId"], with: "None", in: x)
            }
            if lower.hasPrefix("xl/revisions/") { x = replacingAttributes(["userName"], with: name, in: x) }
            if lower == "xl/workbook.xml" {
                x = replacingAttributes(["userName"], with: name, in: x)
                x = addingAttribute("filterPrivacy", "1", toFirst: "workbookPr", in: x)
            }
        } else if lower.hasPrefix("ppt/") {
            if lower == "ppt/commentauthors.xml" || lower == "ppt/authors.xml" {
                x = replacingAttributes(["name"], with: name, in: x)
                x = replacingAttributes(["initials"], with: ini, in: x)
                x = replacingAttributes(["userId"], with: "", in: x)
                x = replacingAttributes(["providerId"], with: "None", in: x)
            }
            if lower == "ppt/presentation.xml" { x = addingAttribute("removePersonalInfoOnSave", "1", toFirst: "p:presentation", in: x) }
        }
        return x
    }

    #if os(macOS)
    // MARK: Tệp

    private static func unzipPart(_ path: String, _ part: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", path, part]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Đọc các thuộc tính có trong tệp (id → giá trị).
    public static func read(_ path: String) -> [String: String] {
        var r: [String: String] = [:]
        let core = unzipPart(path, Part.core.rawValue), app = unzipPart(path, Part.app.rawValue)
        for f in fields {
            guard let xml = f.part == .core ? core : app, let v = value(of: f.tag, in: xml) else { continue }
            r[f.id] = v
        }
        return r
    }

    public enum OfficeError: Error { case unpack, pack }

    /// Giải nén gói vào thư mục tạm, cho `edit` sửa, rồi nén lại thay tệp gốc (giữ ngày tạo).
    private static func rewrite(_ path: String, to dst: String? = nil, _ edit: (String) throws -> Void) throws {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory() + "mfile-office-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        guard ArchiveTool.run("/usr/bin/unzip", ["-q", path, "-d", tmp]).0 else { throw OfficeError.unpack }
        try edit(tmp)
        let out = tmp + ".zip"
        defer { try? fm.removeItem(atPath: out) }
        // [Content_Types].xml đứng đầu gói như Office ghi.
        // Liệt kê tên tệp rõ ràng và tắt ký tự đại diện (-nw) vì "[Content_Types]" chứa dấu ngoặc vuông.
        var files: [String] = []
        for rel in (fm.subpaths(atPath: tmp) ?? []) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: tmp + "/" + rel, isDirectory: &isDir), !isDir.boolValue, rel != "[Content_Types].xml" { files.append(rel) }
        }
        guard ArchiveTool.run("/usr/bin/zip", ["-X", "-q", "-nw", out, "[Content_Types].xml"], cwd: tmp).0,
              ArchiveTool.run("/usr/bin/zip", ["-X", "-q", "-nw", out] + files.sorted(), cwd: tmp).0 else { throw OfficeError.pack }
        let target = dst ?? path
        let created = (try? fm.attributesOfItem(atPath: path))?[.creationDate]
        if fm.fileExists(atPath: target) {
            _ = try fm.replaceItemAt(URL(fileURLWithPath: target), withItemAt: URL(fileURLWithPath: out))
        } else {
            try fm.moveItem(atPath: out, toPath: target)
        }
        if dst == nil, let c = created { try? fm.setAttributes([.creationDate: c], ofItemAtPath: target) }
    }

    private static func editPart(_ dir: String, _ part: String, _ f: (String) -> String) throws {
        let p = dir + "/" + part
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return }
        try f(s).write(toFile: p, atomically: true, encoding: .utf8)
    }

    /// Ghi các thuộc tính đã sửa (id → giá trị mới; chuỗi rỗng = để trống).
    public static func write(_ path: String, _ changes: [String: String]) throws {
        guard !changes.isEmpty else { return }
        try rewrite(path) { dir in
            for part in [Part.core, .app] {
                try editPart(dir, part.rawValue) { xml in
                    var x = xml
                    for f in fields where f.part == part && f.editable {
                        if let v = changes[f.id] { x = setting(f.tag, to: v, in: x, rootClose: rootClose(part)) }
                    }
                    return x
                }
            }
        }
    }

    /// Xóa thông tin cá nhân; `dst` khác nil thì ghi ra bản sao.
    public static func clean(_ path: String, to dst: String? = nil) throws {
        try rewrite(path, to: dst) { dir in
            try editPart(dir, Part.core.rawValue) { cleaned($0, part: .core) }
            try editPart(dir, Part.app.rawValue) { cleaned($0, part: .app) }
            try editPart(dir, "docProps/custom.xml") { cleanedCustom($0) }
            for rel in FileManager.default.subpaths(atPath: dir) ?? [] where rel.lowercased().hasSuffix(".xml") && !rel.hasPrefix("docProps/") {
                try editPart(dir, rel) { deepCleaned($0, part: rel) }
            }
        }
    }
    #endif
}
