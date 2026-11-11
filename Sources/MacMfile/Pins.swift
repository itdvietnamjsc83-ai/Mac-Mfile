import Foundation

/// Danh sách mục ghim trên Truy nhập nhanh (FR-13/27/49, Mục 5.12). Lưu lại khi mở lại ứng dụng.
enum Pins {
    static let didChange = Notification.Name("MacMfile.pinsDidChange")
    private static let key = "MacMfile.pins"

    static var defaults: [String] {
        let home = NSHomeDirectory()
        return ["Desktop", "Downloads", "Documents", "Pictures", "Music", "Movies"].map { home + "/" + $0 }
    }

    static var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? defaults }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func pin(_ path: String) {
        var list = all
        guard !list.contains(path) else { return }
        list.append(path)
        all = list
    }

    static func unpin(_ path: String) {
        all = all.filter { $0 != path }
    }

    static func move(from: Int, to: Int) {
        var list = all
        guard list.indices.contains(from) else { return }
        let p = list.remove(at: from)
        list.insert(p, at: min(max(0, to), list.count))
        all = list
    }
}
