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
