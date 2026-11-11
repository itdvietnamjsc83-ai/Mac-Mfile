import AppKit
import Darwin
import MfileCore

/// Sao chép / di chuyển chạy nền, có hộp trùng tên và cửa sổ tiến trình (Tạm dừng, Hủy) như Windows (Mục 5.10).
final class FileOperation {
    enum Resolution { case replace, skip, keepBoth, merge }

    let sources: [String]
    let dest: String
    let move: Bool
    /// Gọi trên luồng chính khi xong, kèm các đường dẫn đích đã tạo.
    var completion: (([String], String?) -> Void)?

    fileprivate(set) var stats = TransferStats()
    private(set) var currentName = ""
    fileprivate var cancelled = false
    private var paused = false
    private let pauseLock = NSCondition()
    private var rememberedFile: Resolution?
    private var rememberedFolder: Resolution?
    private var results: [String] = []
    private var errorText: String?
    private var progress: ProgressWindowController?
    private static var running: [FileOperation] = []

    init(sources: [String], dest: String, move: Bool) {
        self.sources = sources
        self.dest = dest
        self.move = move
    }

    func start() {
        Self.running.append(self)
        // Windows chỉ hiện hộp tiến trình khi thao tác kéo dài.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, Self.running.contains(where: { $0 === self }) else { return }
            self.progress = ProgressWindowController(op: self)
            self.progress?.showWindow(nil)
        }
        DispatchQueue.global(qos: .userInitiated).async { self.run() }
    }

    var isPaused: Bool { paused }
    func togglePause() {
        pauseLock.lock()
        paused.toggle()
        pauseLock.broadcast()
        pauseLock.unlock()
    }
    func cancel() {
        cancelled = true
        if paused { togglePause() }
    }

    fileprivate func waitIfPaused() {
        pauseLock.lock()
        while paused && !cancelled { pauseLock.wait() }
        pauseLock.unlock()
    }

    // MARK: Chạy

    private func run() {
        let fm = FileManager.default
        // Lập kế hoạch: tổng dung lượng và số mục để tính phần trăm.
        for s in sources {
            if cancelled { break }
            let (b, n) = Self.measure(s)
            stats.totalBytes += b
            stats.totalItems += n
        }
        let (tb, ti) = (stats.totalBytes, stats.totalItems)
        stats = TransferStats()
        stats.totalBytes = tb
        stats.totalItems = ti
        for src in sources {
            if cancelled { break }
            let name = (src as NSString).lastPathComponent
            let parent = (src as NSString).deletingLastPathComponent
            if move && (parent == dest || dest == src || dest.hasPrefix(src + "/")) { continue }
            var target = (dest as NSString).appendingPathComponent(name)
            if !move && parent == dest {
                // Dán vào chính thư mục nguồn: tạo "… - Bản sao" như Windows, không hỏi.
                target = (dest as NSString).appendingPathComponent(FileNaming.copyName(name) { fm.fileExists(atPath: (dest as NSString).appendingPathComponent($0)) })
            }
            if let out = transferItem(src, to: target, topLevel: true) { results.append(out) }
            if errorText != nil { break }
        }
        DispatchQueue.main.async {
            Self.running.removeAll { $0 === self }
            self.progress?.close()
            self.completion?(self.results, self.cancelled ? L10n.t("operationCancelled") : self.errorText)
        }
    }

    /// Trả về đường dẫn đích nếu đã xử lý.
    private func transferItem(_ src: String, to target: String, topLevel: Bool) -> String? {
        let fm = FileManager.default
        var target = target
        var srcIsDir: ObjCBool = false
        fm.fileExists(atPath: src, isDirectory: &srcIsDir)
        var dstIsDir: ObjCBool = false
        if fm.fileExists(atPath: target, isDirectory: &dstIsDir) {
            let folders = srcIsDir.boolValue && dstIsDir.boolValue
            let r = resolve(src: src, existing: target, folders: folders)
            switch r {
            case .skip:
                stats.doneBytes += Self.measure(src).0
                stats.doneItems += Self.measure(src).1
                return nil
            case .keepBoth:
                let dir = (target as NSString).deletingLastPathComponent
                target = (dir as NSString).appendingPathComponent(FileNaming.keepBothName((target as NSString).lastPathComponent) { fm.fileExists(atPath: (dir as NSString).appendingPathComponent($0)) })
            case .merge:
                let children = (try? fm.contentsOfDirectory(atPath: src)) ?? []
                for c in children {
                    if cancelled || errorText != nil { break }
                    _ = transferItem((src as NSString).appendingPathComponent(c), to: (target as NSString).appendingPathComponent(c), topLevel: false)
                }
                stats.doneItems += 1
                if move, ((try? fm.contentsOfDirectory(atPath: src)) ?? []).isEmpty { try? fm.removeItem(atPath: src) }
                return target
            case .replace:
                do { try fm.trashItem(at: URL(fileURLWithPath: target), resultingItemURL: nil) }
                catch { try? fm.removeItem(atPath: target) }
            }
        }
        currentName = (src as NSString).lastPathComponent
        if move, sameVolume(src, (target as NSString).deletingLastPathComponent) {
            // Cùng ổ: đổi chỗ tức thì như Windows.
            do {
                try fm.moveItem(atPath: src, toPath: target)
                let (b, n) = Self.measure(target)
                stats.doneBytes += b
                stats.doneItems += n
                return target
            } catch { errorText = error.localizedDescription; return nil }
        }
        guard copyTree(src, to: target) else {
            if !cancelled && errorText == nil { errorText = L10n.f("cleanFailed", currentName) }
            try? fm.removeItem(atPath: target)
            return nil
        }
        if move { try? fm.removeItem(atPath: src) }
        return target
    }

    private func copyTree(_ src: String, to dst: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src, isDirectory: &isDir)
        if isDir.boolValue && !isSymlink(src) {
            do { try fm.createDirectory(atPath: dst, withIntermediateDirectories: false) }
            catch { errorText = error.localizedDescription; return false }
            stats.doneItems += 1
            for c in (try? fm.contentsOfDirectory(atPath: src)) ?? [] {
                if cancelled { return false }
                guard copyTree((src as NSString).appendingPathComponent(c), to: (dst as NSString).appendingPathComponent(c)) else { return false }
            }
            _ = copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_METADATA))
            return true
        }
        return copyFile(src, to: dst)
    }

    /// copyfile() với callback tiến trình: chặn trong callback để tạm dừng, trả QUIT để hủy.
    private func copyFile(_ src: String, to dst: String) -> Bool {
        currentName = (src as NSString).lastPathComponent
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let box = CopyProgressBox()
        box.op = self
        let cb: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx = ctx else { return COPYFILE_CONTINUE }
            let box = Unmanaged<CopyProgressBox>.fromOpaque(ctx).takeUnretainedValue()
            guard let op = box.op else { return COPYFILE_QUIT }
            if op.cancelled { return COPYFILE_QUIT }
            op.waitIfPaused()
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                op.stats.doneBytes += Int64(copied) - box.last
                box.last = Int64(copied)
            }
            return op.cancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(cb, to: UnsafeRawPointer.self))
        let ctx = Unmanaged.passRetained(box)
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), ctx.toOpaque())
        let r = copyfile(src, dst, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC))
        ctx.release()
        let size = (try? FileManager.default.attributesOfItem(atPath: src))?[.size] as? Int64 ?? 0
        stats.doneBytes += max(0, size - box.last)
        stats.doneItems += 1
        if r != 0 && !cancelled { errorText = String(cString: strerror(errno)) }
        return r == 0
    }

    private func isSymlink(_ p: String) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: p))?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private func sameVolume(_ a: String, _ b: String) -> Bool {
        let k: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let x = try? URL(fileURLWithPath: a).resourceValues(forKeys: k).volumeIdentifier as? NSObject,
              let y = try? URL(fileURLWithPath: b).resourceValues(forKeys: k).volumeIdentifier as? NSObject else { return false }
        return x.isEqual(y)
    }

    static func measure(_ path: String) -> (Int64, Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue { return (((try? fm.attributesOfItem(atPath: path))?[.size] as? Int64) ?? 0, 1) }
        var bytes: Int64 = 0, n = 1
        let e = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
        while let u = e?.nextObject() as? URL {
            bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            n += 1
        }
        return (bytes, n)
    }

    // MARK: Hộp trùng tên

    private func resolve(src: String, existing: String, folders: Bool) -> Resolution {
        if folders, let r = rememberedFolder { return r }
        if !folders, let r = rememberedFile { return r }
        var result = Resolution.skip
        var all = false
        DispatchQueue.main.sync {
            let fm = FileManager.default
            let name = (existing as NSString).lastPathComponent
            let a = NSAlert()
            a.messageText = L10n.t("conflictTitle")
            a.alertStyle = .warning
            func info(_ p: String) -> (String, String) {
                let at = (try? fm.attributesOfItem(atPath: p)) ?? [:]
                let size = folders ? "" : Formatting.size(at[.size] as? Int64 ?? 0)
                return (size, (at[.modificationDate] as? Date).map { Formatting.date($0) } ?? "")
            }
            let (s1, d1) = info(src), (s2, d2) = info(existing)
            a.informativeText = (folders ? L10n.f("conflictFolderInfo", name) : L10n.f("conflictInfo", name))
                + "\n\n" + L10n.f("fromFile", s1, d1) + "\n" + L10n.f("toFile", s2, d2)
            a.icon = NSWorkspace.shared.icon(forFile: src)
            a.addButton(withTitle: L10n.t(folders ? "mergeFolder" : "replaceFile"))
            a.addButton(withTitle: L10n.t("skipFile"))
            a.addButton(withTitle: L10n.t("keepBoth"))
            a.showsSuppressionButton = true
            a.suppressionButton?.title = L10n.t("applyToAll")
            progress?.window?.orderFront(nil)
            switch a.runModal() {
            case .alertFirstButtonReturn: result = folders ? .merge : .replace
            case .alertThirdButtonReturn: result = .keepBoth
            default: result = .skip
            }
            all = a.suppressionButton?.state == .on
        }
        if all { if folders { rememberedFolder = result } else { rememberedFile = result } }
        return result
    }
}

