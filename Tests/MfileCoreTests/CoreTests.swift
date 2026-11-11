import XCTest
@testable import MfileCore

final class FormattingTests: XCTestCase {
    func testSizeVietnamese() {
        XCTAssertEqual(Formatting.size(512, lang: .vi), "512 byte")
        XCTAssertEqual(Formatting.size(1024, lang: .vi), "1 KB")
        XCTAssertEqual(Formatting.size(1025, lang: .vi), "2 KB")
        XCTAssertEqual(Formatting.size(865_280, lang: .vi), "845 KB")
        XCTAssertEqual(Formatting.size(4_404_019, lang: .vi), "4,2 MB")
        XCTAssertEqual(Formatting.size(5 * 1024 * 1024 * 1024, lang: .vi), "5 GB")
    }

    func testSizeEnglish() {
        XCTAssertEqual(Formatting.size(4_404_019, lang: .en), "4.2 MB")
        XCTAssertEqual(Formatting.size(10, lang: .en), "10 bytes")
    }

    func testGrouping() {
        XCTAssertEqual(Formatting.group(1_234_567, lang: .vi), "1.234.567")
        XCTAssertEqual(Formatting.group(1_234_567, lang: .en), "1,234,567")
        XCTAssertEqual(Formatting.group(12, lang: .vi), "12")
    }

    func testDate() {
        let utc = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 1_794_384_000) // 2026-11-11 08:00 UTC
        XCTAssertEqual(Formatting.date(d, lang: .vi, timeZone: utc), "11/11/2026 08:00")
        XCTAssertEqual(Formatting.date(d, lang: .en, timeZone: utc), "11/11/2026 8:00 AM")
    }
}

final class PathParserTests: XCTestCase {
    let home = "/Users/dung"

    func testPlainAndQuoted() {
        XCTAssertEqual(PathParser.parse("/Users/dung/Documents", home: home), .local("/Users/dung/Documents"))
        XCTAssertEqual(PathParser.parse("  \"/Users/dung/Documents/Hợp đồng\"  \n", home: home), .local("/Users/dung/Documents/Hợp đồng"))
        XCTAssertEqual(PathParser.parse("'/tmp/a b'", home: home), .local("/tmp/a b"))
    }

    func testTildeAndTrailingSlash() {
        XCTAssertEqual(PathParser.parse("~", home: home), .local(home))
        XCTAssertEqual(PathParser.parse("~/Downloads/", home: home), .local("/Users/dung/Downloads"))
        XCTAssertEqual(PathParser.parse("/", home: home), .local("/"))
    }

    func testTerminalEscapes() {
        XCTAssertEqual(PathParser.parse("/Users/dung/Hợp\\ đồng\\ 2026", home: home), .local("/Users/dung/Hợp đồng 2026"))
    }

    func testFileURL() {
        XCTAssertEqual(PathParser.parse("file:///Users/dung/H%E1%BB%A3p%20%C4%91%E1%BB%93ng", home: home), .local("/Users/dung/Hợp đồng"))
    }

    func testRemoteAndEmpty() {
        XCTAssertEqual(PathParser.parse("smb://nas.local/chung", home: home), .remote("smb://nas.local/chung"))
        XCTAssertEqual(PathParser.parse("   ", home: home), .empty)
    }

    func testNFDBecomesNFC() {
        let nfd = "/tmp/Ha\u{0300}"  // "Hà" dạng tách dấu
        XCTAssertEqual(PathParser.parse(nfd, home: home), .local("/tmp/H\u{00E0}"))
    }

    func testMultiLineTakesFirst() {
        XCTAssertEqual(PathParser.parse("\"/a/b\"\n\"/c/d\"", home: home), .local("/a/b"))
    }

    func testCopyText() {
        XCTAssertEqual(PathParser.copyText(for: ["/a b", "/c"]), "\"/a b\"\n\"/c\"")
        XCTAssertEqual(PathParser.copyText(for: ["/a b"], quoted: false), "/a b")
    }
}

