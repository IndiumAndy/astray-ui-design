import Foundation

enum TemplateSelection {
    case layers(page: UUID, layers: [DesignLayer])
    case pages(Set<UUID>)
}

struct PersonalTemplate: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case component, group, page, flow

        var title: String {
            switch self {
            case .component: "组件"
            case .group: "组合"
            case .page: "页面"
            case .flow: "流程"
            }
        }

        var symbol: String {
            switch self {
            case .component: "square"
            case .group: "square.on.square"
            case .page: "rectangle.portrait"
            case .flow: "point.topleft.down.to.point.bottomright.curvepath"
            }
        }

        var insertsLayers: Bool { self == .component || self == .group }
    }

    let id: UUID
    let name: String
    let kind: Kind
    let project: DesignProject

    struct Insertion {
        let project: DesignProject
        let page: UUID
        let layers: [UUID]
    }

    static func linkedPages(in project: DesignProject, selection: TemplateSelection) -> Set<UUID> {
        let selected = selectedPages(in: project, selection: selection)
        var visited = Set(selected.map(\.id))
        var remaining = selected
        while let page = remaining.popLast() {
            let targets = page.allLayers.flatMap { layer -> [UUID] in
                let actions = [layer.behavior?.action, layer.behavior?.list?.emptyAction]
                return [layer.destination].compactMap { $0 } + actions.compactMap { action in
                    guard let action, action.kind == .navigate || action.kind == .sheet else { return nil }
                    return action.target.flatMap(UUID.init(uuidString:))
                }
            }
            for id in targets {
                if let page = project.pages.first(where: { $0.id == id }), visited.insert(id).inserted {
                    remaining.append(page)
                }
            }
        }
        return visited.subtracting(selected.map(\.id))
    }

    static func capture(name: String, replacing: UUID? = nil, from project: DesignProject,
                        selection: TemplateSelection, includeLinkedPages: Bool) throws -> Self {
        var pages = selectedPages(in: project, selection: selection)
        guard let first = pages.first else { throw TemplateError.noSelection }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TemplateError.noName }
        let kind: Kind
        switch selection {
        case .layers:
            guard let layer = first.layers.first else { throw TemplateError.noSelection }
            kind = first.layers.count == 1 && layer.children.isEmpty && !layer.kind.isContainer ? .component : .group
        case .pages:
            kind = pages.count == 1 ? .page : .flow
        }
        if includeLinkedPages {
            let extra = linkedPages(in: project, selection: selection)
            pages += project.pages.filter { extra.contains($0.id) }
        }
        let retained = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0.id) })
        let layers = pages.flatMap(\.allLayers)
        let styles = Set(layers.compactMap(\.styleID))
        var payload = DesignProject()
        pages = pages.map { clonePage($0, pageIDs: retained, styleIDs: [:], freshIDs: false) }
        payload.page = pages[0]
        payload.additionalPages = Array(pages.dropFirst())
        payload.buttonStyles = project.buttonStyles?.filter { styles.contains($0.id) }
        if layers.contains(where: { $0.kind == .contactList && $0.behavior?.list == nil }) {
            payload.contacts = project.contacts
        }
        return Self(id: replacing ?? UUID(), name: title, kind: kind, project: try payload.validated())
    }

    func instantiate(into target: DesignProject? = nil, pageID: UUID? = nil,
                     origin: CGPoint? = nil) throws -> Insertion {
        _ = try project.validated()
        if let target, kind.insertsLayers, let pageID, !target.pages.contains(where: { $0.id == pageID }) {
            throw TemplateError.noSelection
        }
        var result = target ?? DesignProject()
        let joins = target != nil && kind.insertsLayers
        let destination = joins ? result.page(withID: pageID) : nil
        let pageIDs = Dictionary(uniqueKeysWithValues: project.pages.map {
            ($0.id, $0.id == project.page.id ? destination?.id ?? UUID() : UUID())
        })
        let styles = project.buttonStyles ?? []
        let styleIDs = Dictionary(uniqueKeysWithValues: styles.map { ($0.id, UUID()) })
        let copiedStyles = styles.compactMap { style in
            styleIDs[style.id].map { ButtonDesignStyle(id: $0, name: style.name, height: style.height, radius: style.radius) }
        }
        if !copiedStyles.isEmpty { result.buttonStyles = (result.buttonStyles ?? []) + copiedStyles }
        if let recordings = project.contacts, !recordings.isEmpty {
            let existing = Set((result.contacts ?? []).map(\.id))
            result.contacts = (result.contacts ?? []) + recordings.filter { !existing.contains($0.id) }
        }
        var copies = project.pages.map { Self.clonePage($0, pageIDs: pageIDs, styleIDs: styleIDs, freshIDs: true) }
        let copiedPage = copies[0]
        if let destination {
            var incoming = copies.removeFirst().layers
            Self.isolateForms(&incoming, from: destination)
            if let origin {
                let bounds = incoming.reduce(CGRect.null) { $0.union($1.frame) }
                for index in incoming.indices {
                    let change: (CGRect) -> CGRect = { frame in
                        let proposed = frame.offsetBy(dx: origin.x - bounds.minX, dy: origin.y - bounds.minY)
                        return CGRect(x: max(0, min(DesignPage.maximumContentHeight, proposed.minX)),
                                      y: max(0, min(DesignPage.maximumContentHeight, proposed.minY)),
                                      width: proposed.width, height: proposed.height)
                    }
                    let kind = incoming[index].kind
                    incoming[index].frame = destination.constrain(change(incoming[index].frame), kind: kind)
                    let sharedFrame = incoming[index].geometry?.frame.map { LayoutBox(change($0.rect)) }
                    incoming[index].geometry?.frame = sharedFrame
                    incoming[index].deviceLayouts = incoming[index].deviceLayouts?.mapValues {
                        var layout = $0
                        layout.frame = layout.frame.map { LayoutBox(change($0.rect)) }
                        return layout
                    }
                }
            }
            result.updatePage(destination.id) { $0.layers += incoming }
        }
        if target == nil {
            result.page = copies.removeFirst()
            result.additionalPages = copies
        } else if !copies.isEmpty {
            // Keep each flow's relative placement and add it clear of existing boards.
            let existing = Self.origins(for: result.pages)
            let incoming = Self.origins(for: copies)
            let sourceX = incoming.values.map(\.x).min() ?? 0
            let right = result.pages.map { (existing[$0.id]?.x ?? 0) + $0.size.width }.max() ?? 0
            let shiftX = right + 112 - sourceX
            for index in copies.indices {
                let point = incoming[copies[index].id] ?? .zero
                copies[index].canvasOrigin = CGPoint(x: point.x + shiftX, y: point.y)
            }
            result.additionalPages = (result.additionalPages ?? []) + copies
        }
        return Insertion(project: try result.validated(), page: copiedPage.id,
                         layers: joins ? copiedPage.layers.map(\.id) : [])
    }

    private static func selectedPages(in project: DesignProject, selection: TemplateSelection) -> [DesignPage] {
        switch selection {
        case .pages(let ids):
            return project.pages.filter { ids.contains($0.id) }
        case let .layers(id, layers):
            guard var page = project.pages.first(where: { $0.id == id }), !layers.isEmpty else { return [] }
            page.layers = layers
            page.reference = nil
            page.referenceImage = nil
            return [page]
        }
    }

    private static func clonePage(_ source: DesignPage, pageIDs: [UUID: UUID],
                                  styleIDs: [UUID: UUID], freshIDs: Bool) -> DesignPage {
        var page = DesignPage(id: pageIDs[source.id] ?? source.id)
        page.title = source.title
        page.device = source.device
        page.customSize = source.customSize
        page.customDeviceLayout = source.customDeviceLayout
        page.reference = source.reference
        page.referenceImage = source.referenceImage
        page.canvasOrigin = source.canvasOrigin
        func mapping(_ action: DesignAction?) -> DesignAction? {
            guard var action else { return nil }
            if action.kind == .navigate || action.kind == .sheet {
                guard let target = action.target.flatMap(UUID.init(uuidString:)).flatMap({ pageIDs[$0] }),
                      target != page.id else { return nil }
                action.target = target.uuidString
            }
            return action
        }
        func fix(_ layer: inout DesignLayer) {
            layer.destination = layer.destination.flatMap { pageIDs[$0] }.flatMap { $0 == page.id ? nil : $0 }
            if freshIDs { layer.styleID = layer.styleID.flatMap { styleIDs[$0] } }
            if var behavior = layer.behavior {
                behavior.action = mapping(behavior.action)
                if var list = behavior.list {
                    list.emptyAction = mapping(list.emptyAction)
                    behavior.list = list
                }
                layer.behavior = behavior
            }
            for index in layer.children.indices { fix(&layer.children[index]) }
        }
        page.layers = source.layers.map { source in
            var clone = freshIDs ? source.duplicate() : source
            fix(&clone)
            return clone
        }
        return page
    }

    private static func origins(for pages: [DesignPage]) -> [UUID: CGPoint] {
        var next: CGFloat = 0
        return Dictionary(uniqueKeysWithValues: pages.map { page in
            let point = page.canvasOrigin ?? CGPoint(x: next, y: 0)
            next += page.size.width + 112
            return (page.id, point)
        })
    }

    private static func isolateForms(_ layers: inout [DesignLayer], from page: DesignPage) {
        func formNames(_ layers: [DesignLayer]) -> Set<String> {
            Set(layers.flatMap { [$0.behavior?.form, $0.behavior?.action?.form, $0.behavior?.list?.emptyAction?.form].compactMap { $0 } })
        }
        var reserved = formNames(page.allLayers)
        let incoming = formNames(layers.flatMap(\.descendants))
        var names: [String: String] = [:]
        for name in incoming.sorted() {
            if !reserved.insert(name).inserted {
                var number = 2
                while reserved.contains("\(name)-\(number)") || incoming.contains("\(name)-\(number)") { number += 1 }
                let unique = "\(name)-\(number)"
                reserved.insert(unique)
                names[name] = unique
            }
        }
        func remap(_ layer: inout DesignLayer) {
            if let name = layer.behavior?.form, let unique = names[name] { layer.behavior?.form = unique }
            if let name = layer.behavior?.action?.form, let unique = names[name] { layer.behavior?.action?.form = unique }
            if let name = layer.behavior?.list?.emptyAction?.form, let unique = names[name] {
                layer.behavior?.list?.emptyAction?.form = unique
            }
            for i in layer.children.indices { remap(&layer.children[i]) }
        }
        for index in layers.indices { remap(&layers[index]) }
    }
}

