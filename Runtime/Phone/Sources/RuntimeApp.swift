import SwiftUI

@main
struct ContactApp: App {
    var body: some Scene {
        WindowGroup {
            RuntimeRoot(onSaveContact: ContactActions.onSaveContact, onAction: ContactActions.onAction)
        }
    }
}

@MainActor @Observable
final class ContactRuntime {
    struct Row: Hashable {
        let list: String
        let id: String
    }

    struct Route: Hashable, Identifiable {
        let page: String
        var contact: String?
        var row: Row?
        var id: Self { self }
    }

    private struct DraftKey: Hashable {
        let route: Route
        let layer: String
    }

    private struct Draft {
        let original: DesignValue
        let value: DesignValue
    }

    private(set) var design: RuntimeDesign?
    var data = RuntimeData()
    var path: [Route] = []
    var panel: Route?
    private var drafts: [DraftKey: Draft] = [:]
    private var errors: [DraftKey: String] = [:]
    private var currentValues: [String: [ContactField: String]] = [:]
    func apply(_ snapshot: RuntimeDesign) {
        guard design != snapshot else { return }
        let previous = design
        design = snapshot
        if snapshot.entry != previous?.entry { path = []; panel = nil }
        reconcile()
        let previousLayers = Dictionary(uniqueKeysWithValues: (previous?.pages ?? []).flatMap(\.layers).map { ($0.id, $0) })
        let layers = Dictionary(uniqueKeysWithValues: snapshot.pages.flatMap(\.layers).map { ($0.id, $0) })
        func retains(_ key: DraftKey) -> Bool {
            guard let layer = layers[key.layer] else { return false }
            return layer.behavior?.binding == previousLayers[key.layer]?.behavior?.binding &&
                layer.field == previousLayers[key.layer]?.field
        }
        drafts = drafts.filter { key, draft in
            guard retains(key), let layer = layers[key.layer] else { return false }
            return original(layer, key.route) == draft.original
        }
        errors = errors.filter { retains($0.key) }
    }

    func apply(_ input: RuntimeData) {
        guard data != input else { return }
        let prior = data
        data = input
        reconcile()
        let layers = Dictionary(uniqueKeysWithValues: (design?.pages ?? []).flatMap(\.layers).map { ($0.id, $0) })
        drafts = drafts.filter { key, draft in
            guard let layer = layers[key.layer] else { return false }
            return original(layer, key.route) == draft.original
        }
        errors = errors.filter { key, _ in
            guard let binding = layers[key.layer]?.behavior?.binding, binding.source == .application else { return true }
            return prior.values[binding.key] == input.values[binding.key]
        }
    }

    private func valid(_ route: Route) -> Bool {
        design?.pages.contains(where: { $0.id == route.page }) == true &&
            (route.contact == nil || contact(route) != nil) && (route.row == nil || record(route) != nil)
    }

    private func reconcile() {
        if let invalid = path.firstIndex(where: { !valid($0) }) { path.removeSubrange(invalid...) }
        if let panel, !valid(panel) { self.panel = nil }
        drafts = drafts.filter { valid($0.key.route) }
        errors = errors.filter { valid($0.key.route) }
    }

    func contact(_ route: Route) -> DesignContact? {
        design?.contacts.first { $0.id == route.contact }
    }

    func content(_ layer: RuntimeLayer) -> ListContent {
        if let spec = layer.behavior?.list { return data.lists[spec.key] ?? spec.sample }
        return ListContent(rows: (design?.contacts ?? []).map { contact in
            DesignRecord(id: contact.id, fields: Dictionary(uniqueKeysWithValues: ContactField.allCases.map { ($0.rawValue, .text(contact[$0])) }))
        })
    }

    private func record(_ route: Route) -> DesignRecord? {
        if let row = route.row,
           let layer = design?.pages.lazy.flatMap(\.layers).first(where: { $0.id == row.list }),
           let record = content(layer).rows.first(where: { $0.id == row.id }) {
            return record
        }
        if let contact = contact(route) {
            return DesignRecord(id: contact.id, fields: Dictionary(uniqueKeysWithValues: ContactField.allCases.map { ($0.rawValue, .text(contact[$0])) }))
        }
        return nil
    }

