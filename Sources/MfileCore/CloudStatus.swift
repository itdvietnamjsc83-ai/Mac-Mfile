import Foundation

/// Cột "Trạng thái" như OneDrive trên Windows: tệp chỉ có trên đám mây, có sẵn trên máy, hay đang đồng bộ.
/// Áp dụng cho iCloud Drive và các ổ dùng File Provider của macOS (OneDrive, Google Drive, Dropbox…).
public enum CloudStatus: String, Sendable {
    /// Chỉ có trên đám mây (biểu tượng đám mây).
    case onlineOnly
    /// Có sẵn trên máy, đã đồng bộ (dấu tích xanh).
    case local
    /// Đang tải xuống từ đám mây.
    case downloading
    /// Đang tải lên đám mây.
    case uploading
    /// Có thay đổi trên máy đang chờ tải lên (tệp vừa tạo, vừa sửa).
    case syncing
    /// Lỗi đồng bộ thật sự (dịch vụ từ chối tệp, hết dung lượng…).
    case error

    public var l10nKey: String {
        switch self {
        case .onlineOnly: return "syncOnlineOnly"
        case .local: return "syncLocal"
        case .downloading: return "syncDownloading"
        case .uploading: return "syncUploading"
        case .syncing: return "syncPending"
        case .error: return "syncError"
        }
    }

    /// Trạng thái đang chuyển tiếp: cần kiểm tra lại thường xuyên cho tới khi xong.
    public var isTransient: Bool { self == .downloading || self == .uploading || self == .syncing }

    /// Thư mục nằm trong vùng đám mây thì mới hiện cột Trạng thái.
    public static func isCloudPath(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        path.hasPrefix(home + "/Library/CloudStorage/") || path.hasPrefix(home + "/Library/Mobile Documents/")
    }

    public static let resourceKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadRequestedKey, .contentModificationDateKey,
    ]

    /// Kết quả đọc trạng thái, kèm mô tả lỗi (nếu có) để hiện khi rê chuột.
    public struct Info: Equatable, Sendable {
        public let status: CloudStatus
        public let detail: String?
        public init(status: CloudStatus, detail: String? = nil) { self.status = status; self.detail = detail }
    }

    /// Suy ra trạng thái từ thuộc tính hệ thống của tệp; nil nếu tệp không thuộc ổ đám mây.
    public static func of(_ path: String) -> CloudStatus? { info(path)?.status }

    /// Đọc trạng thái mới nhất. Mỗi lần tạo URL mới nên macOS không trả lại giá trị đã lưu đệm từ lần trước.
    public static func info(_ path: String, now: Date = Date()) -> Info? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: resourceKeys), v.isUbiquitousItem == true else { return nil }
        let upErr = v.ubiquitousItemUploadingError
        let downErr = v.ubiquitousItemDownloadingError
        let status = from(downloading: v.ubiquitousItemDownloadingStatus?.rawValue,
                          isDownloading: v.ubiquitousItemIsDownloading ?? false,
                          downloadRequested: v.ubiquitousItemDownloadRequested ?? false,
                          isUploading: v.ubiquitousItemIsUploading ?? false,
                          isUploaded: v.ubiquitousItemIsUploaded ?? true,
                          uploadError: upErr.map { ErrorKind(domain: $0.domain, code: $0.code) },
                          downloadError: downErr.map { ErrorKind(domain: $0.domain, code: $0.code) },
                          modifiedSecondsAgo: v.contentModificationDate.map { now.timeIntervalSince($0) })
        let err = (downErr ?? upErr).map { "\($0.localizedDescription) (\($0.domain) \($0.code))" }
        return Info(status: status, detail: status == .error ? err : nil)
    }

    /// Mã lỗi đồng bộ, tách khỏi NSError để kiểm thử.
    public struct ErrorKind: Equatable, Sendable {
        public let domain: String
        public let code: Int
        public init(domain: String, code: Int) { self.domain = domain; self.code = code }

        /// Lỗi tạm thời khi tệp vừa tạo hoặc mất mạng: dịch vụ chưa nhận tệp, máy chủ chưa liên lạc được.
        /// Những lỗi này tự hết khi đồng bộ xong, nên hiện "Đang chờ đồng bộ" thay cho dấu chấm than.
        public var isTransient: Bool {
            switch domain {
            case "NSFileProviderErrorDomain":
                // -1004 serverUnreachable, -1005 noSuchItem (dịch vụ chưa biết tệp mới),
                // -1002 syncAnchorExpired, -2003 pageExpired, -2005 cannotSynchronize (đang thử lại),
                // -2006 providerNotFound / -2007 providerTranslocated (dịch vụ đang khởi động),
                // -2008 olderExtensionVersionRunning, -2009 newerExtensionVersionFound.
                return [-1004, -1005, -1002, -2003, -2005, -2006, -2007, -2008, -2009].contains(code)
            case NSCocoaErrorDomain:
                // 4353 NSUbiquitousFileUnavailableError, 4355 NSUbiquitousFileUbiquityServerNotAvailable.
                return code == 4353 || code == 4355
            case NSURLErrorDomain:
                return true
            default:
                return false
            }
        }
    }

    /// Phần quyết định, tách riêng để kiểm thử.
    /// `modifiedSecondsAgo`: tệp vừa sửa/vừa tạo trong 2 phút thì lỗi tải lên được coi là đang chờ, chưa phải lỗi.
    public static func from(downloading: String?, isDownloading: Bool, downloadRequested: Bool = false,
                            isUploading: Bool, isUploaded: Bool,
                            uploadError: ErrorKind? = nil, downloadError: ErrorKind? = nil,
                            modifiedSecondsAgo: TimeInterval? = nil) -> CloudStatus {
        let notDownloaded = downloading == URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue
        // Đang chạy thì ưu tiên hiện tiến trình, kể cả khi còn sót lỗi của lần thử trước.
        if isDownloading { return .downloading }
        if isUploading { return .uploading }
        if let e = downloadError, !e.isTransient { return .error }
        if let e = uploadError {
            let fresh = (modifiedSecondsAgo ?? .infinity) < 120
            return e.isTransient || fresh ? .syncing : .error
        }
        // Đã bấm tải về nhưng hệ thống chưa bắt đầu: vẫn là đang tải xuống.
        if notDownloaded && downloadRequested { return .downloading }
        if !isUploaded { return .syncing }
        if notDownloaded { return .onlineOnly }
        return .local
    }

    /// Bản cũ (giữ cho mã gọi cũ và kiểm thử).
    public static func from(downloading: String?, isDownloading: Bool, isUploading: Bool, isUploaded: Bool, hasError: Bool) -> CloudStatus {
        from(downloading: downloading, isDownloading: isDownloading, isUploading: isUploading, isUploaded: isUploaded,
             uploadError: hasError ? ErrorKind(domain: "test", code: 1) : nil)
    }
}

