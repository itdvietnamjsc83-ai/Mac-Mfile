import Foundation

/// Một mục Hướng dẫn sử dụng (F1, bản mẫu bảng 22–24): làm ngay được hoặc chỉ từng bước.
public struct HelpTopic: Equatable {
    public let id: String
    public let title: (vi: String, en: String)
    public let body: (vi: String, en: String)
    /// Lệnh chạy khi bấm "Làm ngay" (tên selector, ví dụ "copyPath:").
    public let action: String?
    /// Các bước "Chỉ cho tôi": (vùng giao diện, lời nhắc vi, lời nhắc en).
    public let steps: [(target: String, vi: String, en: String)]
    public let keywords: String
    public let common: Bool

    public static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }

    public func title(_ l: AppLanguage = L10n.current) -> String { l == .vi ? title.vi : title.en }
    public func body(_ l: AppLanguage = L10n.current) -> String { l == .vi ? body.vi : body.en }
}

public enum HelpTopics {
    private static func t(_ id: String, _ tv: String, _ te: String, _ bv: String, _ be: String, action: String? = nil,
                          steps: [(String, String, String)] = [], kw: String = "", common: Bool = false) -> HelpTopic {
        HelpTopic(id: id, title: (tv, te), body: (bv, be), action: action, steps: steps.map { (target: $0.0, vi: $0.1, en: $0.2) }, keywords: kw, common: common)
    }

