import Foundation

enum LayerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case title, input, button, setting, label, toggle

    static let catalog: [Self] = [.title, .input, .button, .setting]
    var id: Self { self }

    var name: String {
        switch self {
        case .title: "标题"
        case .input: "输入框"
        case .button: "按钮"
        case .setting: "设置项"
        case .label: "标签"
        case .toggle: "开关"
        }
    }

    var symbol: String {
        switch self {
        case .title: "textformat.size"
        case .input: "character.textbox"
        case .button: "rectangle"
        case .setting: "slider.horizontal.3"
        case .label: "textformat"
        case .toggle: "switch.2"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .title: CGSize(width: 240, height: 44)
        case .input: CGSize(width: 256, height: 48)
        case .button: CGSize(width: 144, height: 48)
        case .setting: CGSize(width: 288, height: 56)
        case .label: CGSize(width: 80, height: 44)
        case .toggle: CGSize(width: 52, height: 44)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .setting: CGSize(width: 116, height: 44)
        case .input, .button: CGSize(width: 44, height: 44)
        case .title: CGSize(width: 44, height: 28)
        case .label, .toggle: defaultSize
        }
    }

    var editsText: Bool { self != .setting && self != .toggle }
}

struct DesignLayer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: LayerKind
    var text: String
    var frame: CGRect
    var spacing: CGFloat = 12
    var isOn = false
    var children: [Self] = []

    var name: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.name : text
    }

    init(kind: LayerKind, frame: CGRect = .zero) {
        id = UUID()
        self.kind = kind
        self.frame = frame
        text = switch kind {
        case .input: "请输入"
        case .button: "继续"
        case .label: "消息通知"
        case .title: "标题"
        case .setting, .toggle: ""
        }
        if kind == .setting {
            children = [Self(kind: .label), Self(kind: .toggle)]
            children[1].isOn = true
        }
    }

    var maximumSpacing: CGFloat { max(0, min(96, frame.width - 108)) }

    func childFrame(_ child: Self, in group: CGRect, spacing: CGFloat? = nil) -> CGRect {
        let toggle = LayerKind.toggle.defaultSize.width
        let gap = min(spacing ?? self.spacing, max(0, min(96, group.width - 108)))
        let x = child.kind == .toggle ? group.maxX - 12 - toggle : group.minX + 12
        let width = child.kind == .toggle ? toggle : group.width - 24 - toggle - gap
        return CGRect(x: x, y: group.minY, width: width, height: group.height)
    }
}

struct DesignPage: Codable, Equatable, Sendable {
    let id: UUID
    var title = "页面 1"
    var device = ReviewDevice.phone
    var layers: [DesignLayer] = []

    init(id: UUID = UUID()) { self.id = id }

    var bounds: CGRect { CGRect(origin: .zero, size: device.size) }

    func selection(_ id: UUID?) -> (layer: DesignLayer, parent: DesignLayer?)? {
        guard let id else { return nil }
        for layer in layers {
            if layer.id == id { return (layer, nil) }
            if let child = layer.children.first(where: { $0.id == id }) { return (child, layer) }
        }
        return nil
    }

    mutating func update(_ id: UUID, _ change: (inout DesignLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == id || $0.children.contains { $0.id == id } }) else { return }
        if layers[index].id == id {
            change(&layers[index])
        } else if let child = layers[index].children.firstIndex(where: { $0.id == id }) {
            change(&layers[index].children[child])
        }
    }

    func constrain(_ proposed: CGRect, kind: LayerKind) -> CGRect {
        let width = min(max(proposed.width, kind.minimumSize.width), bounds.width)
        let height = min(max(proposed.height, kind.minimumSize.height), bounds.height)
        return CGRect(
            x: min(max(proposed.origin.x, 0), bounds.width - width),
            y: min(max(proposed.origin.y, 0), bounds.height - height),
            width: width, height: height
        )
    }
}

struct DesignProject: Codable, Equatable, Sendable {
    static let currentVersion = 1
    private(set) var version = Self.currentVersion
    var page = DesignPage()

    func validated() throws -> Self {
        guard version == Self.currentVersion else { throw DesignFileError.unsupportedVersion(version) }
        var ids: Set<UUID> = [page.id]
        for layer in page.layers {
            guard ids.insert(layer.id).inserted,
                  LayerKind.catalog.contains(layer.kind),
                  [layer.frame.origin.x, layer.frame.origin.y, layer.frame.width, layer.frame.height, layer.spacing]
                    .allSatisfy(\.isFinite),
                  layer.frame.width >= layer.kind.minimumSize.width,
                  layer.frame.height >= layer.kind.minimumSize.height,
                  layer.frame.minX >= 0, layer.frame.minY >= 0,
                  layer.frame.maxX <= page.bounds.width, layer.frame.maxY <= page.bounds.height,
                  layer.kind == .setting
                    ? layer.children.map(\.kind) == [.label, .toggle] && (0...layer.maximumSpacing).contains(layer.spacing)
                    : layer.children.isEmpty else { throw DesignFileError.invalidLayers }
            for child in layer.children {
                guard ids.insert(child.id).inserted, child.children.isEmpty, child.frame == .zero else {
                    throw DesignFileError.invalidLayers
                }
            }
        }
        return self
    }
}

enum DesignFileError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidLayers
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "此项目使用版本 \(version) 的文件格式"
        case .invalidLayers: "项目包含无效的图层或坐标"
        case .unreadable: "无法读取项目文件"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedVersion: "请用支持该格式的 UI Design 版本打开"
        case .invalidLayers, .unreadable: "请尝试打开原始项目或可用的备份"
        }
    }
}