final class SortingTests: XCTestCase {
    let d = Date(timeIntervalSince1970: 0)

    func item(_ n: String, dir: Bool = false, size: Int64 = 0) -> FileItem {
        FileItem(path: "/x/" + n, name: n, isDirectory: dir, size: size, modified: d)
    }

    func testFoldersFirstAndNumeric() {
        let items = [item("b10.txt"), item("Zeta", dir: true), item("b2.txt"), item("alpha", dir: true)]
        XCTAssertEqual(FileSorting.sort(items).map(\.name), ["alpha", "Zeta", "b2.txt", "b10.txt"])
    }

    func testDescendingKeepsFoldersFirst() {
        let items = [item("a.txt"), item("B", dir: true), item("c.txt")]
        XCTAssertEqual(FileSorting.sort(items, ascending: false).map(\.name), ["B", "c.txt", "a.txt"])
    }

    func testSizeSort() {
        let items = [item("big", size: 900), item("small", size: 10)]
        XCTAssertEqual(FileSorting.sort(items, by: .size).map(\.name), ["small", "big"])
    }

    func testTypeDescription() {
        XCTAssertEqual(item("a.pdf").typeDescription(lang: .vi), "Tệp PDF")
        XCTAssertEqual(item("a.pdf").typeDescription(lang: .en), "PDF File")
        XCTAssertEqual(item("Docs", dir: true).typeDescription(lang: .vi), "Thư mục tệp")
    }
}

final class NavigationTests: XCTestCase {
    func testBackForward() {
        var h = NavigationHistory(start: "/a")
        h.visit("/a/b"); h.visit("/a/b/c")
        XCTAssertEqual(h.back(), "/a/b")
        XCTAssertEqual(h.back(), "/a")
        XCTAssertNil(h.back())
        XCTAssertEqual(h.forward(), "/a/b")
        h.visit("/z")
        XCTAssertFalse(h.canGoForward)
    }

    func testParent() {
        XCTAssertEqual(NavigationHistory.parent(of: "/a/b"), "/a")
        XCTAssertEqual(NavigationHistory.parent(of: "/a"), "/")
        XCTAssertEqual(NavigationHistory.parent(of: "/"), SpecialLocation.thisMac)
        XCTAssertNil(NavigationHistory.parent(of: SpecialLocation.thisMac))
        XCTAssertNil(NavigationHistory.parent(of: SpecialLocation.home))
    }

    func testBreadcrumbLocalized() {
        let c = Breadcrumb.crumbs(for: "/Users/dung/Documents/Hợp đồng", home: "/Users/dung", lang: .vi)
        XCTAssertEqual(c.map(\.title), ["Máy Mac này", "dung", "Tài liệu", "Hợp đồng"])
        XCTAssertEqual(c.last?.path, "/Users/dung/Documents/Hợp đồng")
        let e = Breadcrumb.crumbs(for: "/Volumes/USB", home: "/Users/dung", lang: .en)
        XCTAssertEqual(e.map(\.title), ["This Mac", "Volumes", "USB"])
        XCTAssertEqual(e.first?.path, SpecialLocation.thisMac)
        XCTAssertEqual(Breadcrumb.crumbs(for: SpecialLocation.home, lang: .vi).map(\.title), ["Trang chủ"])
        XCTAssertEqual(Breadcrumb.crumbs(for: "/", lang: .en).count, 2)
        XCTAssertEqual(SpecialLocation.fromTyped("máy mac này"), SpecialLocation.thisMac)
        XCTAssertEqual(SpecialLocation.fromTyped("Home"), SpecialLocation.home)
        XCTAssertNil(SpecialLocation.fromTyped("/Users"))
    }
}

final class L10nTests: XCTestCase {
    func testEveryKeyHasBothLanguages() {
        for key in L10n.allKeys {
            XCTAssertFalse(L10n.t(key, .vi).isEmpty, key)
            XCTAssertFalse(L10n.t(key, .en).isEmpty, key)
        }
    }

