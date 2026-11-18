import SwiftUI

struct BehaviorInspector: View {
    let editor: DesignEditing
    let layer: DesignLayer
    let palette: WorkbenchPalette
    @State private var editingList = false

    private var behavior: LayerBehavior { layer.behavior ?? LayerBehavior() }
    private var isField: Bool { layer.kind == .input || layer.kind == .toggle }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layer.kind.hasAction {
                Button { editor.connectionSetup = layer.id } label: {
                    Label(actionTitle, systemImage: "arrow.turn.down.right")
                        .lineLimit(1)
                }
                .help("设置事件")
                .accessibilityLabel("设置事件")
                .accessibilityValue(actionTitle)
            }
            if isField || [.title, .label].contains(layer.kind) { fieldBinding }
            if isField { fieldEvents }
            if layer.kind == .contactList { listSettings }
            if [.button, .input, .listRow, .toggle, .contactList].contains(layer.kind) { statePicker }
        }
        .sheet(isPresented: $editingList) {
            ListSettings(editor: editor, layer: layer, initial: behavior.list ?? defaultList)
        }
    }

    private var actionTitle: String {
        if let action = behavior.action {
            if let id = action.target.flatMap(UUID.init(uuidString:)),
               let target = editor.project.pages.first(where: { $0.id == id }) {
                return "\(action.kind.title) · \(target.title)"
            }
            if let name = action.name, !name.isEmpty { return name }
            return action.kind.title
        }
        if let id = layer.destination { return "打开页面 · \(editor.project.page(withID: id).title)" }
        if layer.savesContact == true { return "保存联系人" }
        return "设置事件"
    }

    @ViewBuilder private var fieldBinding: some View {
        Picker("值来源", selection: Binding(get: { behavior.binding?.source }, set: { source in
            set("更改值来源") { behavior in
                behavior.binding = source.map {
                    FieldBinding(source: $0, key: behavior.binding?.key ?? layer.field?.rawValue ?? "",
                                 sample: behavior.binding?.sample)
                }
            }
        })) {
            Text("本地").tag(nil as BindingSource?)
            ForEach(BindingSource.allCases) { Text($0.title).tag(Optional($0)) }
        }
        if let binding = behavior.binding {
            entry("字段键", binding.key) { text in set("编辑字段键") { $0.binding?.key = text } }
            if layer.kind == .toggle {
                Toggle("示例值", isOn: Binding(get: { binding.sample?.flag ?? layer.isOn }, set: { value in
                    set("编辑示例值") { $0.binding?.sample = .flag(value) }
                }))
                .controlSize(.small)
            } else {
                entry("示例值", binding.sample?.text ?? "") { text in set("编辑示例值") { $0.binding?.sample = .text(text) } }
            }
        }
    }

    @ViewBuilder private var fieldEvents: some View {
        entry("表单名称", behavior.form ?? "") { text in set("指定表单") { $0.form = text.isEmpty ? nil : text } }
        if behavior.form != nil {
            entry("提交键", behavior.submissionKey ?? behavior.binding?.key ?? layer.id.uuidString) { text in
                set("编辑提交键") { $0.submissionKey = text.isEmpty ? nil : text }
            }
            if layer.kind == .input { validation }
        }
        entry("值改变时", behavior.changeAction ?? "") { text in
            set("设置即时动作") { $0.changeAction = text.isEmpty ? nil : text }
        }
    }

    private var validation: some View {
        let rules = behavior.rules ?? FieldRules()
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("必填", isOn: Binding(get: { rules.required }, set: { value in editRules { $0.required = value } }))
            Toggle("校验邮箱", isOn: Binding(get: { rules.email }, set: { value in editRules { $0.email = value } }))
            length("最少字符", value: rules.minimum) { value in
                editRules { rules in
                    rules.minimum = value
                    if let value, let maximum = rules.maximum, maximum < value { rules.maximum = value }
                }
            }
            length("最多字符", value: rules.maximum) { value in
                editRules { rules in
                    rules.maximum = value
                    if let value, let minimum = rules.minimum, minimum > value { rules.minimum = value }
                }
            }
            if rules.required || rules.email || rules.minimum != nil || rules.maximum != nil {
                entry("错误提示", rules.message ?? "") { text in editRules { $0.message = text.isEmpty ? nil : text } }
            }
        }
        .controlSize(.small)
    }

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("控件状态", selection: Binding(get: { behavior.state ?? .normal }, set: { state in
                set("切换控件状态") { $0.state = state == .normal ? nil : state }
            })) {
                ForEach(ControlState.allCases.filter {
                    switch layer.kind {
                    case .button: true
                    case .input: $0 != .busy
                    default: $0 == .normal || $0 == .disabled
                    }
                }) { Text($0.title).tag($0) }
            }
            if behavior.state == .busy || behavior.state == .error {
                entry("状态文字", behavior.stateMessage ?? "") { text in
                    set("修改状态文字") { $0.stateMessage = text.isEmpty ? nil : text }
                }
            }
        }
    }

    private var defaultList: ListDesign {
        var list = ListDesign()
        list.sample.rows = (editor.project.contacts?.prefix(3).map { contact in
            DesignRecord(id: contact.id, fields: Dictionary(uniqueKeysWithValues:
                ContactField.allCases.map { ($0.rawValue, .text(contact[$0])) }))
        }) ?? []
        return list
    }

    private var listSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("配置列表…") { editingList = true }
            Picker("预览状态", selection: Binding(get: { behavior.list?.sample.state ?? .ready }, set: { state in
                set("更改列表预览状态") { behavior in
                    var list = behavior.list ?? defaultList
                    list.sample.state = state
                    behavior.list = list
                }
            })) { ForEach(ListState.allCases) { Text($0.title).tag($0) } }
        }
    }

    private func entry(_ name: String, _ value: String, commit: @escaping (String) -> Void) -> some View {
        InspectorEntry(label: name, value: value, palette: palette) { text in
            commit(text)
            return true
        }
    }

    private func length(_ name: String, value: Int?, commit: @escaping (Int?) -> Void) -> some View {
        InspectorEntry(label: name, value: value.map(String.init) ?? "", palette: palette) { text in
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { commit(nil); return true }
            guard let length = Int(text), (0...4096).contains(length) else { return false }
            commit(length)
            return true
        }
    }

    private func editRules(_ edit: (inout FieldRules) -> Void) {
        set("编辑校验") { behavior in
            var rules = behavior.rules ?? FieldRules()
            edit(&rules)
            behavior.rules = rules == FieldRules() ? nil : rules
        }
    }

    private func set(_ action: String, _ edit: (inout LayerBehavior) -> Void) {
        editor.updateBehavior(layer.id, action: action, edit)
    }
}
