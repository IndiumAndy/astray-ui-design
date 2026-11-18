import AppKit
import ImageIO
import SwiftUI

@MainActor @Observable
final class DesignEditing {
    private let file: DesignFile
    @ObservationIgnored weak var undoManager: UndoManager?
    private(set) var selectedID: UUID?
    private(set) var enteredGroup: UUID?
    private(set) var textEditor: UUID?
    private(set) var focusRequest = 0
    private var currentPageID: UUID?
    private(set) var additionalSelection: Set<UUID> = []
    var selectedBoards: Set<UUID> = []
    var librarySave: TemplateSaveRequest?
    var libraryIssue: String?
    var usesDeviceLayout = false
    var showsFullPage = false
    var imageIssue: String?
    var referenceOffset: CGPoint?
    var connectionSetup: UUID?
    var overviewRequest = 0

    var scope: DeviceLayout? { usesDeviceLayout ? page.deviceLayout : nil }
    var selectedIDs: Set<UUID> { additionalSelection.union(selectedID.map { [$0] } ?? []) }

    var layout: ScreenLayout {
        ScreenLayout(page: page.runtime(styles: project.buttonStyles ?? [], contacts: project.contacts ?? [], canvas: true),
                     width: page.size.width, height: page.size.height, top: page.safeTop, bottom: page.safeBottom,
                     device: scope)
    }

    func boardSize(using layout: ScreenLayout) -> CGSize {
        CGSize(width: page.size.width, height: showsFullPage
            ? max(page.size.height, page.safeTop + layout.headerHeight + layout.bodyHeight + layout.footerHeight + page.safeBottom)
            : page.size.height)
    }

    func frame(of layer: DesignLayer, using layout: ScreenLayout? = nil) -> CGRect {
        let layout = layout ?? self.layout
        let size = boardSize(using: layout)
        if let frame = layout.artboardFrame(layer.id.uuidString, top: page.safeTop, bottom: page.safeBottom,
                                            height: size.height) { return frame }
        if let parent = page.selection(layer.id)?.parent, parent.kind == .setting {
            return parent.childFrame(layer, in: frame(of: parent, using: layout), spacing: parent.placement(for: scope).gap)
        }
        return layer.frame
    }

    var scopeTitle: String { scope.map { "仅改\($0.title)布局" } ?? "通用布局" }

    var pan = CGPoint.zero
    var magnification: CGFloat?

    init(file: DesignFile) { self.file = file }

    var project: DesignProject { file.project }
    var page: DesignPage { project.page(withID: currentPageID) }
    var selection: (layer: DesignLayer, parent: DesignLayer?)? { page.selection(selectedID) }

    func showPage(_ id: UUID) {
        currentPageID = id
        selectedBoards = []
        textEditor = nil
        select(nil)
        pan = .zero
        showsFullPage = false
        referenceOffset = nil
    }

    func selectBoards(_ ids: Set<UUID>) {
        select(nil)
        selectedBoards = ids
    }

    var selectedTemplateLayers: [DesignLayer] {
        if let selection, let parent = selection.parent {
            var layer = selection.layer
            layer.frame = frame(of: layer)
            layer.geometry?.frame = nil
            if parent.kind == .setting { layer.deviceLayouts = nil }
            return [layer]
        }
        return page.layers.filter { selectedIDs.contains($0.id) }
    }

    func requestLibrarySave(layers: Bool, replacing: PersonalTemplate? = nil) {
        if layers && selectedTemplateLayers.isEmpty { return }
        librarySave = TemplateSaveRequest(layers: layers,
                                          selectedPages: selectedBoards.isEmpty ? [page.id] : selectedBoards,
                                          name: replacing?.name ?? (layers ? selectedTemplateLayers.first?.name ?? "" : page.title),
                                          replacing: replacing?.id)
    }

    func insertTemplate(_ template: PersonalTemplate, at origin: CGPoint? = nil) {
        do {
            let proposed = template.kind.insertsLayers
                ? origin ?? insertionFrame(template.project.page.layers.first?.kind ?? .title).origin
                : nil
            let insertion = try template.instantiate(into: project, pageID: page.id, origin: proposed)
            file.apply(insertion.project, undoManager: undoManager, action: "插入模板")
            if template.kind.insertsLayers {
                select(insertion.layers.first)
                additionalSelection = Set(insertion.layers.dropFirst())
                focusCanvas()
            } else {
                showPage(insertion.page)
            }
        } catch {
            libraryIssue = error.localizedDescription
        }
    }