    public static let all: [HelpTopic] = [
        t("copyPath", "Sao chép đường dẫn của tệp", "Copy a file's path",
          "Bấm Cmd+Shift+C, hoặc chuột phải › Sao chép đường dẫn. Đường dẫn có ngoặc kép, dán thẳng vào ứng dụng khác.",
          "Press Cmd+Shift+C, or right-click › Copy as path. The path is quoted and pastes straight into other apps.",
          action: "copyPath:", steps: [("content", "Nhấp chuột phải vào tệp cần lấy đường dẫn", "Right-click the file"),
                                       ("content", "Chọn “Sao chép đường dẫn”", "Choose “Copy as path”")],
          kw: "copy path duong dan dia chi", common: true),
        t("copyAddress", "Sao chép địa chỉ thư mục đang mở", "Copy the current folder's address",
          "Bấm Cmd+L rồi Cmd+C. Hoặc chuột phải vào thanh địa chỉ › Sao chép địa chỉ.",
          "Press Cmd+L then Cmd+C. Or right-click the address bar › Copy address.",
          action: "copyAddress:", steps: [("address", "Bấm vào thanh địa chỉ (Cmd+L)", "Click the address bar (Cmd+L)"),
                                          ("address", "Bấm Cmd+C để sao chép", "Press Cmd+C to copy")],
          kw: "address bar thanh dia chi copy"),
        t("pasteAndGo", "Dán đường dẫn để mở thư mục", "Paste a path to open a folder",
          "Cmd+L, Cmd+V, Enter. Hoặc chuột phải thanh địa chỉ › Dán và đi. Dán đường dẫn của tệp thì mở thư mục chứa và chọn sẵn tệp.",
          "Cmd+L, Cmd+V, Enter. Or right-click the address bar › Paste and go. A file path opens its folder with the file selected.",
          action: "pasteAndGo:", steps: [("address", "Bấm vào thanh địa chỉ rồi dán (Cmd+V)", "Click the address bar and paste (Cmd+V)"),
                                         ("address", "Bấm Enter để mở", "Press Enter to open")],
          kw: "paste go dan mo"),
        t("deleteForever", "Xóa vĩnh viễn, không qua Thùng rác", "Delete permanently",
          "Chọn tệp rồi bấm Shift+Delete (Shift+⌫). Có hộp hỏi lại vì không khôi phục được.",
          "Select files and press Shift+Delete (Shift+⌫). You'll be asked to confirm because it can't be undone.",
          action: "deleteForever:", steps: [("content", "Chọn tệp cần xóa", "Select the files"), ("content", "Bấm Shift+Delete", "Press Shift+Delete")],
          kw: "xoa vinh vien delete permanently", common: true),
        t("trash", "Chuyển vào Thùng rác", "Move to the Recycle Bin",
          "Chọn tệp rồi bấm ⌫ (delete) hoặc nút Xóa trên thanh lệnh. Mở Thùng rác ở cuối ngăn bên trái để khôi phục.",
          "Select files and press ⌫ (delete) or the Delete button. Open the Recycle Bin at the bottom of the left pane to restore.",
          action: "trashSelected:", steps: [("delete", "Bấm nút Xóa trên thanh lệnh", "Click Delete on the command bar")], kw: "xoa thung rac trash recycle"),
        t("pin", "Ghim thư mục vào Truy nhập nhanh", "Pin a folder to Quick access",
          "Chuột phải thư mục › Ghim vào Truy nhập nhanh, hoặc Cmd+Shift+P, hoặc kéo thư mục thả vào ngăn bên trái. Cmd+1…9 mở nhanh mục ghim.",
          "Right-click a folder › Pin to Quick access, press Cmd+Shift+P, or drag it onto the left pane. Cmd+1…9 opens pins.",
          action: "pinSelected:", steps: [("content", "Chọn thư mục cần ghim", "Select the folder"),
                                          ("sidebar", "Kéo thả vào đây, hoặc bấm Cmd+Shift+P", "Drag it here, or press Cmd+Shift+P")],
          kw: "ghim pin quick access yeu thich", common: true),
        t("snap", "Xếp cửa sổ nửa màn hình", "Snap the window to half the screen",
          "Cmd+← xếp sang trái, Cmd+→ xếp sang phải (như Windows+←/→). Mở hai cửa sổ để kéo tệp qua lại.",
          "Cmd+← snaps left, Cmd+→ snaps right (like Windows+←/→). Open two windows to drag files between them.",
          action: "snapLeft:", kw: "snap chia doi man hinh cua so", common: true),
        t("shortcuts", "Đổi phím tắt", "Change shortcuts",
          "Mac Mfile › Cài đặt phím tắt. Bấm vào ô phím rồi nhấn tổ hợp mới; bị trùng sẽ có gợi ý phím còn trống.",
          "Mac Mfile › Shortcut settings. Click a key box and press the new keys; conflicts get a free suggestion.",
          action: "showShortcutSettings:", kw: "phim tat shortcut keyboard", common: true),
        t("removeInfo", "Xóa thông tin cá nhân của ảnh, PDF", "Remove personal info from photos and PDFs",
          "Chuột phải › Thuộc tính › Chi tiết › Xóa thuộc tính và thông tin cá nhân. Bỏ GPS, máy ảnh, tác giả, nguồn tải xuống.",
          "Right-click › Properties › Details › Remove Properties and Personal Information. Removes GPS, camera, author, download source.",
          action: "showInfo:", kw: "gps exif metadata thong tin ca nhan privacy", common: true),
        t("extract", "Giải nén tệp ZIP, 7z, RAR", "Extract ZIP, 7z, RAR",
          "Chuột phải tệp nén › Giải nén tất cả…, Giải nén tại đây, hoặc Giải nén vào thư mục. Tệp có mật khẩu sẽ được hỏi.",
          "Right-click the archive › Extract All…, Extract here, or Extract to folder. Password-protected files will ask.",
          action: "extractAll:", kw: "giai nen extract unzip zip rar 7z", common: true),
        t("compressPassword", "Nén có đặt mật khẩu", "Compress with a password",
          "Chuột phải › Nén thành › Nén có đặt mật khẩu…, nhập mật khẩu hai lần. Mặc định mã hóa AES-256.",
          "Right-click › Compress to › Compress with password…, enter it twice. AES-256 by default.",
          action: "compressWithPassword:", kw: "nen mat khau password zip encrypt"),
        t("tabs", "Mở nhiều tab", "Use tabs",
          "Cmd+T mở tab mới, Cmd+W đóng tab, Ctrl+Tab chuyển tab. Chuột phải thư mục › Mở trong tab mới.",
          "Cmd+T new tab, Cmd+W close tab, Ctrl+Tab switch. Right-click a folder › Open in new tab.",
          action: "newTab:", kw: "tab moi new tab"),
        t("views", "Đổi chế độ xem", "Change the view",
          "Nút Xem trên thanh lệnh, hoặc Ctrl+Shift+1…8: biểu tượng cực lớn… nội dung. Mỗi thư mục nhớ chế độ xem riêng.",
          "View button on the command bar, or Ctrl+Shift+1…8. Each folder remembers its own view.",
          steps: [("view", "Bấm nút Xem để chọn chế độ", "Click View to choose a layout")], kw: "che do xem icon chi tiet view layout"),
        t("hidden", "Hiện tệp ẩn", "Show hidden files",
          "Cmd+Shift+. hoặc Xem › Hiện › Mục ẩn.", "Cmd+Shift+. or View › Show › Hidden items.",
          action: "toggleHidden:", kw: "an hidden dot file"),
        t("preview", "Xem trước tệp", "Preview files",
          "Bấm phím cách để xem nhanh. Option+P bật ngăn xem trước bên phải; Option+Shift+P bật ngăn chi tiết.",
          "Press Space for Quick Look. Option+P shows the preview pane; Option+Shift+P shows the details pane.",
          action: "togglePreviewPane:", kw: "xem truoc preview quick look"),
        t("search", "Tìm tệp", "Find files",
          "Cmd+F hoặc bấm ô tìm kiếm góc phải. Tìm cả thư mục con, không phân biệt dấu.",
          "Cmd+F or click the search box. Includes subfolders, ignores accents.",
          action: "focusSearch:", steps: [("search", "Gõ tên tệp vào đây", "Type the file name here")], kw: "tim kiem search find"),
        t("theme", "Đổi giao diện Sáng/Tối", "Switch Light/Dark",
          "Bấm nút ☀/☾ ở thanh trạng thái, hoặc Cmd+Shift+L.", "Click ☀/☾ in the status bar, or Cmd+Shift+L.",
          action: "toggleTheme:", steps: [("theme", "Bấm nút này để đổi", "Click this button")], kw: "sang toi dark light theme mau"),
        t("language", "Đổi ngôn ngữ Việt/Anh", "Switch Vietnamese/English",
          "Bấm VI/EN ở góc phải thanh trạng thái. Đổi ngay, không cần mở lại.", "Click VI/EN in the status bar. Changes immediately.",
          action: "toggleLanguage:", steps: [("language", "Bấm vào đây", "Click here")], kw: "ngon ngu language tieng anh english"),
        t("properties", "Xem thuộc tính, dung lượng thư mục", "See properties and folder size",
          "Option+Enter hoặc chuột phải › Thuộc tính. Có kích thước, kích thước trên ổ, ngày tạo, chỉ đọc, ẩn.",
          "Option+Enter or right-click › Properties. Shows size, size on disk, dates, read-only, hidden.",
          action: "showInfo:", kw: "thuoc tinh properties dung luong size"),
        t("cmdE", "Mở Mac Mfile từ bất kỳ đâu", "Open Mac Mfile from anywhere",
          "Bấm Cmd+E (như Windows+E). Đổi phím trong Cài đặt phím tắt.", "Press Cmd+E (like Windows+E). Change it in Shortcut settings.",
          kw: "cmd e win e mo nhanh"),
        t("windowsUsers", "Hướng dẫn nhanh cho người dùng Windows", "Quick guide for Windows users",
          "Ctrl → Cmd (hoặc bật “Dùng Ctrl như Windows”), Windows+E → Cmd+E, F2 đổi tên, F5 làm mới, Alt+Enter → Option+Enter, Delete → ⌫, Shift+Delete xóa vĩnh viễn, Windows+←/→ → Cmd+←/→.",
          "Ctrl → Cmd (or turn on “Use Ctrl like Windows”), Win+E → Cmd+E, F2 rename, F5 refresh, Alt+Enter → Option+Enter, Delete → ⌫, Shift+Delete deletes permanently, Win+←/→ → Cmd+←/→.",
          kw: "windows nguoi dung moi ctrl"),
    ]