    func testFormat() {
        XCTAssertEqual(L10n.f("items", 128, lang: .vi), "128 mục")
        XCTAssertEqual(L10n.f("items", 128, lang: .en), "128 items")
    }

    func testSystemDefault() {
        XCTAssertEqual(AppLanguage.systemDefault(preferred: ["vi-VN"]), .vi)
        XCTAssertEqual(AppLanguage.systemDefault(preferred: ["en-US"]), .en)
    }
}

final class ArchiveTests: XCTestCase {
    func testRecognize() {
        XCTAssertTrue(ArchiveSupport.isArchive("Hồ sơ.ZIP"))
        XCTAssertTrue(ArchiveSupport.isArchive("a.tar.gz"))
        XCTAssertTrue(ArchiveSupport.isArchive("b.7z"))
        XCTAssertFalse(ArchiveSupport.isArchive("Báo cáo.docx"))
        XCTAssertFalse(ArchiveSupport.isArchive("zip"))
    }

    func testBaseName() {
        XCTAssertEqual(ArchiveSupport.baseName(of: "Hồ sơ dự thầu.zip"), "Hồ sơ dự thầu")
        XCTAssertEqual(ArchiveSupport.baseName(of: "data.tar.gz"), "data")
        XCTAssertEqual(ArchiveSupport.baseName(of: "x.rar"), "x")
        XCTAssertEqual(ArchiveSupport.baseName(of: "note.txt"), "note.txt")
    }
}

final class ViewModeTests: XCTestCase {
    func testEightModesWithTitles() {
        XCTAssertEqual(ViewMode.allCases.count, 8)
        for m in ViewMode.allCases {
            XCTAssertNotEqual(L10n.t(m.titleKey, .vi), m.titleKey, m.rawValue)
            XCTAssertNotEqual(L10n.t(m.titleKey, .en), m.titleKey, m.rawValue)
        }
    }

    func testPerFolderPreference() {
        var p = ViewPreferences()
        XCTAssertEqual(p.mode(for: "/a"), .details)
        p.set(.largeIcons, for: "/a")
        XCTAssertEqual(p.mode(for: "/a"), .largeIcons)
        XCTAssertEqual(p.mode(for: "/b"), .details)
    }

    func testListFlowsInColumns() {
        XCTAssertTrue(ViewMode.list.flowsInColumns)
        XCTAssertFalse(ViewMode.smallIcons.flowsInColumns)
        XCTAssertEqual(ViewMode.details.itemSize(compact: true).height, 24)
    }
}

#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers

final class MetadataCleanerTests: XCTestCase {
    func testRemovesGPSAndExif() throws {
        let dir = NSTemporaryDirectory() + "mfile-meta-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let src = dir + "/anh.jpg"
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let img = ctx.makeImage()!
        let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: src) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 21.03, kCGImagePropertyGPSLatitudeRef as String: "N"],
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFMake as String: "MayAnh", kCGImagePropertyTIFFArtist as String: "Dung"],
        ]
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        XCTAssertTrue(MetadataCleaner.imageMetadataGroups(src).contains(kCGImagePropertyGPSDictionary as String))

        let copy = dir + "/" + MetadataCleaner.copyName(for: src, lang: .vi)
        XCTAssertTrue(copy.hasSuffix("anh - Bản sao.jpg"))
        try MetadataCleaner.clean(src, to: copy)
        XCTAssertFalse(MetadataCleaner.imageMetadataGroups(copy).contains(kCGImagePropertyGPSDictionary as String))

        try MetadataCleaner.cleanInPlace(src)
        let left = MetadataCleaner.imageMetadataGroups(src)
        XCTAssertFalse(left.contains(kCGImagePropertyGPSDictionary as String))
        XCTAssertTrue(MetadataCleaner.canClean("/x/a.PDF"))
        XCTAssertFalse(MetadataCleaner.canClean("/x/a.txt"))
    }
}
#endif

