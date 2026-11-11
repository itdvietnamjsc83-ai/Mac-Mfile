import Foundation
import CoreServices
import MfileCore

/// Tự xóa thông tin cá nhân khi có ảnh/PDF mới được lưu vào các thư mục chọn sẵn (Mục 5.11, cài trong Tùy chọn).
final class AutoCleanWatcher {
    static let shared = AutoCleanWatcher()
    static let foldersKey = "MacMfile.autoCleanFolders"
    static let changed = Notification.Name("MacMfile.autoCleanChanged")

    private var stream: FSEventStreamRef?
    private var recentlyCleaned: [String: Date] = [:]
    private let queue = DispatchQueue(label: "vn.macmfile.autoclean")

    static var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: foldersKey) ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: foldersKey)
            shared.restart()
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    func restart() {
        stop()
        let paths = Self.folders.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, eventPaths, flags, _ in
            guard let info = info else { return }
            let me = Unmanaged<AutoCleanWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            for i in 0..<min(count, list.count) {
                let f = flags[i]
                let isFile = f & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
                let touched = f & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemRenamed) != 0
                if isFile && touched { me.handle(list[i]) }
            }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func handle(_ path: String) {
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix("."), MetadataCleaner.canClean(path), FileManager.default.fileExists(atPath: path) else { return }
        // Bỏ qua sự kiện do chính lần làm sạch vừa rồi sinh ra.
        if let t = recentlyCleaned[path], Date().timeIntervalSince(t) < 5 { return }
        recentlyCleaned[path] = Date()
        // Chờ ứng dụng khác ghi xong tệp.
        queue.asyncAfter(deadline: .now() + 1.5) {
            try? MetadataCleaner.cleanInPlace(path)
            self.recentlyCleaned[path] = Date()
        }
    }
}
