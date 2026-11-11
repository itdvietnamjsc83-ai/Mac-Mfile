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
        XCTAssertNil(NavigationHistory.parent(of: "/"))
    }

    func testBreadcrumbLocalized() {
        let c = Breadcrumb.crumbs(for: "/Users/dung/Documents/Hợp đồng", home: "/Users/dung", lang: .vi)
        XCTAssertEqual(c.map(\.title), ["Máy Mac này", "dung", "Tài liệu", "Hợp đồng"])
        XCTAssertEqual(c.last?.path, "/Users/dung/Documents/Hợp đồng")
        let e = Breadcrumb.crumbs(for: "/Volumes/USB", home: "/Users/dung", lang: .en)
        XCTAssertEqual(e.map(\.title), ["This Mac", "Volumes", "USB"])
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
