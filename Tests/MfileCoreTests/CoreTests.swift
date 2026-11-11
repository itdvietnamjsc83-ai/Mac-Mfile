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