final class FileNamingTests: XCTestCase {
    func testCopyNameLikeWindows() {
        var existing: Set<String> = ["Báo cáo.docx"]
        let a = FileNaming.copyName("Báo cáo.docx", lang: .vi) { existing.contains($0) }
        XCTAssertEqual(a, "Báo cáo - Bản sao.docx")
        existing.insert(a)
        XCTAssertEqual(FileNaming.copyName("Báo cáo.docx", lang: .vi) { existing.contains($0) }, "Báo cáo - Bản sao (2).docx")
        XCTAssertEqual(FileNaming.copyName("Thư mục", lang: .en) { _ in false }, "Thư mục - Copy")
    }

    func testKeepBoth() {
        let existing: Set<String> = ["a.txt", "a (2).txt"]
        XCTAssertEqual(FileNaming.keepBothName("a.txt") { existing.contains($0) }, "a (3).txt")
        XCTAssertEqual(FileNaming.keepBothName(".env") { $0 == ".env" }, ".env (2)")
    }

    func testStats() {
        var s = TransferStats(started: Date(timeIntervalSince1970: 0))
        s.totalBytes = 1000
        s.doneBytes = 250
        XCTAssertEqual(s.fraction, 0.25)
        XCTAssertEqual(s.secondsRemaining(now: Date(timeIntervalSince1970: 10))!, 30, accuracy: 0.01)
        XCTAssertEqual(TransferStats.describe(seconds: 125, lang: .vi), "Khoảng 2 phút")
        XCTAssertEqual(TransferStats.describe(seconds: 5, lang: .en), "About 5 seconds")
    }
}

final class ShortcutTests: XCTestCase {
    func testParseAndDescribe() {
        let k = KeyCombo("cmd+shift+n")!
        XCTAssertTrue(k.command && k.shift && !k.option)
        XCTAssertEqual(k.description, "Cmd+Shift+N")
        XCTAssertEqual(KeyCombo("opt+left")!.description, "Option+←")
        XCTAssertEqual(KeyCombo(k.stringValue), k)
        XCTAssertNil(KeyCombo("hyper+x"))
    }

    func testDefaultsHaveNoConflicts() {
        for p in ShortcutPreset.allCases {
            XCTAssertTrue(ShortcutRegistry.conflicts(ShortcutRegistry.defaults(p)).isEmpty, p.rawValue)
        }
        for x in ShortcutRegistry.actions {
            XCTAssertNotEqual(L10n.t(x.titleKey, .vi), x.titleKey, x.id)
            XCTAssertNotEqual(L10n.t(x.category, .vi), x.category, x.category)
        }
    }

    func testWindowsPresetUsesAltArrows() {
        let b = ShortcutBindings(preset: .windows)
        XCTAssertEqual(b.combo(for: "back"), KeyCombo("opt+left"))
        XCTAssertEqual(ShortcutBindings().combo(for: "back"), KeyCombo("cmd+["))
    }

    func testConflictAndSuggestion() {
        var b = ShortcutBindings()
        let want = KeyCombo("cmd+t")!
        XCTAssertEqual(ShortcutRegistry.owner(of: want, in: b.effective, except: "refresh"), "newTab")
        XCTAssertEqual(ShortcutRegistry.owner(of: KeyCombo("shift+cmd+4")!, in: b.effective, except: "x")?.hasPrefix("system:"), true)
        let s = ShortcutRegistry.suggest(for: want, in: b.effective, except: "refresh")
        XCTAssertNotNil(s)
        XCTAssertNil(ShortcutRegistry.owner(of: s!, in: b.effective, except: "refresh"))
        b.set(s, for: "refresh")
        XCTAssertEqual(b.combo(for: "refresh"), s)
        b.set(nil, for: "refresh")
        XCTAssertNil(b.combo(for: "refresh"))
    }