    public static func topic(_ id: String) -> HelpTopic? { all.first { $0.id == id } }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// Tìm theo mọi từ đã gõ, không phân biệt dấu; tiêu đề khớp xếp trước.
    public static func search(_ query: String, lang: AppLanguage = L10n.current) -> [HelpTopic] {
        let words = fold(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return all.filter(\.common) }
        let scored: [(HelpTopic, Int)] = all.compactMap { tp in
            let title = fold(tp.title.vi + " " + tp.title.en)
            let hay = title + " " + fold(tp.body.vi + " " + tp.body.en + " " + tp.keywords)
            guard words.allSatisfy({ hay.contains($0) }) else { return nil }
            return (tp, words.filter { title.contains($0) }.count)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Mẹo khi mở (bảng 24).
    public static let tips: [(vi: String, en: String, title: (String, String), action: String?)] = [
        ("Bấm Cmd+1 đến Cmd+9 để mở ngay mục ghim thứ 1 đến 9 trên ngăn bên trái.", "Press Cmd+1 to Cmd+9 to open pinned items 1 to 9.", ("Mở nhanh thư mục đã ghim", "Open pinned folders fast"), nil),
        ("Dán đường dẫn vào thanh địa chỉ rồi Enter để đi thẳng tới thư mục.", "Paste a path in the address bar and press Enter.", ("Dán đường dẫn để mở", "Paste a path to go"), "focusAddress:"),
        ("Cmd+Shift+C sao chép đường dẫn tệp đang chọn, có sẵn ngoặc kép.", "Cmd+Shift+C copies the selected file's path, quoted.", ("Sao chép đường dẫn", "Copy as path"), "copyPath:"),
        ("Cmd+← / Cmd+→ xếp cửa sổ nửa màn hình như Windows.", "Cmd+← / Cmd+→ snaps the window like Windows.", ("Xếp cửa sổ", "Snap windows"), "snapLeft:"),
        ("Phím cách xem nhanh tệp mà không cần mở.", "Press Space to preview a file without opening it.", ("Xem nhanh", "Quick look"), nil),
        ("F1 mở Hướng dẫn sử dụng; gõ câu hỏi bằng tiếng Việt không dấu cũng được.", "F1 opens the user guide; search works without accents.", ("Hướng dẫn luôn sẵn", "Help is always there"), "showHelp:"),
        ("Nút ☀/☾ ở thanh trạng thái đổi nhanh giao diện Sáng/Tối.", "The ☀/☾ button switches Light/Dark.", ("Sáng hay tối", "Light or dark"), "toggleTheme:"),
    ]
}
