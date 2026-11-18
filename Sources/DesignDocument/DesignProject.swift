import Foundation

enum LayerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case title, input, button, setting, label, toggle, contactList
    case layout, image, divider, labeledInput, listRow, actionBar

    static let sections: [(String, [Self])] = [
        ("布局", [.layout, .divider]),
        ("文字与媒体", [.title, .label, .image]),
        ("输入与操作", [.input, .toggle, .button, .labeledInput, .setting]),
        ("导航与反馈", [.listRow, .contactList, .actionBar])
    ]
    static let catalog = sections.flatMap(\.1)
    var isContainer: Bool { [.layout, .labeledInput, .listRow, .actionBar].contains(self) }
    var id: Self { self }

    var name: String {
        switch self {
        case .title: "标题"
        case .input: "输入框"
        case .button: "按钮"
        case .setting: "设置项"
        case .label: "标签"
        case .toggle: "开关"
        case .contactList: "联系人列表"
        case .layout: "布局容器"
        case .image: "图片"
        case .divider: "分隔线"
        case .labeledInput: "带标签输入框"
        case .listRow: "列表行"
        case .actionBar: "操作栏"
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
        case .contactList: "list.bullet"
        case .layout: "rectangle.3.group"
        case .image: "photo"
        case .divider: "minus"
        case .labeledInput: "text.below.photo"
        case .listRow: "list.bullet.rectangle"
        case .actionBar: "rectangle.bottomthird.inset.filled"
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
        case .contactList: CGSize(width: 320, height: 168)
        case .layout: CGSize(width: 320, height: 120)
        case .image: CGSize(width: 144, height: 112)
        case .divider: CGSize(width: 256, height: 1)
        case .labeledInput: CGSize(width: 288, height: 76)
        case .listRow: CGSize(width: 288, height: 48)
        case .actionBar: CGSize(width: 288, height: 48)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .setting: CGSize(width: 116, height: 44)
        case .input, .button: CGSize(width: 44, height: 44)
        case .title: CGSize(width: 44, height: 28)
        case .label: CGSize(width: 44, height: 24)
        case .toggle: defaultSize
        case .contactList: CGSize(width: 120, height: 56)
        case .layout: CGSize(width: 44, height: 4)
        case .image: CGSize(width: 44, height: 44)
        case .divider: CGSize(width: 4, height: 1)
        case .labeledInput: CGSize(width: 44, height: 4)
        case .listRow: CGSize(width: 44, height: 4)
        case .actionBar: CGSize(width: 44, height: 4)
        }
    }

    var hasAction: Bool { [.button, .listRow, .contactList].contains(self) }

    var editsText: Bool { [.title, .input, .button, .label, .image].contains(self) }
}

