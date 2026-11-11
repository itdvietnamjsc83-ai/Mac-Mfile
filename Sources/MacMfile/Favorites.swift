import Foundation

/// Tệp được "Thêm vào Ưa thích" hiện ở Trang chủ (Windows 11: Favorites). Thư mục thì ghim vào Truy nhập nhanh.
enum Favorites {
    static let didChange = Notification.Name("MacMfile.favoritesDidChange")
    private static let key = "MacMfile.favorites"

    static var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func add(_ path: String) { if !all.contains(path) { all.append(path) } }
    static func remove(_ path: String) { all = all.filter { $0 != path } }
    static func contains(_ path: String) -> Bool { all.contains(path) }
}