/// Ổ đám mây chứa một đường dẫn: dùng cho menu chuột phải (Xem trực tuyến, tên dịch vụ).
public struct CloudProvider: Equatable, Sendable {
    public enum Kind: String, Sendable { case iCloud, oneDrive, oneDriveBusiness, googleDrive, dropbox, box, other }
    public let kind: Kind
    /// Thư mục gốc của ổ trên máy, ví dụ ~/Library/CloudStorage/OneDrive-Personal.
    public let root: String
    /// Tên hiển thị: "OneDrive", "Google Drive", "iCloud Drive"…
    public let name: String

    public static func of(_ path: String, home: String = NSHomeDirectory()) -> CloudProvider? {
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == icloud || path.hasPrefix(icloud + "/") { return CloudProvider(kind: .iCloud, root: icloud, name: "iCloud Drive") }
        let cs = home + "/Library/CloudStorage/"
        guard path.hasPrefix(cs) else { return nil }
        let folder = String(path.dropFirst(cs.count).split(separator: "/", maxSplits: 1).first ?? "")
        guard !folder.isEmpty else { return nil }
        let root = cs + folder
        if folder == "OneDrive-Personal" || folder == "OneDrive" { return CloudProvider(kind: .oneDrive, root: root, name: "OneDrive") }
        if folder.hasPrefix("OneDrive-") { return CloudProvider(kind: .oneDriveBusiness, root: root, name: "OneDrive - " + folder.dropFirst(9)) }
        if folder.hasPrefix("GoogleDrive") { return CloudProvider(kind: .googleDrive, root: root, name: "Google Drive") }
        if folder.hasPrefix("Dropbox") { return CloudProvider(kind: .dropbox, root: root, name: "Dropbox") }
        if folder.hasPrefix("Box") { return CloudProvider(kind: .box, root: root, name: "Box") }
        return CloudProvider(kind: .other, root: root, name: folder)
    }

    /// Trang web của dịch vụ (Xem trực tuyến). Dropbox mở đúng thư mục; các dịch vụ khác không có địa chỉ
    /// theo đường dẫn nên mở trang chính của ổ.
    public func webURL(for path: String) -> URL? {
        switch kind {
        case .iCloud: return URL(string: "https://www.icloud.com/iclouddrive/")
        case .oneDrive: return URL(string: "https://onedrive.live.com/")
        case .oneDriveBusiness: return URL(string: "https://www.office.com/launch/onedrive")
        case .googleDrive: return URL(string: "https://drive.google.com/drive/my-drive")
        case .box: return URL(string: "https://app.box.com/folder/0")
        case .dropbox:
            var rel = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : ""
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                rel = (rel as NSString).deletingLastPathComponent
            }
            let enc = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return URL(string: "https://www.dropbox.com/home" + enc)
        case .other: return nil
        }
    }

    /// Dịch vụ có menu riêng trong Finder (Chia sẻ, Sao chép liên kết, Quản lý quyền truy cập…).
    public var hasFinderMenu: Bool { kind != .iCloud }
}