struct DesignLayer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: LayerKind
    var text: String
    var frame: CGRect
    var spacing: CGFloat = 12
    var isOn = false
    var children: [Self] = []
    var field: ContactField?
    var destination: UUID?
    var savesContact: Bool?
    var geometry: LayerGeometry?
    var deviceLayouts: [String: LayerGeometry]?
    var styleID: UUID?
    var cornerRadius: CGFloat?
    var inputType: DesignInputType?
    var fieldHint: String?
    var secondaryButton: Bool?
    var image: Data?
    var behavior: LayerBehavior?

    var descendants: [Self] { [self] + children.flatMap(\.descendants) }

    func placement(for device: DeviceLayout?) -> LayerGeometry {
        (geometry ?? LayerGeometry()).applying(device.flatMap { deviceLayouts?[$0.rawValue] })
    }

    mutating func editPlacement(for device: DeviceLayout?, _ change: (inout LayerGeometry) -> Void) {
        guard let device else {
            var placement = geometry ?? LayerGeometry()
            change(&placement)
            geometry = placement
            return
        }
        var overrides = deviceLayouts ?? [:]
        var placement = overrides[device.rawValue] ?? LayerGeometry()
        change(&placement)
        overrides[device.rawValue] = placement
        deviceLayouts = overrides
    }

    mutating func update(_ id: UUID, _ change: (inout Self) -> Void) {
        if self.id == id { change(&self) }
        else {
            for index in children.indices { children[index].update(id, change) }
        }
    }

    func selection(_ id: UUID, parent: Self? = nil) -> (layer: Self, parent: Self?)? {
        if self.id == id { return (self, parent) }
        return children.lazy.compactMap { $0.selection(id, parent: self) }.first
    }

    mutating func remove(_ id: UUID) {
        children.removeAll { $0.id == id }
        let key = id.uuidString
        geometry?.order?.removeAll { $0 == key }
        if let layouts = deviceLayouts {
            deviceLayouts = layouts.mapValues {
                var placement = $0
                placement.order?.removeAll { $0 == key }
                return placement
            }
        }
        for index in children.indices { children[index].remove(id) }
    }

    func duplicate() -> Self {
        var copy = Self(id: UUID(), from: self)
        copy.children = children.map { $0.duplicate() }
        let identifiers = Dictionary(uniqueKeysWithValues: zip(children.map { $0.id.uuidString }, copy.children.map { $0.id.uuidString }))
        func order(_ ids: [String]?) -> [String]? { ids.map { $0.compactMap { identifiers[$0] } } }
        copy.geometry?.order = order(geometry?.order)
        copy.deviceLayouts = deviceLayouts?.mapValues { value in
            var placement = value
            placement.order = order(value.order)
            return placement
        }
        return copy
    }

    private init(id: UUID, from layer: Self) {
        self.id = id
        kind = layer.kind
        text = layer.text
        frame = layer.frame
        spacing = layer.spacing
        isOn = layer.isOn
        children = layer.children
        field = layer.field
        destination = layer.destination
        savesContact = layer.savesContact
        geometry = layer.geometry
        deviceLayouts = layer.deviceLayouts
        styleID = layer.styleID
        cornerRadius = layer.cornerRadius
        inputType = layer.inputType
        fieldHint = layer.fieldHint
        secondaryButton = layer.secondaryButton
        image = layer.image
        behavior = layer.behavior
    }

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
        case .setting, .toggle, .contactList, .layout, .labeledInput, .listRow, .actionBar, .divider, .image: ""
        }
        if kind == .setting {
            children = [Self(kind: .label), Self(kind: .toggle)]
            children[1].isOn = true
        }
        switch kind {
        case .labeledInput:
            children = [Self.part(.label, "字段名称", width: .fill, height: .content),
                        Self.part(.input, "请输入", width: .fill, height: .content)]
            geometry = LayerGeometry(width: .fixed, height: .content, arrangement: .vertical, gap: 4)
        case .listRow:
            children = [Self.part(.label, "列表项", width: .fill, height: .content),
                        Self.part(.label, "›", width: .content, height: .content)]
            geometry = LayerGeometry(width: .fixed, height: .content, arrangement: .horizontal, gap: 12)
        case .actionBar:
            children = [Self.part(.button, "取消", width: .fill), Self.part(.button, "完成", width: .fill)]
            children[0].secondaryButton = true
            geometry = LayerGeometry(width: .fixed, height: .content, arrangement: .horizontal, gap: 12)
        case .layout:
            geometry = LayerGeometry(width: .fixed, height: .content, arrangement: .vertical, gap: 12)
        default: break
        }
    }

    private static func part(_ kind: LayerKind, _ name: String, width: LayoutSizeMode,
                             height: LayoutSizeMode? = nil) -> Self {
        var part = Self(kind: kind, frame: CGRect(origin: .zero, size: kind.defaultSize))
        part.text = name
        part.geometry = LayerGeometry(width: width, height: height)
        return part
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
    var customSize: CGSize?
    var customDeviceLayout: DeviceLayout?
    var reference: ReferenceLayout?
    var referenceImage: ReferenceImage?
    var canvasOrigin: CGPoint?

    static let maximumContentHeight: CGFloat = 24_000
    var size: CGSize { customSize ?? device.size }
    var deviceLayout: DeviceLayout { customDeviceLayout ?? DeviceLayout(width: size.width) }
    var safeTop: CGFloat { deviceLayout == .phone && size.height > size.width ? 56 : 0 }
    var safeBottom: CGFloat { deviceLayout == .phone && size.height > size.width ? 34 : 0 }

    init(id: UUID = UUID()) { self.id = id }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    var allLayers: [DesignLayer] { layers.flatMap(\.descendants) }

    func selection(_ id: UUID?) -> (layer: DesignLayer, parent: DesignLayer?)? {
        guard let id else { return nil }
        return layers.lazy.compactMap { $0.selection(id) }.first
    }

    mutating func update(_ id: UUID, _ change: (inout DesignLayer) -> Void) {
        for index in layers.indices { layers[index].update(id, change) }
    }

    mutating func remove(_ id: UUID) {
        layers.removeAll { $0.id == id }
        for index in layers.indices { layers[index].remove(id) }
    }

    func constrain(_ proposed: CGRect, kind: LayerKind) -> CGRect {
        let width = min(max(proposed.width, kind.minimumSize.width), bounds.width)
        let height = min(max(proposed.height, kind.minimumSize.height), Self.maximumContentHeight)
        return CGRect(
            x: min(max(proposed.minX, 0), bounds.width - width),
            y: min(max(proposed.minY, 0), Self.maximumContentHeight - height),
            width: width, height: height
        )
    }

}

struct DesignProject: Codable, Equatable, Sendable {
    static let currentVersion = 4
    private(set) var version = Self.currentVersion
    var page = DesignPage()
    var additionalPages: [DesignPage]?
    var contacts: [DesignContact]?
    var buttonStyles: [ButtonDesignStyle]?

    var pages: [DesignPage] { [page] + (additionalPages ?? []) }

    func page(withID id: UUID?) -> DesignPage {
        pages.first { $0.id == id } ?? page
    }

    mutating func migrate() throws {
        guard (1...Self.currentVersion).contains(version) else { throw DesignFileError.unsupportedVersion(version) }
        version = Self.currentVersion
    }

    mutating func updatePage(_ id: UUID, _ update: (inout DesignPage) -> Void) {
        if id == page.id {
            update(&page)
        } else if var pages = additionalPages, let index = pages.firstIndex(where: { $0.id == id }) {
            update(&pages[index])
            additionalPages = pages
        }
    }