    func testExportImport() throws {
        var b = ShortcutBindings(preset: .windows)
        b.set(KeyCombo("cmd+k"), for: "openApp")
        let back = try ShortcutBindings.importJSON(try b.exportJSON())
        XCTAssertEqual(back, b)
        XCTAssertEqual(back.combo(for: "openApp"), KeyCombo("cmd+k"))
    }
}

#if os(macOS)
final class ArchivePasswordTests: XCTestCase {
    private func roundTrip(_ enc: ZipEncryption) throws {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "mfile-zip-" + UUID().uuidString
        try fm.createDirectory(atPath: dir + "/Hồ sơ", withIntermediateDirectories: true)
        try "bí mật".write(toFile: dir + "/Hồ sơ/thư.txt", atomically: true, encoding: .utf8)
        let zip = dir + "/Hồ sơ.zip"
        let made = ArchiveTool.createZip(names: ["Hồ sơ"], in: dir, dest: zip, password: "Mk@2026abc", encryption: enc)
        XCTAssertTrue(made.ok, made.message)
        XCTAssertNotNil(made.encryption)
        print("Kiểu mã hóa yêu cầu \(enc.rawValue), đã dùng \(made.encryption?.rawValue ?? "-")")

        let noPw = dir + "/khong"
        try fm.createDirectory(atPath: noPw, withIntermediateDirectories: true)
        let r0 = ArchiveTool.extract(zip, to: noPw)
        XCTAssertFalse(fm.contents(atPath: noPw + "/Hồ sơ/thư.txt").flatMap { String(data: $0, encoding: .utf8) } == "bí mật",
                       "Giải nén được khi không có mật khẩu: \(r0)")

        let wrong = dir + "/sai"
        try fm.createDirectory(atPath: wrong, withIntermediateDirectories: true)
        XCTAssertFalse(ArchiveTool.extract(zip, to: wrong, password: "sai").0)

        let ok = dir + "/dung"
        try fm.createDirectory(atPath: ok, withIntermediateDirectories: true)
        let r = ArchiveTool.extract(zip, to: ok, password: "Mk@2026abc")
        XCTAssertTrue(r.0, r.1)
        XCTAssertEqual(try String(contentsOfFile: ok + "/Hồ sơ/thư.txt", encoding: .utf8), "bí mật")
        XCTAssertTrue(ArchiveTool.test(zip, password: "Mk@2026abc").0 || made.encryption == .aes256)
    }

    func testAES() throws { try roundTrip(.aes256) }
    func testZipCrypto() throws { try roundTrip(.zipCrypto) }

    func testStrength() {
        XCTAssertEqual(PasswordStrength.score("123"), 0)
        XCTAssertEqual(PasswordStrength.score("matkhau12"), 1)
        XCTAssertEqual(PasswordStrength.score("Mk@2026abcdef"), 2)
    }
}
#endif

final class HelpTests: XCTestCase {
    func testSearchWithoutAccents() {
        XCTAssertEqual(HelpTopics.search("sao chep duong dan").first?.id, "copyPath")
        XCTAssertEqual(HelpTopics.search("xóa vĩnh viễn").first?.id, "deleteForever")
        XCTAssertTrue(HelpTopics.search("giai nen").contains { $0.id == "extract" })
        XCTAssertFalse(HelpTopics.search("").isEmpty)
        XCTAssertTrue(HelpTopics.search("zzzqqq").isEmpty)
    }

    func testTopicsUnique() {
        XCTAssertEqual(Set(HelpTopics.all.map(\.id)).count, HelpTopics.all.count)
    }
}