    func open(_ layer: RuntimeLayer, contact: DesignContact) {
        guard let destination = layer.destination else { return }
        let next = Route(page: destination, contact: contact.id)
        if valid(next) { path.append(next) }
    }

    func select(_ layer: RuntimeLayer, row: DesignRecord, route: Route, inPanel: Bool,
                onAction: (DesignEvent) -> DesignActionResult) {
        if let action = layer.behavior?.action {
            perform(action, layer: layer, route: route, selected: row, inPanel: inPanel, onAction: onAction)
        } else if let destination = layer.destination {
            if layer.behavior?.list != nil {
                perform(DesignAction(kind: .navigate, target: destination), layer: layer, route: route,
                        selected: row, inPanel: inPanel, onAction: onAction)
            } else if let contact = design?.contacts.first(where: { $0.id == row.id }) {
                open(layer, contact: contact)
            }
        }
    }

    func state(_ layer: RuntimeLayer) -> ControlState { data.controlStates[layer.id] ?? layer.behavior?.state ?? .normal }

    private func original(_ layer: RuntimeLayer, _ route: Route) -> DesignValue {
        let legacy = layer.field.flatMap { field in
            contact(route).map { currentValues[$0.id]?[field] ?? $0[field] } ?? record(route)?.fields[field.rawValue]?.text
        }
        return layer.originalValue(data: data, record: record(route), legacy: legacy)
    }

    func current(_ layer: RuntimeLayer, _ route: Route) -> DesignValue {
        let base = original(layer, route)
        if let draft = drafts[DraftKey(route: route, layer: layer.id)], draft.original == base { return draft.value }
        return base
    }

    func display(_ layer: RuntimeLayer, route: Route) -> String { current(layer, route).text }

    func value(_ layer: RuntimeLayer, route: Route,
               onAction: @escaping (DesignEvent) -> DesignActionResult) -> Binding<String> {
        Binding { self.current(layer, route).text } set: { self.edit(layer, route, .text($0), onAction: onAction) }
    }

    func toggle(_ layer: RuntimeLayer, route: Route,
                onAction: @escaping (DesignEvent) -> DesignActionResult) -> Binding<Bool> {
        Binding { self.current(layer, route).flag } set: { self.edit(layer, route, .flag($0), onAction: onAction) }
    }

    func error(_ layer: RuntimeLayer, _ route: Route) -> String? {
        errors[DraftKey(route: route, layer: layer.id)] ??
            (state(layer) == .error ? layer.behavior?.stateMessage ?? "请检查此字段" : nil)
    }

    private func edit(_ layer: RuntimeLayer, _ route: Route, _ value: DesignValue,
                      onAction: (DesignEvent) -> DesignActionResult) {
        guard !state(layer).blocksInput, current(layer, route) != value else { return }
        let key = DraftKey(route: route, layer: layer.id)
        drafts[key] = Draft(original: original(layer, route), value: value)
        errors[key] = nil
        if let name = layer.behavior?.changeAction, !name.isEmpty {
            let result = onAction(DesignEvent(name: name, pageID: route.page, layerID: layer.id,
                                              values: [layer.eventKey: value], record: record(route)))
            errors[key] = result.fieldErrors[layer.eventKey]
        }
    }

    @discardableResult func perform(_ action: DesignAction, layer: RuntimeLayer, route: Route,
                                    selected: DesignRecord? = nil, inPanel: Bool, order: [String] = [],
                                    onAction: (DesignEvent) -> DesignActionResult) -> String? {
        guard !state(layer).blocksInput else { return nil }
        switch action.kind {
        case .navigate, .sheet:
            guard let target = action.target else { return nil }
            let row = selected.map { Row(list: layer.id, id: $0.id) } ?? route.row
            let next = Route(page: target, contact: selected == nil ? route.contact : nil, row: row)
            guard valid(next) else { return nil }
            if action.kind == .sheet { panel = next }
            else {
                if inPanel { panel = nil }
                path.append(next)
            }
        case .back:
            if inPanel { panel = nil }
            else if !path.isEmpty { path.removeLast() }
        case .dismiss: panel = nil
        case .named, .submit:
            guard let name = action.name, !name.isEmpty else { return nil }
            var event = DesignEvent(name: name, pageID: route.page, layerID: layer.id, record: selected ?? record(route))
            guard action.kind == .submit else { _ = onAction(event); return nil }
            guard let form = action.form, !form.isEmpty,
                  let page = design?.pages.first(where: { $0.id == route.page }) else { return nil }
            let lookup = Dictionary(uniqueKeysWithValues: page.layers.map { ($0.id, $0) })
            let layers = order.isEmpty ? page.layers : order.compactMap { lookup[$0] }
            let submission = FormSubmission(form: form, layers: layers, value: { current($0, route) }, state: state)
            event.form = form
            event.values = submission.values
            let formErrors = submission.errors.isEmpty ? submission.errorsByLayer(onAction(event)) : submission.errors
            for field in submission.fields { errors[DraftKey(route: route, layer: field.id)] = formErrors[field.id] }
            let invalid = submission.fields.filter { formErrors[$0.id] != nil }
            return (invalid.first { $0.kind == "input" } ?? invalid.first)?.id
        }
        return nil
    }

