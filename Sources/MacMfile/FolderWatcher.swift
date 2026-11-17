import Foundation

/// Theo dõi một thư mục: có tệp mới, đổi tên, xóa (kể cả do ứng dụng khác hay dịch vụ đám mây) thì báo lại
/// để danh sách tự làm mới như File Explorer của Windows. Chỉ theo dõi đúng thư mục đang xem, không đệ quy.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private(set) var path: String?
    /// Gọi trên luồng chính, đã gộp các sự kiện dồn dập trong 0,4 giây.
    var onChange: (() -> Void)?

    func watch(_ newPath: String?) {
        guard newPath != path else { return }
        stop()
        path = newPath
        guard let newPath else { return }
        let fd = open(newPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link, .extend, .attrib], queue: .main)
        s.setEventHandler { [weak self] in self?.schedule() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        path = nil
    }

    private func schedule() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    deinit { stop() }
}