    func applyCanvasBatch(_ operations: [CanvasOperation], page: UUID, revision: String) throws -> String {
        let next = try DesignBatch.applying(operations, to: project, pageID: page, expecting: revision)
        let nextRevision = try DesignBatch.revision(next)
        file.apply(next, undoManager: undoManager, action: "本机 MCP 编辑")
        return nextRevision
    }

    func setContainerGap(_ layer: UUID, to value: CGFloat) {
        let device = scope
        update(layer, action: "修改间距") { DesignBatch.setGap(value, on: &$0, device: device) }
    }

    func updateBehavior(_ id: UUID, action: String, _ edit: (inout LayerBehavior) -> Void) {
        update(id, action: action) { layer in
            var behavior = layer.behavior ?? LayerBehavior()
            edit(&behavior)
            layer.behavior = behavior == LayerBehavior() ? nil : behavior
        }
    }

    func connect(_ id: UUID, to action: DesignAction?) {
        update(id, action: "修改事件连线") { layer in
            var behavior = layer.behavior ?? LayerBehavior()
            behavior.action = action
            layer.destination = nil
            layer.savesContact = nil
            layer.behavior = behavior == LayerBehavior() ? nil : behavior
        }
    }

    func boardOrigins() -> [UUID: CGPoint] {
        var x: CGFloat = 0
        return Dictionary(uniqueKeysWithValues: project.pages.map { page in
            let origin = page.canvasOrigin ?? CGPoint(x: x, y: 0)
            x += page.size.width + 112
            return (page.id, origin)
        })
    }

