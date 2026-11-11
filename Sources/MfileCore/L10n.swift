import Foundation

/// Ngôn ngữ giao diện. Đổi tức thì, không cần khởi động lại (FR-41).
public enum AppLanguage: String, CaseIterable, Sendable {
    case vi
    case en

    /// Ngôn ngữ mặc định lần đầu chạy: theo macOS, nếu là tiếng Việt thì dùng tiếng Việt.
    public static func systemDefault(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferred.first else { return .vi }
        return first.lowercased().hasPrefix("en") ? .en : .vi
    }

    public var toggled: AppLanguage { self == .vi ? .en : .vi }
}

/// Bảng thuật ngữ chuẩn (Mục 5 kế hoạch). Mỗi khóa có đủ tiếng Việt và tiếng Anh.
public enum L10n {
    public static let didChangeNotification = Notification.Name("MacMfile.languageDidChange")

    private static let storageKey = "MacMfile.language"
    private static var _current: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return AppLanguage.systemDefault()
    }()

    public static var current: AppLanguage {
        get { _current }
        set {
            guard newValue != _current else { return }
            _current = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Lấy chuỗi theo ngôn ngữ đang chọn (hoặc ngôn ngữ chỉ định).
    public static func t(_ key: String, _ lang: AppLanguage? = nil) -> String {
        guard let pair = table[key] else { return key }
        return (lang ?? current) == .vi ? pair.vi : pair.en
    }

    /// Thay {0}, {1}… bằng tham số.
    public static func f(_ key: String, _ args: CustomStringConvertible..., lang: AppLanguage? = nil) -> String {
        var s = t(key, lang)
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a.description) }
        return s
    }

    public static var allKeys: [String] { Array(table.keys) }

    static let table: [String: (vi: String, en: String)] = [
        // Vùng giao diện (5.1)
        "home": ("Trang chủ", "Home"),
        "gallery": ("Thư viện ảnh", "Gallery"),
        "quickAccess": ("Truy nhập nhanh", "Quick access"),
        "thisMac": ("Máy Mac này", "This Mac"),
        "network": ("Mạng", "Network"),
        "trash": ("Thùng rác", "Recycle Bin"),
        "desktop": ("Màn hình nền", "Desktop"),
        "downloads": ("Tải về", "Downloads"),
        "documents": ("Tài liệu", "Documents"),
        "pictures": ("Ảnh", "Pictures"),
        "music": ("Nhạc", "Music"),
        "videos": ("Video", "Videos"),
        "searchIn": ("Tìm kiếm trong {0}", "Search {0}"),
        // Thanh lệnh (5.2)
        "new": ("Mới", "New"),
        "newFolder": ("Thư mục", "Folder"),
        "cut": ("Cắt", "Cut"),
        "copy": ("Sao chép", "Copy"),
        "paste": ("Dán", "Paste"),
        "rename": ("Đổi tên", "Rename"),
        "share": ("Chia sẻ", "Share"),
        "delete": ("Xóa", "Delete"),
        "sort": ("Sắp xếp", "Sort"),
        "view": ("Xem", "View"),
        "filter": ("Lọc", "Filter"),
        "seeMore": ("Xem thêm", "See more"),
        "details": ("Chi tiết", "Details"),
        "back": ("Quay lại", "Back"),
        "forward": ("Tiến", "Forward"),
        "up": ("Lên một cấp", "Up"),
        "refresh": ("Làm mới", "Refresh"),
        // Cột
        "colName": ("Tên", "Name"),
        "colModified": ("Ngày sửa đổi", "Date modified"),
        "colType": ("Loại", "Type"),
        "colSize": ("Kích cỡ", "Size"),
        "typeFolder": ("Thư mục tệp", "File folder"),
        "typeFile": ("Tệp {0}", "{0} File"),
        // Menu chuột phải (5.3)
        "open": ("Mở", "Open"),
        "openNewTab": ("Mở trong tab mới", "Open in new tab"),
        "openNewWindow": ("Mở trong cửa sổ mới", "Open in new window"),
        "pinQuick": ("Ghim vào Truy nhập nhanh", "Pin to Quick access"),
        "unpinQuick": ("Bỏ ghim khỏi Truy nhập nhanh", "Unpin from Quick access"),
        "copyPath": ("Sao chép đường dẫn", "Copy as path"),
        "properties": ("Thuộc tính", "Properties"),
        "view_extraLargeIcons": ("Biểu tượng cực lớn", "Extra large icons"),
        "view_largeIcons": ("Biểu tượng lớn", "Large icons"),
        "view_mediumIcons": ("Biểu tượng trung bình", "Medium icons"),
        "view_smallIcons": ("Biểu tượng nhỏ", "Small icons"),
        "view_list": ("Danh sách", "List"),
        "view_details": ("Chi tiết", "Details"),
        "view_tiles": ("Ô xếp", "Tiles"),
        "view_content": ("Nội dung", "Content"),
        "compactView": ("Chế độ xem thu gọn", "Compact view"),
        "show": ("Hiện", "Show"),
        "fileExtensions": ("Phần mở rộng tên tệp", "File name extensions"),
        "itemCheckBoxes": ("Hộp kiểm mục", "Item check boxes"),
        "newTab": ("Tab mới", "New tab"),
        "closeTab": ("Đóng tab", "Close tab"),
        "nextTab": ("Tab kế tiếp", "Next tab"),
        "previousTab": ("Tab trước", "Previous tab"),
        "duplicateTab": ("Nhân bản tab", "Duplicate tab"),
        "closeOtherTabs": ("Đóng các tab khác", "Close other tabs"),
        "moveTabToNewWindow": ("Chuyển tab sang cửa sổ mới", "Move tab to new window"),
        "openWith": ("Mở bằng", "Open with"),
        "defaultApp": ("mặc định", "default"),
        "chooseOtherApp": ("Chọn ứng dụng khác…", "Choose another app…"),
        "openInTerminal": ("Mở trong Terminal", "Open in Terminal"),
        "showMoreOptions": ("Hiện thêm tùy chọn", "Show more options"),
        "shareWith": ("Chia sẻ với", "Share with"),
        "addFavorites": ("Thêm vào Ưa thích", "Add to Favorites"),
        "compressTo": ("Nén thành…", "Compress to…"),
        "fmtZip": ("Tệp ZIP", "ZIP File"),
        "fmt7z": ("Tệp 7z", "7z File"),
        "fmtTar": ("Tệp TAR", "TAR File"),
        "fmtTarGz": ("Tệp TAR.GZ", "TAR.GZ File"),
        "fmtZipFolder": ("Thư mục nén (ZIP)", "Compressed (zipped) folder"),
        "sendToDocuments": ("Tài liệu", "Documents"),
        "editInTextEdit": ("Sửa bằng TextEdit", "Edit in TextEdit"),
        "sendTo": ("Gửi tới", "Send to"),
        "sendToDesktop": ("Màn hình nền (tạo lối tắt)", "Desktop (create shortcut)"),
        "sentToDesktop": ("Đã tạo lối tắt trên Màn hình nền", "Shortcut created on the Desktop"),
        "createShortcut": ("Tạo lối tắt", "Create shortcut"),
        "shortcutSuffix": (" - Lối tắt", " - Shortcut"),
        "duplicate": ("Nhân bản", "Duplicate"),
        "showInFinder": ("Hiện trong Finder", "Show in Finder"),
        "newTextFile": ("Tài liệu văn bản", "Text Document"),
        "newTextName": ("Tài liệu văn bản mới.txt", "New Text Document.txt"),
        "sortBy": ("Sắp xếp theo", "Sort by"),
        "hiddenItems": ("Mục ẩn", "Hidden items"),
        "extractAll": ("Giải nén tất cả…", "Extract all…"),
        "extractHere": ("Giải nén tại đây", "Extract here"),
        "extractTo": ("Giải nén vào “{0}\\”", "Extract to “{0}\\”"),
        "testArchive": ("Kiểm tra tệp nén", "Test archive"),
        "compressZip": ("Nén thành tệp ZIP", "Compress to ZIP file"),
        "chooseDestination": ("Chọn đích và giải nén tệp", "Select a destination and extract files"),
        "extract": ("Giải nén", "Extract"),
        "extracting": ("Đang giải nén “{0}”…", "Extracting “{0}”…"),
        "extracted": ("Đã giải nén vào “{0}”", "Extracted to “{0}”"),
        "compressing": ("Đang nén {0} mục…", "Compressing {0} items…"),
        "compressed": ("Đã tạo “{0}”", "Created “{0}”"),
        "archiveOK": ("Tệp nén “{0}” không có lỗi.", "No errors found in “{0}”."),
        "archiveBad": ("Tệp nén “{0}” bị lỗi hoặc không đọc được.", "“{0}” is damaged or can't be read."),
        "copyAddress": ("Sao chép địa chỉ", "Copy address"),
        "editAddress": ("Chỉnh sửa địa chỉ", "Edit address"),
        "pasteAndGo": ("Dán và đi", "Paste and go"),
        // Thanh trạng thái, hộp thoại (5.5)
        "items": ("{0} mục", "{0} items"),
        "selected": ("Đã chọn {0} mục", "{0} items selected"),
        "emptyFolder": ("Thư mục này trống.", "This folder is empty."),
        "confirmTrash": ("Bạn có chắc muốn chuyển {0} mục này vào Thùng rác không?", "Are you sure you want to move these {0} items to the Recycle Bin?"),
        "confirmDeleteForever": ("Xóa vĩnh viễn {0} mục này?", "Permanently delete these {0} items?"),
        "deleteForeverNote": ("Không thể khôi phục từ Thùng rác sau khi xóa.", "You can't restore them from the Recycle Bin."),
        "deleteForever": ("Xóa vĩnh viễn", "Delete permanently"),
        "yes": ("Có", "Yes"),
        "no": ("Không", "No"),
        "cancel": ("Hủy", "Cancel"),
        "ok": ("OK", "OK"),
        "newFolderName": ("Thư mục mới", "New folder"),
        "renameTitle": ("Đổi tên “{0}”", "Rename “{0}”"),
        "pathNotFound": ("Không tìm thấy “{0}”. Hãy kiểm tra lại đường dẫn.", "Can't find “{0}”. Check the spelling and try again."),
        "copiedPaths": ("Đã sao chép {0} đường dẫn", "Copied {0} paths"),
        "movedToTrash": ("Đã chuyển {0} mục vào Thùng rác", "Moved {0} items to the Recycle Bin"),
        "errorTitle": ("Không thực hiện được", "Something went wrong"),
        // Thanh menu macOS (5.4)
        "menuFile": ("Tệp", "File"),
        "menuEdit": ("Sửa", "Edit"),
        "menuView": ("Xem", "View"),
        "menuGo": ("Đi", "Go"),
        "menuWindow": ("Cửa sổ", "Window"),
        "menuHelp": ("Trợ giúp", "Help"),
        "about": ("Giới thiệu Mac Mfile", "About Mac Mfile"),
        "settings": ("Cài đặt…", "Settings…"),
        "hide": ("Ẩn Mac Mfile", "Hide Mac Mfile"),
        "quit": ("Thoát Mac Mfile", "Quit Mac Mfile"),
        "newWindow": ("Cửa sổ mới", "New window"),
        "closeWindow": ("Đóng cửa sổ", "Close window"),
        "undo": ("Hoàn tác", "Undo"),
        "redo": ("Làm lại", "Redo"),
        "selectAll": ("Chọn tất cả", "Select all"),
        "search": ("Tìm kiếm", "Search"),
        "goToFolder": ("Đi đến thư mục…", "Go to folder…"),
        "minimize": ("Thu nhỏ", "Minimize"),
        "maximize": ("Phóng to", "Maximize"),
        "close": ("Đóng", "Close"),
        "snapLeft": ("Nửa trái", "Left half"),
        "snapRight": ("Nửa phải", "Right half"),
        "userGuide": ("Hướng dẫn sử dụng", "User guide"),
        "shortcuts": ("Bảng tra phím tắt", "Keyboard shortcuts"),
        "language": ("Ngôn ngữ: Tiếng Việt", "Language: English"),
    ]
}