private final class CopyProgressBox {
    weak var op: FileOperation?
    var last: Int64 = 0
}

/// Cửa sổ tiến trình kiểu Windows: tiêu đề, % hoàn tất, thanh tiến trình, Tạm dừng / Hủy, Thêm chi tiết.
final class ProgressWindowController: NSWindowController, NSWindowDelegate {
    private weak var op: FileOperation?
    private let titleL = label("")
    private let percentL = label("", size: 15)
    private let bar = NSProgressIndicator()
    private let detail = label("", color: Theme.secondaryText)
    private let pauseB = NSButton(title: "", target: nil, action: nil)
    private let moreB = NSButton(title: "", target: nil, action: nil)
    private var timer: Timer?
    private var showMore = false
    private let summary: String

    init(op: FileOperation) {
        self.op = op
        let from = Breadcrumb.crumbs(for: (op.sources.first.map { ($0 as NSString).deletingLastPathComponent }) ?? "/").last?.title ?? ""
        let to = Breadcrumb.crumbs(for: op.dest).last?.title ?? ""
        summary = L10n.f(op.move ? "movingItems" : "copyingItems", op.sources.count, from, to)
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 170), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
        w.center()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let c = window?.contentView else { return }
        titleL.maximumNumberOfLines = 2
        titleL.lineBreakMode = .byTruncatingMiddle
        percentL.font = Theme.font(15, weight: .semibold)
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.style = .bar
        bar.translatesAutoresizingMaskIntoConstraints = false
        detail.maximumNumberOfLines = 4
        detail.lineBreakMode = .byWordWrapping
        pauseB.target = self
        pauseB.action = #selector(pauseResume)
        let cancelB = NSButton(title: L10n.t("cancel"), target: self, action: #selector(cancelOp))
        moreB.target = self
        moreB.action = #selector(toggleMore)
        moreB.bezelStyle = .disclosure
        moreB.setButtonType(.pushOnPushOff)
        moreB.title = ""
        let moreLabel = label(L10n.t("moreDetails"))
        let bottom = NSStackView(views: [moreB, moreLabel, NSView(), pauseB, cancelB])
        bottom.spacing = 6
        let stack = NSStackView(views: [titleL, percentL, bar, detail, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: c.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: c.bottomAnchor, constant: -12),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleL.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
        detail.isHidden = true
    }

    private func tick() {
        guard let op = op else { return }
        let s = op.stats
        let pct = Int((s.fraction * 100).rounded(.down))
        window?.title = L10n.f("percentComplete", pct)
        titleL.stringValue = summary
        percentL.stringValue = op.isPaused ? L10n.t("paused") : L10n.f("percentComplete", pct)
        bar.doubleValue = s.fraction
        pauseB.title = L10n.t(op.isPaused ? "resume" : "pause")
        var lines = [L10n.t("nameLabel") + ": " + op.currentName]
        if let r = s.secondsRemaining() { lines.append(L10n.t("timeRemaining") + ": " + TransferStats.describe(seconds: r)) }
        lines.append(L10n.t("itemsRemaining") + ": " + "\(max(0, s.totalItems - s.doneItems)) (\(Formatting.size(max(0, s.totalBytes - s.doneBytes))))")
        lines.append(L10n.t("speed") + ": " + Formatting.size(Int64(s.bytesPerSecond())) + "/s")
        detail.stringValue = lines.joined(separator: "\n")
    }

    @objc private func pauseResume() { op?.togglePause(); tick() }
    @objc private func cancelOp() { op?.cancel() }
    @objc private func toggleMore() {
        showMore.toggle()
        detail.isHidden = !showMore
        if let w = window {
            var f = w.frame
            let h: CGFloat = showMore ? 250 : 170
            f.origin.y += f.height - h
            f.size.height = h
            w.setFrame(f, display: true, animate: true)
        }
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Đóng bằng nút X khi đang chạy nghĩa là Hủy, như Windows.
        op?.cancel()
        return true
    }
    override func close() { timer?.invalidate(); super.close() }
}