    mutating func removePage(_ id: UUID) {
        guard pages.count > 1 else { return }
        if page.id == id, let next = additionalPages?.removeFirst() { page = next }
        else { additionalPages?.removeAll { $0.id == id } }
        for pageID in pages.map(\.id) {
            updatePage(pageID) { page in
                for layer in page.allLayers {
                    page.update(layer.id) {
                        if $0.destination == id { $0.destination = nil }
                        if $0.behavior?.action?.target == id.uuidString { $0.behavior?.action = nil }
                        if $0.behavior?.list?.emptyAction?.target == id.uuidString { $0.behavior?.list?.emptyAction = nil }
                    }
                }
            }
        }
    }

    func validated() throws -> Self {
        guard version == Self.currentVersion else { throw DesignFileError.unsupportedVersion(version) }
        let pageIDs = Set(pages.map(\.id))
        var ids = pageIDs
        let contacts = contacts ?? []
        guard pageIDs.count == pages.count,
              Set(contacts.map(\.id)).count == contacts.count else { throw DesignFileError.invalidLayers }
        let styles = buttonStyles ?? []
        let styleIDs = Set(styles.map(\.id))
        guard styleIDs.count == styles.count, styles.allSatisfy({ (44...640).contains($0.height) && (0...48).contains($0.radius) }) else {
            throw DesignFileError.invalidLayers
        }
        for page in pages {
            guard (160...4096).contains(page.size.width), (160...4096).contains(page.size.height),
                  page.canvasOrigin.map({ $0.x.isFinite && $0.y.isFinite }) != false,
                  page.referenceImage?.isValid != false else { throw DesignFileError.invalidLayers }
            for layer in page.layers {
                try validate(layer, parent: nil, page: page.id, ids: &ids, pageIDs: pageIDs, styles: styleIDs)
            }
        }
        return self
    }

    private func actionIsValid(_ action: DesignAction?, page: UUID, pageIDs: Set<UUID>) -> Bool {
        guard let action, action.kind == .navigate || action.kind == .sheet else { return true }
        guard let target = action.target.flatMap(UUID.init(uuidString:)) else { return false }
        return target != page && pageIDs.contains(target)
    }

    private func validate(_ layer: DesignLayer, parent: LayerKind?, page: UUID, ids: inout Set<UUID>,
                          pageIDs: Set<UUID>, styles: Set<UUID>) throws {
        let frame = layer.frame
        let parts = Set(layer.children.map { $0.id.uuidString })
        let overrides = layer.deviceLayouts ?? [:]
        let placements = [layer.geometry].compactMap { $0 } + Array(overrides.values)
        guard ids.insert(layer.id).inserted,
              actionIsValid(layer.behavior?.action, page: page, pageIDs: pageIDs),
              actionIsValid(layer.behavior?.list?.emptyAction, page: page, pageIDs: pageIDs),
              layer.behavior?.list.map({
                  Set($0.sample.rows.map(\.id)).count == $0.sample.rows.count && (44...120).contains($0.rowHeight ?? 56)
              }) != false,
              layer.behavior?.rules.map({ rules in
                  (rules.minimum ?? 0) >= 0 && (rules.maximum ?? Int.max) >= (rules.minimum ?? 0)
              }) != false,
              layer.field == nil || [.title, .input].contains(layer.kind),
              layer.field?.isEditable != false || layer.kind == .title,
              layer.savesContact == nil || layer.kind == .button,
              layer.destination.map({ layer.kind == .contactList && $0 != page && pageIDs.contains($0) }) ?? true,
              layer.styleID.map({ layer.kind == .button && styles.contains($0) }) ?? true,
              layer.cornerRadius.map({ (0...48).contains($0) }) ?? true,
              layer.image.map({ layer.kind == .image && $0.count <= ReferenceImage.maximumBytes }) ?? true,
              (layer.inputType == nil && layer.fieldHint == nil) || layer.kind == .input,
              layer.secondaryButton == nil || layer.kind == .button,
              overrides.keys.allSatisfy({ DeviceLayout(rawValue: $0) != nil }),
              placements.allSatisfy({ spec in
                  spec.isValid && (spec.order.map { Set($0).isSubset(of: parts) } ?? true)
                  && (parent == nil || spec.region == nil || spec.region == .body)
              }),
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ (0...DesignPage.maximumContentHeight).contains($0) }),
              layer.spacing.isFinite else { throw DesignFileError.invalidLayers }
        if parent == .setting {
            guard frame == .zero, layer.children.isEmpty else { throw DesignFileError.invalidLayers }
        } else {
            guard frame.width >= layer.kind.minimumSize.width, frame.height >= layer.kind.minimumSize.height,
                  layer.kind == .setting ? layer.children.map(\.kind) == [.label, .toggle] :
                    layer.kind.isContainer || layer.children.isEmpty else { throw DesignFileError.invalidLayers }
        }
        for child in layer.children {
            try validate(child, parent: layer.kind, page: page, ids: &ids, pageIDs: pageIDs, styles: styles)
        }
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
