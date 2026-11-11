import Foundation

/// Cột "Trạng thái" như OneDrive trên Windows: tệp chỉ có trên đám mây, có sẵn trên máy, hay đang đồng bộ.
/// Áp dụng cho iCloud Drive và các ổ dùng File Provider của macOS (OneDrive, Google Drive, Dropbox…).
public enum CloudStatus: String, Sendable {
    case onlineOnly, local, syncing, error

    public var l10nKey: String {
        switch self {
        case .onlineOnly: return "syncOnlineOnly"
        case .local: return "syncLocal"
        case .syncing: return "syncPending"
        case .error: return "syncError"
        }
    }

    /// Thư mục nằm trong vùng đám mây thì mới hiện cột Trạng thái.
    public static func isCloudPath(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        path.hasPrefix(home + "/Library/CloudStorage/") || path.hasPrefix(home + "/Library/Mobile Documents/")
    }

    public static let resourceKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemDownloadingErrorKey,
    ]

    /// Suy ra trạng thái từ thuộc tính hệ thống của tệp; nil nếu tệp không thuộc ổ đám mây.
    public static func of(_ path: String) -> CloudStatus? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: resourceKeys), v.isUbiquitousItem == true else { return nil }
        return from(downloading: v.ubiquitousItemDownloadingStatus?.rawValue,
                    isDownloading: v.ubiquitousItemIsDownloading ?? false,
                    isUploading: v.ubiquitousItemIsUploading ?? false,
                    isUploaded: v.ubiquitousItemIsUploaded ?? true,
                    hasError: v.ubiquitousItemUploadingError != nil || v.ubiquitousItemDownloadingError != nil)
    }

    /// Phần quyết định, tách riêng để kiểm thử.
    public static func from(downloading: String?, isDownloading: Bool, isUploading: Bool, isUploaded: Bool, hasError: Bool) -> CloudStatus {
        if hasError { return .error }
        if isDownloading || isUploading || !isUploaded { return .syncing }
        if downloading == URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue { return .onlineOnly }
        return .local
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
