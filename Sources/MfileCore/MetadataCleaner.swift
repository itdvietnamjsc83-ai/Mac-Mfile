import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(PDFKit)
import PDFKit
#endif

/// "Xóa thuộc tính và thông tin cá nhân" như Windows (Mục 5.11): bỏ EXIF, GPS, tên máy ảnh, tác giả, nguồn tải xuống.
public enum MetadataCleaner {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    public static func canClean(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExts.contains(ext) || ext == "pdf" || OfficeMetadata.extensions.contains(ext)
    }

    /// Thuộc tính mở rộng mang dấu vết cá nhân (nguồn tải xuống, ghi chú Finder). Không đụng tới cờ cách ly bảo mật.
    public static let personalXattrs = ["com.apple.metadata:kMDItemWhereFroms", "com.apple.metadata:kMDItemFinderComment",
                                        "com.apple.metadata:kMDItemAuthors", "com.apple.metadata:kMDItemCreator"]

    public enum CleanError: Error { case unsupported, failed }

    /// Ghi bản đã làm sạch của `src` ra `dst`.
    public static func clean(_ src: String, to dst: String) throws {
        let ext = (src as NSString).pathExtension.lowercased()
        if imageExts.contains(ext) { try cleanImage(src, to: dst) }
        else if ext == "pdf" { try cleanPDF(src, to: dst) }
        else if OfficeMetadata.extensions.contains(ext) {
            #if os(macOS)
            try OfficeMetadata.clean(src, to: dst)
            #else
            throw CleanError.unsupported
            #endif
        }
        else { throw CleanError.unsupported }
        removePersonalXattrs(dst)
    }

    /// Làm sạch ngay trên tệp (ghi tạm rồi thay thế, giữ nguyên ngày tạo).
    public static func cleanInPlace(_ path: String) throws {
        let tmp = (path as NSString).deletingLastPathComponent + "/.mfile-clean-" + UUID().uuidString + "." + (path as NSString).pathExtension
        try clean(path, to: tmp)
        let fm = FileManager.default
        let created = (try? fm.attributesOfItem(atPath: path))?[.creationDate]
        _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        if let c = created { try? fm.setAttributes([.creationDate: c], ofItemAtPath: path) }
        removePersonalXattrs(path)
    }

    /// Tên bản sao kiểu Windows: "Ảnh - Bản sao.jpg".
    public static func copyName(for path: String, lang: AppLanguage = L10n.current) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        let suffix = lang == .vi ? " - Bản sao" : " - Copy"
        return name + suffix + (ext.isEmpty ? "" : "." + ext)
    }

    public static func removePersonalXattrs(_ path: String) {
        for a in personalXattrs { removexattr(path, a, 0) }
    }

    /// Các khóa siêu dữ liệu ảnh có trong tệp (để hiện ở tab Chi tiết và kiểm thử).
    public static func imageMetadataGroups(_ path: String) -> Set<String> {
        #if canImport(ImageIO)
        guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any] else { return [] }
        var out = Set<String>()
        for k in [kCGImagePropertyGPSDictionary, kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] {
            if let d = p[k as String] as? [String: Any], !d.isEmpty { out.insert(k as String) }
        }
        return out
        #else
        return []
        #endif
    }

    private static func cleanImage(_ src: String, to dst: String) throws {
        #if canImport(ImageIO)
        guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: src) as CFURL, nil),
              let type = CGImageSourceGetType(s) else { throw CleanError.failed }
        let count = CGImageSourceGetCount(s)
        guard let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dst) as CFURL, type, count, nil) else { throw CleanError.failed }
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(s, i, nil) else { throw CleanError.failed }
            let props = CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [String: Any] ?? [:]
            // Chỉ giữ hướng ảnh để ảnh không bị xoay; mọi EXIF/GPS/TIFF/IPTC bị bỏ khi mã hóa lại.
            var keep: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.95]
            if let o = props[kCGImagePropertyOrientation as String] { keep[kCGImagePropertyOrientation as String] = o }
            CGImageDestinationAddImage(d, img, keep as CFDictionary)
        }
        guard CGImageDestinationFinalize(d) else { throw CleanError.failed }
        #else
        throw CleanError.unsupported
        #endif
    }

    private static func cleanPDF(_ src: String, to dst: String) throws {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: URL(fileURLWithPath: src)) else { throw CleanError.failed }
        var attrs = doc.documentAttributes ?? [:]
        for k in [PDFDocumentAttribute.authorAttribute, .creatorAttribute, .producerAttribute, .keywordsAttribute,
                  .subjectAttribute, .titleAttribute] { attrs.removeValue(forKey: k) }
        doc.documentAttributes = attrs
        guard doc.write(to: URL(fileURLWithPath: dst)) else { throw CleanError.failed }
        #else
        throw CleanError.unsupported
        #endif
    }
}