final class RecursiveSearchTests: XCTestCase {
    func testFindsInSubfolders() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "mfile-search-" + UUID().uuidString
        try fm.createDirectory(atPath: root + "/Dự án/Hồ sơ", withIntermediateDirectories: true)
        fm.createFile(atPath: root + "/Dự án/Hồ sơ/Đề xuất ngân sách.docx", contents: Data())
        fm.createFile(atPath: root + "/khac.txt", contents: Data())
        let r = RecursiveSearch.run(in: root, query: "de xuat ngan sach")
        XCTAssertEqual(r.map(\.name), ["Đề xuất ngân sách.docx"])
        XCTAssertTrue(RecursiveSearch.matches("Hồ sơ dự thầu", "HO SO"))
        XCTAssertFalse(RecursiveSearch.matches("abc", ""))
    }
}

final class CloudStatusTests: XCTestCase {
    func testStatus() {
        let nd = URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue
        let cur = URLUbiquitousItemDownloadingStatus.current.rawValue
        XCTAssertEqual(CloudStatus.from(downloading: nd, isDownloading: false, isUploading: false, isUploaded: true, hasError: false), .onlineOnly)
        XCTAssertEqual(CloudStatus.from(downloading: cur, isDownloading: false, isUploading: false, isUploaded: true, hasError: false), .local)
        XCTAssertEqual(CloudStatus.from(downloading: cur, isDownloading: false, isUploading: true, isUploaded: false, hasError: false), .syncing)
        XCTAssertEqual(CloudStatus.from(downloading: nd, isDownloading: false, isUploading: false, isUploaded: true, hasError: true), .error)
        XCTAssertTrue(CloudStatus.isCloudPath("/Users/a/Library/CloudStorage/OneDrive-Personal/x", home: "/Users/a"))
        XCTAssertFalse(CloudStatus.isCloudPath("/Users/a/Documents", home: "/Users/a"))
    }
}