    func save(_ route: Route, onSave: (ContactSave) -> Void) {
        guard let contact = contact(route), let page = design?.pages.first(where: { $0.id == route.page }) else { return }
        var values: [String: String] = [:]
        for layer in page.layers where layer.kind == "input" {
            guard let field = layer.field else { continue }
            let text = current(layer, route).text
            values[field.rawValue] = text
            currentValues[contact.id, default: [:]][field] = text
        }
        onSave(ContactSave(contactID: contact.id, values: values))
    }
}

struct RuntimeRoot: View {
    let design: RuntimeDesign?
    let data: RuntimeData
    var onSaveContact: (ContactSave) -> Void
    var onAction: (DesignEvent) -> DesignActionResult
    @State private var runtime = ContactRuntime()
    @State private var failure = false
    private let preview = ProcessInfo.processInfo.arguments
        .first { $0.hasPrefix("--preview-url=") }
        .flatMap { URL(string: String($0.dropFirst("--preview-url=".count))) }
        .flatMap { $0.host() == "127.0.0.1" ? $0 : nil }

    init(design: RuntimeDesign? = nil, data: RuntimeData = RuntimeData(),
         onSaveContact: @escaping (ContactSave) -> Void = { _ in },
         onAction: @escaping (DesignEvent) -> DesignActionResult = { _ in DesignActionResult() }) {
        self.design = design
        self.data = data
        self.onSaveContact = onSaveContact
        self.onAction = onAction
    }

    var body: some View {
        @Bindable var runtime = runtime
        NavigationStack(path: $runtime.path) {
            Group {
                if let design = runtime.design {
                    screen(.init(page: design.entry))
                } else if failure {
                    Text("请在编辑器中重新运行预览")
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: ContactRuntime.Route.self) { screen($0, isPushed: true) }
        }
        .sheet(item: $runtime.panel) { route in
            NavigationStack {
                screen(route, inPanel: true)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { runtime.panel = nil } } }
            }
        }
        .onChange(of: data, initial: true) { runtime.apply(data) }
        .onChange(of: design, initial: true) { if let design { runtime.apply(design) } }
        .task { await load() }
    }

    @ViewBuilder private func screen(_ route: ContactRuntime.Route, isPushed: Bool = false, inPanel: Bool = false) -> some View {
        if let page = runtime.design?.pages.first(where: { $0.id == route.page }) {
            RuntimeScreen(page: page, runtime: runtime, route: route, isLive: preview != nil || design != nil,
                          isPushed: isPushed, inPanel: inPanel, onSaveContact: onSaveContact, onAction: onAction)
        }
    }

    private func load() async {
        if design != nil { return }
        guard let preview else {
            if let url = Bundle.main.url(forResource: "Design", withExtension: "json"),
               let data = try? Data(contentsOf: url), let design = try? JSONDecoder().decode(RuntimeDesign.self, from: data) {
                runtime.apply(design)
            } else { failure = true }
            return
        }
        var lastSnapshot: Data?
        let decoder = JSONDecoder()
        while !Task.isCancelled {
            do {
                let (data, _) = try await URLSession.shared.data(from: preview.appending(path: "design.json"))
                if data != lastSnapshot {
                    runtime.apply(try decoder.decode(RuntimeDesign.self, from: data))
                    lastSnapshot = data
                }
            } catch { failure = true }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
