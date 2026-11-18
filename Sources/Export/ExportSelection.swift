import Foundation

enum SourceExportScope: Sendable {
    case complete
    case pages(Set<UUID>)
}

struct SourceExport: Sendable {
    struct Page: Codable, Equatable, Sendable {
        let id: String
        let title: String
    }

    struct HostLink: Codable, Equatable, Sendable {
        let event: String
        let fromPage: String
        let fromLayer: String
        let targetPage: String
        let targetTitle: String
        let presentation: String
        let trigger: String
    }

    let runtime: RuntimeDesign
    let pages: [Page]
    let links: [HostLink]
    let isComplete: Bool

    init(project: DesignProject, scope: SourceExportScope) throws {
        let full = try project.validated().runtime()
        let selected: [RuntimePage]
        switch scope {
        case .complete:
            isComplete = true
            selected = full.pages
        case .pages(let ids):
            isComplete = false
            selected = full.pages.filter { page in UUID(uuidString: page.id).map(ids.contains) == true }
        }
        guard let first = selected.first else { throw ExportProblem.noSelectedPages }
        let included = Set(selected.map(\.id))
        let titles = Dictionary(uniqueKeysWithValues: full.pages.map { ($0.id, $0.title) })
        var links: [HostLink] = []
        let exported = selected.map { original in
            var page = original
            page.layers = original.layers.map { input in
                var layer = input
                func routed(_ action: DesignAction?, trigger: String) -> DesignAction? {
                    guard let action, action.kind == .navigate || action.kind == .sheet,
                          let target = action.target, !included.contains(target),
                          let title = titles[target] else { return action }
                    let event = "\(action.kind == .sheet ? "presentPage" : "openPage"):\(target)"
                    links.append(HostLink(event: event, fromPage: original.id, fromLayer: input.id,
                                          targetPage: target, targetTitle: title, presentation: action.kind.rawValue,
                                          trigger: trigger))
                    return DesignAction(kind: .named, name: event)
                }
                if var behavior = layer.behavior {
                    behavior.action = routed(behavior.action, trigger: "activate")
                    if var list = behavior.list {
                        list.emptyAction = routed(list.emptyAction, trigger: "empty")
                        behavior.list = list
                    }
                    layer.behavior = behavior
                }
                if let target = layer.destination, !included.contains(target) {
                    var behavior = layer.behavior ?? LayerBehavior()
                    if behavior.action == nil {
                        behavior.action = routed(DesignAction(kind: .navigate, target: target), trigger: "row")
                        layer.behavior = behavior
                    }
                    layer.destination = nil
                }
                return layer
            }
            return page
        }
        let needsLegacySample = exported.flatMap(\.layers).contains { $0.kind == "contactList" && $0.behavior?.list == nil }
        runtime = RuntimeDesign(entry: included.contains(full.entry) ? full.entry : first.id,
                                pages: exported, contacts: needsLegacySample ? full.contacts : [])
        pages = exported.map { Page(id: $0.id, title: $0.title) }
        self.links = links
    }

    init(runtime: RuntimeDesign) {
        self.runtime = runtime
        pages = runtime.pages.map { Page(id: $0.id, title: $0.title) }
        links = []
        isComplete = true
    }
}

enum ExportProblem: LocalizedError {
    case noSelectedPages
    case invalidDirectory
    case changedAfterReview(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .noSelectedPages: "请至少选择一个页面"
        case .invalidDirectory: "请选择已有的 UI Design 导出目录，或导出到新目录"
        case .changedAfterReview(let path): "检查后又修改了「\(path)」。请重新查看差异再更新"
        case .unsafePath(let path): "无法更新「\(path)」：路径包含非普通文件或链接"
        }
    }
}
