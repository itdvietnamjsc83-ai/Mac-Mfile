import Foundation

/// 8 chế độ xem như Windows 11 (FR-06, Mục 5.2), kèm phím Cmd+Shift+1…8 (Windows: Ctrl+Shift+1…8).
public enum ViewMode: String, CaseIterable, Sendable {
    case extraLargeIcons, largeIcons, mediumIcons, smallIcons, list, details, tiles, content

    public var titleKey: String { "view_" + rawValue }

    /// Kích thước biểu tượng (điểm).
    public var iconSize: Double {
        switch self {
        case .extraLargeIcons: return 160
        case .largeIcons: return 96
        case .mediumIcons: return 48
        case .smallIcons, .list, .details: return 16
        case .tiles: return 48
        case .content: return 32
        }
    }

    /// Kích thước một ô (rộng, cao); rộng 0 nghĩa là chiếm hết chiều ngang.
    public func itemSize(compact: Bool) -> (width: Double, height: Double) {
        let row: Double = compact ? 24 : 28
        switch self {
        case .extraLargeIcons: return (190, 212)
        case .largeIcons: return (124, 140)
        case .mediumIcons: return (96, 92)
        case .smallIcons, .list: return (240, row)
        case .details: return (0, compact ? 24 : 32)
        case .tiles: return (300, compact ? 60 : 68)
        case .content: return (0, compact ? 48 : 56)
        }
    }

    /// Danh sách xếp theo cột (cuộn ngang), giống Windows.
    public var flowsInColumns: Bool { self == .list }

    public var showsLabelBelowIcon: Bool {
        self == .extraLargeIcons || self == .largeIcons || self == .mediumIcons
    }
}

/// Ghi nhớ chế độ xem cho từng thư mục (FR-21).
public struct ViewPreferences {
    public var defaultMode: ViewMode = .details
    public var perFolder: [String: String] = [:]

    public init(defaultMode: ViewMode = .details, perFolder: [String: String] = [:]) {
        self.defaultMode = defaultMode
        self.perFolder = perFolder
    }

    public func mode(for path: String) -> ViewMode {
        perFolder[path].flatMap(ViewMode.init(rawValue:)) ?? defaultMode
    }

    public mutating func set(_ mode: ViewMode, for path: String) {
        perFolder[path] = mode.rawValue
    }
}
