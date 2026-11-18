import SwiftUI

struct EventSettings: View {
    @Environment(\.dismiss) private var dismiss
    let editor: DesignEditing
    let layer: DesignLayer
    @State private var kind: ActionKind?
    @State private var target: UUID?
    @State private var name: String
    @State private var form: String

    init(editor: DesignEditing, layer: DesignLayer) {
        self.editor = editor
        self.layer = layer
        let event = layer.behavior?.action
        let legacy = layer.destination != nil ? ActionKind.navigate : nil
        _kind = State(initialValue: event?.kind ?? legacy)
        _target = State(initialValue: event?.target.flatMap(UUID.init(uuidString:)) ?? layer.destination)
        _name = State(initialValue: event?.name ?? "")
        _form = State(initialValue: event?.form ?? "")
    }

    private var targets: [DesignPage] { editor.project.pages.filter { $0.id != editor.page.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(layer.name).font(.headline)
            Form {
                Picker("点按时", selection: $kind) {
                    Text(layer.savesContact == true ? "保存联系人" : "无").tag(nil as ActionKind?)
                    ForEach(ActionKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
                if kind == .navigate || kind == .sheet {
                    Picker("目标页面", selection: $target) {
                        Text("选择页面").tag(nil as UUID?)
                        ForEach(targets, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                if kind == .named || kind == .submit { TextField("动作名称", text: $name) }
                if kind == .submit {
                    TextField("表单名称", text: $form)
                    let forms = Set(editor.page.allLayers.compactMap { $0.behavior?.form }).sorted()
                    if !forms.isEmpty {
                        Menu("页面上的表单") { ForEach(forms, id: \.self) { name in Button(name) { form = name } } }
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("完成") {
                    if kind != nil || layer.savesContact != true { editor.connect(layer.id, to: action) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kind != nil && action == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var action: DesignAction? {
        guard let kind else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let form = form.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .navigate, .sheet: return target.map { .page(kind, $0) }
        case .named: return name.isEmpty ? nil : .init(kind: kind, name: name)
        case .submit: return name.isEmpty || form.isEmpty ? nil : .init(kind: kind, name: name, form: form)
        case .back, .dismiss: return .init(kind: kind)
        }
    }
}

struct ListSettings: View {
    @Environment(\.dismiss) private var dismiss
    let editor: DesignEditing
    let layer: DesignLayer
    @State private var list: ListDesign

    init(editor: DesignEditing, layer: DesignLayer, initial: ListDesign) {
        self.editor = editor
        self.layer = layer
        _list = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置列表").font(.headline)
            ScrollView {
                Form {
                    TextField("数据键", text: $list.key)
                    TextField("行标题字段", text: $list.titleKey)
                    TextField("行副标题字段", text: $list.detailKey)
                    Stepper("行高 \(list.rowHeight ?? 56) pt", value: Binding(get: { list.rowHeight ?? 56 },
                                                                    set: { list.rowHeight = $0 }), in: 44...120, step: 4)
                    Section("示例数据") {
                        ForEach($list.sample.rows) { $record in
                            HStack {
                                TextField("标题", text: field(list.titleKey, in: $record))
                                TextField("副标题", text: field(list.detailKey, in: $record))
                                Button(role: .destructive) { list.sample.rows.removeAll { $0.id == record.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .accessibilityLabel("删除该行")
                            }
                        }
                        Button("添加示例行") {
                            list.sample.rows.append(DesignRecord(id: UUID().uuidString, fields: [:]))
                        }
                    }
                    Section("列表状态") {
                        TextField("空数据", text: $list.emptyText)
                        TextField("加载中", text: $list.loadingText)
                        TextField("加载失败", text: $list.failureText)
                        TextField("空态按钮", text: $list.emptyButton)
                        if !list.emptyButton.isEmpty {
                            Picker("按钮打开", selection: Binding(get: { list.emptyAction?.target }, set: { target in
                                list.emptyAction = target.map { DesignAction(kind: .navigate, target: $0) }
                            })) {
                                Text("无").tag(nil as String?)
                                ForEach(editor.project.pages.filter { $0.id != editor.page.id }, id: \.id) {
                                    Text($0.title).tag(Optional($0.id.uuidString))
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: 410)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("完成") {
                    editor.updateBehavior(layer.id, action: "配置列表") { $0.list = list }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(list.key.isEmpty || list.titleKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func field(_ key: String, in record: Binding<DesignRecord>) -> Binding<String> {
        Binding {
            record.wrappedValue.fields[key]?.text ?? ""
        } set: { text in
            record.wrappedValue.fields[key] = .text(text)
        }
    }
}