final class OfficeMetadataTests: XCTestCase {
    let core = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <cp:coreProperties xmlns:cp="x" xmlns:dc="y" xmlns:dcterms="z"><dc:title>Báo cáo &amp; dự toán</dc:title><dc:creator>Nguyễn Văn A</dc:creator><cp:lastModifiedBy>Trần B</cp:lastModifiedBy><cp:revision>7</cp:revision><cp:lastPrinted>2026-10-01T00:00:00Z</cp:lastPrinted><dcterms:created xsi:type="dcterms:W3CDTF">2026-10-29T08:40:00Z</dcterms:created></cp:coreProperties>
    """
    let app = "<Properties xmlns=\"a\"><Template>Normal.dotm</Template><TotalTime>95</TotalTime><Application>Microsoft Office Word</Application><Company>ITD</Company></Properties>"

    func testReadAndSet() {
        XCTAssertEqual(OfficeMetadata.value(of: "dc:title", in: core), "Báo cáo & dự toán")
        XCTAssertEqual(OfficeMetadata.value(of: "dcterms:created", in: core), "2026-10-29T08:40:00Z")
        XCTAssertNil(OfficeMetadata.value(of: "dc:subject", in: core))
        let x = OfficeMetadata.setting("dc:subject", to: "Hồ sơ <mời>", in: core, rootClose: "</cp:coreProperties>")
        XCTAssertEqual(OfficeMetadata.value(of: "dc:subject", in: x), "Hồ sơ <mời>")
        XCTAssertTrue(x.contains("&lt;mời&gt;"))
        let y = OfficeMetadata.setting("dc:creator", to: "Lê C", in: core, rootClose: "</cp:coreProperties>")
        XCTAssertEqual(OfficeMetadata.value(of: "dc:creator", in: y), "Lê C")
    }

    func testClean() {
        let c = OfficeMetadata.cleaned(core, part: .core)
        XCTAssertEqual(OfficeMetadata.value(of: "dc:creator", in: c), "")
        XCTAssertEqual(OfficeMetadata.value(of: "cp:lastModifiedBy", in: c), "")
        XCTAssertEqual(OfficeMetadata.value(of: "dc:title", in: c), "")
        XCTAssertNil(OfficeMetadata.value(of: "cp:lastPrinted", in: c))
        XCTAssertEqual(OfficeMetadata.value(of: "cp:revision", in: c), "1")
        XCTAssertEqual(OfficeMetadata.value(of: "dcterms:created", in: c), "2026-10-29T08:40:00Z")
        let a = OfficeMetadata.cleaned(app, part: .app)
        XCTAssertEqual(OfficeMetadata.value(of: "Company", in: a), "")
        XCTAssertEqual(OfficeMetadata.value(of: "Template", in: a), "")
        XCTAssertEqual(OfficeMetadata.value(of: "TotalTime", in: a), "0")
        XCTAssertEqual(OfficeMetadata.value(of: "Application", in: a), "Microsoft Office Word")
        XCTAssertEqual(OfficeMetadata.cleanedCustom("<?xml?><Properties xmlns=\"q\"><property name=\"Khách\"><vt:lpwstr>X</vt:lpwstr></property></Properties>"), "<?xml?><Properties xmlns=\"q\"></Properties>")
    }

    func testDeepCleanWord() {
        let n = OfficeMetadata.anonymousName
        let doc = "<w:body><w:ins w:id=\"1\" w:author=\"Nguyễn Văn A\" w:date=\"2026-10-29T08:40:00Z\"><w:r/></w:ins><w:del w:author=\"Trần B\" w:date=\"2026-10-30T09:00:00Z\"/></w:body>"
        let d = OfficeMetadata.deepCleaned(doc, part: "word/document.xml")
        XCTAssertFalse(d.contains("Nguyễn"))
        XCTAssertFalse(d.contains("Trần"))
        XCTAssertFalse(d.contains("w:date="))
        XCTAssertTrue(d.contains("w:author=\"\(n)\""))
        let com = "<w:comments><w:comment w:id=\"0\" w:author=\"Lê C\" w:date=\"2026-10-29T08:40:00Z\" w:initials=\"LC\"><w:p/></w:comment></w:comments>"
        let c = OfficeMetadata.deepCleaned(com, part: "word/comments.xml")
        XCTAssertFalse(c.contains("Lê C"))
        XCTAssertTrue(c.contains("w:initials=\"\(OfficeMetadata.anonymousInitials)\""))
        let people = "<w15:people><w15:person w15:author=\"Lê C\"><w15:presenceInfo w15:providerId=\"AD\" w15:userId=\"S::le.c@example.com::1\"/></w15:person></w15:people>"
        let p = OfficeMetadata.deepCleaned(people, part: "word/people.xml")
        XCTAssertFalse(p.contains("example.com"))
        XCTAssertFalse(p.contains("Lê C"))
        let settings = "<w:settings xmlns:w=\"x\"><w:zoom w:percent=\"100\"/><w:proofState w:spelling=\"clean\"/></w:settings>"
        let st = OfficeMetadata.deepCleaned(settings, part: "word/settings.xml")
        XCTAssertTrue(st.contains("<w:zoom w:percent=\"100\"/><w:removePersonalInformation/><w:removeDateAndTime/><w:proofState"))
        XCTAssertEqual(OfficeMetadata.deepCleaned(st, part: "word/settings.xml"), st)
    }

    func testDeepCleanExcelAndPowerPoint() {
        let n = OfficeMetadata.anonymousName
        let xc = "<comments><authors><author>Nguyễn Văn A</author><author>tc={1A2B}</author></authors></comments>"
        let x = OfficeMetadata.deepCleaned(xc, part: "xl/comments1.xml")
        XCTAssertTrue(x.contains("<author>\(n)</author>"))
        XCTAssertTrue(x.contains("<author>tc={1A2B}</author>"))
        let persons = "<personList><person displayName=\"Lê C\" id=\"{9}\" userId=\"le.c@example.com\" providerId=\"AD\"/></personList>"
        let ps = OfficeMetadata.deepCleaned(persons, part: "xl/persons/person.xml")
        XCTAssertFalse(ps.contains("Lê C") || ps.contains("example.com"))
        XCTAssertTrue(ps.contains("id=\"{9}\""))
        let wb = OfficeMetadata.deepCleaned("<workbook><workbookPr defaultThemeVersion=\"1\"/></workbook>", part: "xl/workbook.xml")
        XCTAssertTrue(wb.contains("<workbookPr filterPrivacy=\"1\" defaultThemeVersion"))
        let pa = "<p:cmAuthorLst><p:cmAuthor id=\"0\" name=\"Trần B\" initials=\"TB\" lastIdx=\"2\" clrIdx=\"0\"/></p:cmAuthorLst>"
        let pc = OfficeMetadata.deepCleaned(pa, part: "ppt/commentAuthors.xml")
        XCTAssertFalse(pc.contains("Trần B"))
        XCTAssertTrue(pc.contains("lastIdx=\"2\""))
        let pres = OfficeMetadata.deepCleaned("<p:presentation xmlns:p=\"x\" saveSubsetFonts=\"1\"><p:sldIdLst/></p:presentation>", part: "ppt/presentation.xml")
        XCTAssertTrue(pres.hasPrefix("<p:presentation removePersonalInfoOnSave=\"1\" xmlns:p"))
        // Tệp ngoài phạm vi không bị đụng tới.
        XCTAssertEqual(OfficeMetadata.deepCleaned(pa, part: "ppt/slides/slide1.xml"), pa)
    }

    #if os(macOS)
    func testFileRoundTrip() throws {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "office-test-" + UUID().uuidString
        try fm.createDirectory(atPath: dir + "/docProps", withIntermediateDirectories: true)
        try "<Types/>".write(toFile: dir + "/[Content_Types].xml", atomically: true, encoding: .utf8)
        try core.write(toFile: dir + "/docProps/core.xml", atomically: true, encoding: .utf8)
        try app.write(toFile: dir + "/docProps/app.xml", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: dir + "/word", withIntermediateDirectories: true)
        try "<w:comments><w:comment w:id=\"0\" w:author=\"Lê C\" w:date=\"2026-10-29T08:40:00Z\" w:initials=\"LC\"/></w:comments>".write(toFile: dir + "/word/comments.xml", atomically: true, encoding: .utf8)
        let doc = dir + "/Hồ sơ.docx"
        XCTAssertTrue(ArchiveTool.run("/usr/bin/zip", ["-X", "-r", "-q", "-nw", doc, "[Content_Types].xml", "docProps", "word"], cwd: dir).0)
        XCTAssertEqual(OfficeMetadata.read(doc)["creator"], "Nguyễn Văn A")
        XCTAssertEqual(OfficeMetadata.read(doc)["company"], "ITD")
        try OfficeMetadata.write(doc, ["subject": "Dự thầu", "company": "Công ty ITD"])
        XCTAssertEqual(OfficeMetadata.read(doc)["subject"], "Dự thầu")
        XCTAssertEqual(OfficeMetadata.read(doc)["company"], "Công ty ITD")
        XCTAssertTrue(MetadataCleaner.canClean(doc))
        let copy = dir + "/Hồ sơ - Bản sao.docx"
        try MetadataCleaner.clean(doc, to: copy)
        XCTAssertEqual(OfficeMetadata.read(copy)["creator"], "")
        XCTAssertEqual(OfficeMetadata.read(doc)["creator"], "Nguyễn Văn A")
        try MetadataCleaner.cleanInPlace(doc)
        XCTAssertEqual(OfficeMetadata.read(doc)["lastModifiedBy"], "")
        let out = dir + "/out"
        XCTAssertTrue(ArchiveTool.run("/usr/bin/unzip", ["-q", doc, "-d", out]).0)
        let comments = try String(contentsOfFile: out + "/word/comments.xml", encoding: .utf8)
        XCTAssertFalse(comments.contains("Lê C"))
        XCTAssertFalse(comments.contains("w:date="))
        try? fm.removeItem(atPath: dir)
    }
    #endif
}
