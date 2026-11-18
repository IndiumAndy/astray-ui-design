import SwiftUI

@MainActor @Observable
final class DesignEditing {
    private let file: DesignFile
    @ObservationIgnored weak var undoManager: UndoManager?
    private(set) var selectedID: UUID?
    private(set) var enteredGroup: UUID?
    private(set) var textEditor: UUID?
    private(set) var focusRequest = 0

    var pan = CGPoint.zero
    var magnification: CGFloat?

    init(file: DesignFile) { self.file = file }

    var page: DesignPage { file.project.page }
    var selection: (layer: DesignLayer, parent: DesignLayer?)? { page.selection(selectedID) }

    func select(_ id: UUID?) {
        selectedID = id
        enteredGroup = page.selection(id)?.parent?.id
    }

    func enter(_ id: UUID) {
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

    func insert(_ kind: LayerKind, frame: CGRect? = nil) {
        guard LayerKind.catalog.contains(kind) else { return }
        let layer = DesignLayer(kind: kind, frame: frame ?? insertionFrame(kind))
        change("插入组件") { $0.layers.append(layer) }
        select(layer.id)
        focusCanvas()
    }

    func insertionFrame(_ kind: LayerKind) -> CGRect {
        let last = selection.map { $0.parent?.frame ?? $0.layer.frame } ?? page.layers.last?.frame
        let x = last?.minX ?? IOSLayout.pageInset
        let y = (last.map { $0.maxY + 16 } ?? (IOSLayout.statusHeight + 24))
        let origin = y + kind.defaultSize.height < page.bounds.height - IOSLayout.homeHeight
            ? CGPoint(x: x, y: y)
            : CGPoint(x: IOSLayout.pageInset + 16, y: IOSLayout.statusHeight + 40)
        return page.constrain(CGRect(origin: origin, size: kind.defaultSize), kind: kind)
    }

    func removeSelection() {
        guard let selected = selection, selected.parent == nil else { return }
        change("删除图层") { $0.layers.removeAll { $0.id == selected.layer.id } }
        select(nil)
    }

    func selectAdjacent(forward: Bool) {
        let layers = page.layers.flatMap { [$0] + $0.children }
        guard !layers.isEmpty else { return }
        let index = layers.firstIndex { $0.id == selectedID }
        let delta = forward ? 1 : -1
        select(layers[((index ?? (forward ? -1 : 0)) + delta + layers.count) % layers.count].id)
    }

    func setDevice(_ device: ReviewDevice) {
        change("更改画板设备") { page in
            page.device = device
            for index in page.layers.indices {
                let layer = page.layers[index]
                page.layers[index].frame = page.constrain(layer.frame, kind: layer.kind)
                page.layers[index].spacing = min(layer.spacing, page.layers[index].maximumSpacing)
            }
        }
    }

    func setFrame(_ frame: CGRect, of id: UUID) {
        guard let selected = page.selection(id), selected.parent == nil else { return }
        let frame = page.constrain(frame, kind: selected.layer.kind)
        update(id, action: frame.size == selected.layer.frame.size ? "移动图层" : "调整大小") {
            $0.frame = frame
            $0.spacing = min($0.spacing, $0.maximumSpacing)
        }
    }

    func setSpacing(_ spacing: CGFloat, of id: UUID) {
        update(id, action: "调整间距") { $0.spacing = min(max(spacing, 0), $0.maximumSpacing) }
    }

    func update(_ id: UUID, action: String, _ change: (inout DesignLayer) -> Void) {
        self.change(action) { $0.update(id, change) }
    }

    private func change(_ action: String, _ change: (inout DesignPage) -> Void) {
        var updated = file.project
        change(&updated.page)
        file.apply(updated, undoManager: undoManager, action: action)
    }
}
