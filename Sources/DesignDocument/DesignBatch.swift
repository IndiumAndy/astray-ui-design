import CoreGraphics
import Foundation

struct CanvasOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, align, gap }
    let kind: Kind
    let ids: [UUID]
    var text: String?
    var value: CGFloat?
}

enum DesignBatch {
    static func revision(_ project: DesignProject) throws -> String {
        ExportManifest.digest(try DesignCodec.encoded(project))
    }

    static func applying(_ operations: [CanvasOperation], to source: DesignProject,
                         pageID: UUID, expecting revision: String) throws -> DesignProject {
        let current = try Self.revision(source)
        guard revision == current else { throw CanvasBatchError.conflict(current: current) }
        guard (1...64).contains(operations.count), source.pages.contains(where: { $0.id == pageID }) else {
            throw CanvasBatchError.invalid("选择界面不存在，或批次操作数不在 1–64 范围")
        }
        var candidate = source
        var page = source.page(withID: pageID)
        for (index, operation) in operations.enumerated() {
            do { try apply(operation, to: &page) }
            catch { throw CanvasBatchError.operation(index + 1, error.localizedDescription) }
        }
        candidate.updatePage(pageID) { $0 = page }
        return try candidate.validated()
    }

    static func setGap(_ gap: CGFloat, on layer: inout DesignLayer, device: DeviceLayout? = nil) {
        layer.editPlacement(for: device) { $0.gap = gap }
    }

    private static func apply(_ operation: CanvasOperation, to page: inout DesignPage) throws {
        let selections = operation.ids.compactMap { page.selection($0) }
        guard !selections.isEmpty, selections.count == operation.ids.count,
              Set(operation.ids).count == operation.ids.count else {
            throw CanvasBatchError.invalid("包含不存在或重复的图层标识")
        }
        switch operation.kind {
        case .text:
            guard selections.count == 1, selections[0].layer.kind.editsText,
                  let text = operation.text, text.utf8.count <= 32_768 else {
                throw CanvasBatchError.invalid("文字操作需要一个支持文本的图层和有效文本")
            }
            page.update(operation.ids[0]) { $0.text = text }
        case .align:
            let parent = selections[0].parent
            guard selections.count >= 2, selections.allSatisfy({ $0.parent?.id == parent?.id }),
                  parent?.kind != .setting,
                  parent == nil || (parent?.placement(for: nil).arrangement ?? .free) == .free else {
                throw CanvasBatchError.invalid("左对齐需要同一自由布局中的两个或更多图层")
            }
            let target = operation.value ?? selections.map { $0.layer.placement(for: nil).frame?.x ?? $0.layer.frame.minX }.min()!
            guard (0...DesignPage.maximumContentHeight).contains(target) else {
                throw CanvasBatchError.invalid("左对齐坐标超出范围")
            }
            for id in operation.ids {
                page.update(id) { layer in
                    layer.frame.origin.x = target
                    layer.geometry?.frame?.x = target
                }
            }
        case .gap:
            guard selections.count == 1, selections[0].layer.kind.isContainer,
                  let gap = operation.value, (0...240).contains(gap) else {
                throw CanvasBatchError.invalid("间距操作需要一个容器和 0–240 的数值")
            }
            page.update(operation.ids[0]) { setGap(gap, on: &$0) }
        }
    }
}

enum CanvasBatchError: LocalizedError {
    case conflict(current: String)
    case invalid(String)
    case operation(Int, String)

    var errorDescription: String? {
        switch self {
        case .conflict: "设计已被修改。请先重新读取，再提交更新"
        case .invalid(let note): note
        case .operation(let index, let note): "第 \(index) 项：\(note)"
        }
    }
}