    func moveBoard(_ id: UUID, to origin: CGPoint) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        // Materialize default positions in the same undo group so later page removal does not rearrange the flow.
        let origins = boardOrigins()
        var updated = project
        for page in project.pages {
            updated.updatePage(page.id) { $0.canvasOrigin = page.id == id ? origin : origins[page.id] }
        }
        file.apply(updated, undoManager: undoManager, action: "移动画板")
    }

    func addPage() {
        var page = DesignPage()
        let takenTitles = Set(project.pages.map(\.title))
        let number = (1...project.pages.count + 1).first { !takenTitles.contains("页面 \($0)") }!
        page.title = "页面 \(number)"
        let origins = boardOrigins()
        if project.pages.contains(where: { $0.canvasOrigin != nil }) {
            let right = project.pages.map { (origins[$0.id]?.x ?? 0) + $0.size.width }.max() ?? 0
            page.canvasOrigin = CGPoint(x: right + 112, y: 0)
        }
        var updated = project
        updated.additionalPages = (updated.additionalPages ?? []) + [page]
        file.apply(updated, undoManager: undoManager, action: "添加页面")
        showPage(page.id)
    }

    func renamePage(_ title: String) {
        change("重命名页面") { $0.title = title }
    }

    func removePage() {
        var updated = project
        updated.removePage(page.id)
        file.apply(updated, undoManager: undoManager, action: "删除页面")
        showPage(updated.page.id)
    }

    func select(_ id: UUID?) {
        selectedID = id
        selectedBoards = []
        additionalSelection = []
        enteredGroup = page.selection(id)?.parent?.id
    }

    func toggleSelection(_ id: UUID) {
        guard page.layers.contains(where: { $0.id == id }) else { return }
        guard selection?.parent == nil else { select(id); return }
        if id == selectedID {
            selectedID = page.layers.first { additionalSelection.contains($0.id) }?.id
            if let selectedID { additionalSelection.remove(selectedID) }
        } else if additionalSelection.remove(id) == nil {
            if let selectedID { additionalSelection.insert(selectedID) }
            selectedID = id
        }
        enteredGroup = nil
    }

    func enter(_ id: UUID) {
        additionalSelection = []
        selectedID = id
        enteredGroup = id
    }

    func focusCanvas() { focusRequest += 1 }

    func startTextEditing() {
        guard let layer = selection?.layer, layer.kind.editsText else { return }
        textEditor = layer.id
    }

    func endTextEditing(_ text: String?) {
        guard let id = textEditor else { return }
        textEditor = nil
        if let text { update(id, action: "编辑文字") { $0.text = text } }
    }

    func insert(_ kind: LayerKind, frame: CGRect? = nil, into container: UUID? = nil) {
        guard LayerKind.catalog.contains(kind) else { return }
        let target = (container ?? enteredGroup).flatMap { page.selection($0)?.layer }
        let parent = target?.kind.isContainer == true ? target : nil
        let proposed = frame ?? insertionFrame(kind)
        let origin = parent.map {
            let origin = self.frame(of: $0).origin
            return CGPoint(x: max(0, proposed.minX - origin.x), y: max(0, proposed.minY - origin.y))
        } ?? CGPoint(x: proposed.minX, y: max(page.safeTop, proposed.minY - layout.headerHeight))
        var layer = DesignLayer(kind: kind, frame: CGRect(origin: origin, size: proposed.size))
        if layer.geometry == nil {
            layer.geometry = LayerGeometry(width: .fixed, height: kind == .input ? .content : nil)
        }
        change("插入组件") {
            if let parent { $0.update(parent.id) { $0.children.append(layer) } }
            else { $0.layers.append(layer) }
        }
        select(layer.id)
        focusCanvas()
    }

    func insertionFrame(_ kind: LayerKind) -> CGRect {
        let scene = layout
        let root = selection.map { $0.parent ?? $0.layer }
        let last = root ?? page.layers.last(where: { $0.placement(for: scope).region ?? .body == .body })
        let previous = last.map { frame(of: $0, using: scene) }
        return page.constrain(CGRect(x: previous?.minX ?? IOSLayout.pageInset,
                                     y: previous.map { $0.maxY + 16 } ?? page.safeTop + scene.headerHeight + 24,
                                     width: kind.defaultSize.width, height: kind.defaultSize.height), kind: kind)
    }

    func removeSelection() {
        guard let selected = selection, selected.parent?.kind != .setting else { return }
        let ids = selectedIDs
        change("删除图层") { page in ids.forEach { page.remove($0) } }
        select(nil)
    }

    func duplicateSelection() {
        guard let selected = selection, selected.parent?.kind != .setting else { return }
        let scene = layout
        var copy = selected.layer.duplicate()
        if let parent = selected.parent {
            change("复制图层") { $0.update(parent.id) { $0.children.append(copy) } }
        } else {
            let target = frame(of: selected.layer, using: scene)
            copy.frame = page.constrain(selected.layer.frame.offsetBy(dx: 0, dy: target.height + 12), kind: copy.kind)
            copy.geometry?.frame = nil
            copy.deviceLayouts = copy.deviceLayouts?.mapValues {
                var placement = $0
                placement.frame = nil
                return placement
            }
            change("复制图层") { $0.layers.append(copy) }
        }
        select(copy.id)
    }

    func selectAdjacent(forward: Bool) {
        let lookup = Dictionary(uniqueKeysWithValues: page.allLayers.map { ($0.id.uuidString, $0) })
        let layers = layout.renderOrder.compactMap { lookup[$0] }.flatMap { layer in
            layer.kind == .setting ? [layer] + layer.children : [layer]
        }
        guard !layers.isEmpty else { return }
        let index = layers.firstIndex { $0.id == selectedID }
        let delta = forward ? 1 : -1
        select(layers[((index ?? (forward ? -1 : 0)) + delta + layers.count) % layers.count].id)
    }

    func setDevice(_ device: ReviewDevice) {
        change("更改画板设备") {
            $0.device = device
            $0.customSize = nil
            $0.customDeviceLayout = nil
        }
    }

    func setCustomSize(_ size: CGSize) {
        guard (160...4096).contains(size.width), (160...4096).contains(size.height) else { return }
        change("调整画板尺寸") {
            $0.customSize = size
            $0.customDeviceLayout = nil
        }
    }

    func rotateCanvas() {
        let device = page.deviceLayout
        let rotated = CGSize(width: page.size.height, height: page.size.width)
        change("交换画板宽高") {
            $0.customSize = rotated
            $0.customDeviceLayout = device
        }
    }

    func setAspect(width: CGFloat, height: CGFloat) {
        let landscape = page.size.width >= page.size.height || width == height
        let longSide = max(page.size.width, page.size.height, 160 * width / height)
        let shortSide = (longSide * height / width).rounded()
        setCustomSize(landscape ? CGSize(width: longSide, height: shortSide) : CGSize(width: shortSide, height: longSide))
    }

    func setFrame(_ proposed: CGRect, of id: UUID, resizing: Bool = true) {
        guard let selected = page.selection(id), selected.parent?.kind != .setting else { return }
        let scope = scope
        let layer = selected.layer
        let current = frame(of: layer)
        let spec = layer.placement(for: scope)
        let raw = spec.frame?.rect ?? layer.frame
        let widthChanged = resizing && abs(proposed.width - current.width) > 0.01
        let heightChanged = resizing && abs(proposed.height - current.height) > 0.01
        let offsetY = (spec.region ?? .body) == .body ? proposed.minY - current.minY : 0
        let offsetX = proposed.minX - current.minX
        if offsetX == 0 && offsetY == 0 && !widthChanged && !heightChanged { return }
        let frame = page.constrain(CGRect(x: raw.minX + offsetX,
                                         y: raw.minY + offsetY,
                                         width: widthChanged ? proposed.width : raw.width,
                                         height: heightChanged ? proposed.height : raw.height), kind: layer.kind)
        update(id, action: widthChanged || heightChanged ? "调整大小" : "移动图层") {
            if scope == nil {
                $0.frame = frame
                $0.geometry?.frame = nil
                if $0.kind == .setting { $0.spacing = min($0.spacing, $0.maximumSpacing) }
            }
            if scope != nil || widthChanged || heightChanged {
                $0.editPlacement(for: scope) {
                    if scope != nil { $0.frame = LayoutBox(frame) }
                    if widthChanged { $0.width = .fixed }
                    if heightChanged { $0.height = .fixed }
                }
            }
        }
    }

    func setPlacement(_ id: UUID, _ change: (inout LayerGeometry) -> Void) {
        let scope = scope
        update(id, action: "修改布局") { $0.editPlacement(for: scope, change) }
    }

    func restoreSharedLayout() {
        guard let scope else { return }
        change("恢复通用布局") { page in
            for layer in page.allLayers where layer.deviceLayouts?[scope.rawValue] != nil {
                page.update(layer.id) { $0.deviceLayouts?.removeValue(forKey: scope.rawValue) }
            }
        }
    }

    func arrangeSelection(_ arrangement: Arrangement) {
        guard !usesDeviceLayout else { return }
        let ordered = page.layers.filter { selectedIDs.contains($0.id) }
        guard ordered.count > 1, ordered.allSatisfy({ $0.placement(for: nil).region ?? .body == .body }) else { return }
        let scene = layout
        let frames = ordered.map { frame(of: $0, using: scene) }
        let bounds = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        var group = DesignLayer(kind: .layout, frame: bounds.offsetBy(dx: 0, dy: -scene.headerHeight))
        group.geometry = LayerGeometry(width: .fill, height: .content, arrangement: arrangement, gap: 12)
        let indexes = ordered.indices.sorted {
            let left = frames[$0]
            let right = frames[$1]
            return arrangement == .horizontal
                ? (left.minX, left.minY, $0) < (right.minX, right.minY, $1)
                : (left.minY, left.minX, $0) < (right.minY, right.minX, $1)
        }
        group.children = indexes.map { index in
            var layer = ordered[index]
            let origin = layer.frame.origin
            layer.frame = page.constrain(frames[index].offsetBy(dx: -bounds.minX, dy: -bounds.minY), kind: layer.kind)
            layer.geometry?.region = nil
            layer.geometry?.frame = nil
            layer.deviceLayouts = layer.deviceLayouts?.mapValues { value in
                var placement = value
                placement.region = nil
                if var frame = placement.frame {
                    frame.x = max(0, layer.frame.minX + frame.x - origin.x)
                    frame.y = max(0, layer.frame.minY + frame.y - origin.y)
                    placement.frame = frame
                }
                return placement
            }
            return layer
        }
        let ids = selectedIDs
        change("建立排列") { page in
            let index = page.layers.firstIndex(where: { ids.contains($0.id) }) ?? 0
            page.layers.removeAll { ids.contains($0.id) }
            page.layers.insert(group, at: index)
        }
        select(group.id)
    }

    func ungroup(_ group: DesignLayer) {
        guard !usesDeviceLayout, page.selection(group.id)?.parent == nil,
              group.kind.isContainer || group.kind == .setting else { return }
        let scene = layout
        let children = group.children.map { child in
            var part = child
            part.frame = page.constrain(frame(of: child, using: scene).offsetBy(dx: 0, dy: -scene.headerHeight), kind: child.kind)
            part.geometry?.frame = nil
            part.geometry?.region = group.geometry?.region
            part.deviceLayouts = nil
            return part
        }
        change("拆分组合") { page in
            guard let index = page.layers.firstIndex(where: { $0.id == group.id }) else { return }
            page.layers.replaceSubrange(index...index, with: children)
        }
        select(children.first?.id)
    }

    func siblings(of parent: DesignLayer) -> [DesignLayer] {
        guard let order = parent.placement(for: scope).order else { return parent.children }
        let lookup = Dictionary(uniqueKeysWithValues: parent.children.map { ($0.id.uuidString, $0) })
        return order.compactMap { lookup[$0] } + parent.children.filter { !order.contains($0.id.uuidString) }
    }

    func reorder(_ id: UUID, to index: Int) {
        guard let selected = page.selection(id), let parent = selected.parent, parent.kind.isContainer else { return }
        var order = siblings(of: parent).map { $0.id.uuidString }
        guard let previous = order.firstIndex(of: id.uuidString), order.indices.contains(index), previous != index else { return }
        order.remove(at: previous)
        order.insert(id.uuidString, at: index)
        setPlacement(parent.id) { $0.order = order }
    }

    func buttonStyle(for layer: DesignLayer) -> ButtonDesignStyle? {
        project.buttonStyles?.first { $0.id == layer.styleID }
    }

    func newButtonStyle(from layer: DesignLayer, name: String) {
        let style = ButtonDesignStyle(id: UUID(), name: name,
                                      height: min(640, frame(of: layer).height), radius: layer.cornerRadius ?? buttonStyle(for: layer)?.radius ?? 8)
        var updated = project
        updated.buttonStyles = (updated.buttonStyles ?? []) + [style]
        updated.updatePage(page.id) { $0.update(layer.id) { Self.link(style.id, to: &$0) } }
        file.apply(updated, undoManager: undoManager, action: "新建按钮样式")
    }

    func useButtonStyle(_ id: UUID?, for layer: DesignLayer) {
        let height = frame(of: layer).height
        let radius = layer.cornerRadius ?? buttonStyle(for: layer)?.radius
        update(layer.id, action: "应用按钮样式") {
            Self.link(id, to: &$0)
            if id == nil {
                $0.frame.size.height = height
                $0.cornerRadius = radius
            }
        }
    }

    func updateButtonStyle(from layer: DesignLayer) {
        guard let style = buttonStyle(for: layer) else { return }
        let height = min(640, frame(of: layer).height)
        var updated = project
        guard let index = updated.buttonStyles?.firstIndex(where: { $0.id == style.id }) else { return }
        updated.buttonStyles?[index].height = height
        updated.buttonStyles?[index].radius = layer.cornerRadius ?? style.radius
        updated.updatePage(page.id) { $0.update(layer.id) { Self.link(style.id, to: &$0) } }
        file.apply(updated, undoManager: undoManager, action: "更新按钮样式")
    }

    private static func link(_ styleID: UUID?, to layer: inout DesignLayer) {
        layer.styleID = styleID
        layer.geometry?.height = nil
        layer.cornerRadius = nil
        if let overrides = layer.deviceLayouts {
            layer.deviceLayouts = overrides.mapValues { value in
                var placement = value
                placement.height = nil
                return placement
            }
        }
    }

    func setReference(_ reference: ReferenceLayout?) {
        change("选择参考布局") { $0.reference = reference }
    }

    func updateReference(_ action: String, _ update: (inout ReferenceImage) -> Void) {
        change(action) { page in
            guard var reference = page.referenceImage else { return }
            update(&reference)
            page.referenceImage = reference
        }
    }

    func removeReferenceImage() {
        change("移除对照底图") { $0.referenceImage = nil }
    }

    func importImage(reference: Bool, layerID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        let pageID = page.id
        let completion: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self, result == .OK, let url = panel.url, self.page.id == pageID else { return }
            guard let data = Self.readImage(url) else {
                self.imageIssue = "请选择可读取且大小不超过 12 MB 的图片"
                return
            }
            if reference {
                self.change("导入对照底图") { $0.referenceImage = ReferenceImage(data: data, name: url.lastPathComponent) }
            } else if let layerID {
                self.update(layerID, action: "更换图片") { $0.image = data }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private static func readImage(_ url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= ReferenceImage.maximumBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target), output.length <= ReferenceImage.maximumBytes else { return nil }
        return output as Data
    }

    func setSpacing(_ spacing: CGFloat, of id: UUID) {
        let local = scope
        guard let layer = page.selection(id)?.layer else { return }
        let maximum = max(0, min(96, frame(of: layer).width - 108))
        let gap = min(max(spacing, 0), maximum)
        if let local {
            update(id, action: "调整间距") { $0.editPlacement(for: local) { $0.gap = gap } }
        } else {
            update(id, action: "调整间距") { $0.spacing = gap }
        }
    }

    func update(_ id: UUID, action: String, _ change: (inout DesignLayer) -> Void) {
        self.change(action) { $0.update(id, change) }
    }

    func change(_ action: String, _ change: (inout DesignPage) -> Void) {
        var updated = file.project
        updated.updatePage(page.id, change)
        file.apply(updated, undoManager: undoManager, action: action)
    }
}