enum TemplateError: LocalizedError {
    case noSelection, noName
    var errorDescription: String? {
        switch self {
        case .noSelection: "请选择要保存的组件或页面"
        case .noName: "请输入模板名称"
        }
    }
}

@MainActor @Observable
final class PersonalLibrary {
    static let shared = PersonalLibrary()
    private(set) var templates: [PersonalTemplate] = []
    var issue: String?
    private let directory: URL

    init(directory: URL? = nil) {
        let applicationSupport = URL.applicationSupportDirectory
        self.directory = directory ?? applicationSupport.appending(path: "UI Design/Personal Library", directoryHint: .isDirectory)
        reload()
    }

    func save(_ template: PersonalTemplate) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(template).write(to: directory.appending(path: "\(template.id.uuidString).json"), options: .atomic)
        templates.removeAll { $0.id == template.id }
        templates.append(template)
        sort()
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            let decoder = JSONDecoder()
            templates = files.filter { $0.pathExtension == "json" }.compactMap { file in
                do {
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                          let identifier = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
                    let item = try decoder.decode(PersonalTemplate.self, from: Data(contentsOf: file))
                    guard item.id == identifier else { return nil }
                    return item
                } catch {
                    issue = "部分模板无法读取，原文件未修改"
                    return nil
                }
            }
            sort()
        } catch {
            issue = "无法打开个人库：\(error.localizedDescription)"
        }
    }

    private func sort() {
        templates.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedAscending || (order == .orderedSame && $0.id.uuidString < $1.id.uuidString)
        }
    }
}
