import SwiftUI

struct DesignInspector: View {
    let editor: DesignEditing
    let layer: DesignLayer
    let parent: DesignLayer?
    let palette: WorkbenchPalette
    @State private var namingStyle = false
    @State private var styleName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(editor.selectedIDs.count > 1 ? "已选 \(editor.selectedIDs.count) 个图层" : layer.kind.name,
                          systemImage: editor.selectedIDs.count > 1 ? "square.on.square" : layer.kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                }
                if editor.selectedIDs.count > 1 {
                    Menu("排列") { arrangementCommands(editor) }
                } else {
                    properties
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(palette.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("属性检查器")
        .alert("新建按钮样式", isPresented: $namingStyle) {
            TextField("样式名称", text: $styleName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let name = styleName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { editor.newButtonStyle(from: layer, name: name) }
            }
            .disabled(styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private var properties: some View {
        if [.input, .title, .label, .toggle, .button, .listRow, .contactList].contains(layer.kind) {
            BehaviorInspector(editor: editor, layer: layer, palette: palette)
            Divider()
        }
        geometry
        if layer.kind.isContainer { arrangement }
        if let parent, parent.kind.isContainer { order(parent) }
        if layer.kind.editsText {
            if layer.kind == .label || layer.kind == .title {
                Text("文字").font(.system(size: 12)).foregroundStyle(palette.propertyLabel)
                MultilineDesignText(label: "文字", text: layer.text, palette: palette) { text in
                    editor.update(layer.id, action: "编辑文字") { $0.text = text }
                }
            } else {
                InspectorEntry(label: layer.kind == .input ? "显示名称" : layer.kind == .image ? "替代文字" : "文字",
                               value: layer.text, palette: palette) { text in
                    editor.update(layer.id, action: "编辑文字") { $0.text = text }
                    return true
                }
            }
            if editor.usesDeviceLayout {
                Text("文字应用于所有设备").font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
        }
        if layer.kind == .image {
            Button(layer.image == nil ? "选择图片…" : "更换图片…") {
                editor.importImage(reference: false, layerID: layer.id)
            }
        }
        if layer.kind == .input {
            Text("提示文字").font(.system(size: 12)).foregroundStyle(palette.propertyLabel)
            MultilineDesignText(label: "提示文字", text: layer.fieldHint ?? "", palette: palette) { text in
                editor.update(layer.id, action: "编辑提示文字") { $0.fieldHint = text.isEmpty ? nil : text }
            }
            Picker("输入类型", selection: Binding(get: { layer.inputType ?? .text }, set: { type in
                editor.update(layer.id, action: "更改输入类型") { $0.inputType = type }
            })) {
                ForEach(DesignInputType.allCases) { type in Text(type.title).tag(type) }
            }
        }
        if layer.behavior?.binding == nil && (layer.field != nil || editor.project.contacts != nil) && (layer.kind == .input || layer.kind == .title) {
            Picker("联系人字段", selection: Binding(get: { layer.field }, set: { field in
                editor.update(layer.id, action: "绑定字段") { $0.field = field }
            })) {
                Text("无").tag(nil as ContactField?)
                ForEach(ContactField.allCases.filter { layer.kind == .title || $0.isEditable }) { field in
                    Text(field.title).tag(Optional(field))
                }
            }
        }
        if layer.kind == .button {
            buttonStyleControls
            Toggle("次要按钮", isOn: Binding(get: { layer.secondaryButton == true }, set: { value in
                editor.update(layer.id, action: "修改按钮外观") { $0.secondaryButton = value ? true : nil }
            })).controlSize(.small)
        }
        if layer.kind == .setting {
            number("间距", value: layer.placement(for: editor.scope).gap ?? layer.spacing,
                   range: 0...max(0, min(96, editor.frame(of: layer).width - 108)), unit: "pt") {
                editor.setSpacing($0, of: layer.id)
            }
        }
        if layer.kind == .toggle {
            Toggle("开启", isOn: Binding(get: { layer.isOn }, set: { value in
                editor.update(layer.id, action: "切换开关") { $0.isOn = value }
            }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("inspector-toggle")
        }
        if parent == nil, (layer.kind.isContainer || layer.kind == .setting), !layer.children.isEmpty, !editor.usesDeviceLayout {
            Button("拆分组合") { editor.ungroup(layer) }
        }
    }

    private var buttonStyleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("按钮样式", selection: Binding(get: { layer.styleID }, set: { editor.useButtonStyle($0, for: layer) })) {
                Text("独立样式").tag(nil as UUID?)
                ForEach(editor.project.buttonStyles ?? []) { style in Text(style.name).tag(Optional(style.id)) }
            }
            number("圆角", value: layer.cornerRadius ?? editor.buttonStyle(for: layer)?.radius ?? 8, range: 0...48, unit: "pt") {
                value in editor.update(layer.id, action: "调整圆角") { $0.cornerRadius = value }
            }
            if let style = editor.buttonStyle(for: layer) {
                let height = editor.frame(of: layer).height
                if height != style.height || (layer.cornerRadius ?? style.radius) != style.radius {
                    Button("更新样式") { editor.updateButtonStyle(from: layer) }
                    Text("更新后会应用到引用此样式的按钮").font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
            } else {
                Button("新建项目样式…") {
                    styleName = ""
                    namingStyle = true
                }
            }
        }
    }

    private var arrangement: some View {
        let spec = layer.placement(for: editor.scope)
        return VStack(alignment: .leading, spacing: 8) {
            Picker("排列", selection: Binding(get: { spec.arrangement ?? .free }, set: {
                value in editor.setPlacement(layer.id) { $0.arrangement = value }
            })) {
                ForEach(Arrangement.allCases) { item in Text(item.title).tag(item) }
            }
            if spec.arrangement != .free {
                number("间距", value: spec.gap ?? 12, range: 0...192, unit: "pt") { value in
                    editor.setContainerGap(layer.id, to: value)
                }
            }
            if spec.arrangement == .grid {
                Picker("列数", selection: Binding(get: { spec.columns ?? 2 }, set: { value in
                    editor.setPlacement(layer.id) { $0.columns = value }
                })) {
                    ForEach(2...6, id: \.self) { Text(String($0)).tag($0) }
                }
            }
            if spec.arrangement == .grid || spec.arrangement == .horizontal {
                Toggle("窄屏自动堆叠", isOn: Binding(get: { spec.stackAtNarrowWidth == true }, set: { value in
                    editor.setPlacement(layer.id) { $0.stackAtNarrowWidth = value }
                })).help("容器宽度小于 420 pt 时改为纵排")
            }
        }
    }

    @ViewBuilder private func order(_ parent: DesignLayer) -> some View {
        let siblings = editor.siblings(of: parent)
        if parent.placement(for: editor.scope).arrangement != .free,
           let index = siblings.firstIndex(where: { $0.id == layer.id }) {
            HStack {
                Text("顺序").font(.system(size: 12))
                Spacer()
                Button { editor.reorder(layer.id, to: index - 1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).accessibilityLabel("前移一项").help("前移一项")
                Button { editor.reorder(layer.id, to: index + 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == siblings.count - 1).accessibilityLabel("后移一项").help("后移一项")
            }
            InspectorEntry(label: "移至第", accessibilityTitle: "移至第几项", value: String(index + 1), palette: palette,
                           hint: "1–\(siblings.count) 项", unit: "项") { text in
                guard let value = Int(text), (1...siblings.count).contains(value) else { return false }
                editor.reorder(layer.id, to: value - 1)
                return true
            }
        }
    }

    private var geometry: some View {
        let frame = editor.frame(of: layer)
        let placement = layer.placement(for: editor.scope)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("位置与大小").font(.system(size: 12, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("pt").font(.system(size: 11)).foregroundStyle(palette.muted)
                    .accessibilityLabel("单位，点")
            }
            Text(editor.scopeTitle).font(.system(size: 11)).foregroundStyle(palette.secondary)
            if parent == nil || parent?.placement(for: editor.scope).arrangement == .free {
                HStack(spacing: 8) {
                    coordinate("X", title: "X 坐标", value: frame.minX, range: 0...max(0, editor.page.bounds.width - frame.width)) {
                        editor.setFrame(frame.offsetBy(dx: $0 - frame.minX, dy: 0), of: layer.id, resizing: false)
                    }
                    if placement.region == nil || placement.region == .body {
                        coordinate("Y", title: "Y 坐标", value: frame.minY, range: 0...max(0, DesignPage.maximumContentHeight - frame.height)) {
                            editor.setFrame(frame.offsetBy(dx: 0, dy: $0 - frame.minY), of: layer.id, resizing: false)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                coordinate("W", title: "宽度", value: frame.width, range: layer.kind.minimumSize.width...max(layer.kind.minimumSize.width, editor.page.bounds.width - frame.minX)) {
                    editor.setFrame(CGRect(x: frame.minX, y: frame.minY, width: $0, height: frame.height), of: layer.id)
                }
                coordinate("H", title: "高度", value: frame.height, range: layer.kind.minimumSize.height...max(layer.kind.minimumSize.height, DesignPage.maximumContentHeight - frame.minY)) {
                    editor.setFrame(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: $0), of: layer.id)
                }
            }
            if parent?.kind != .setting {
                Picker("宽度", selection: Binding(get: { placement.width ?? .fixed }, set: {
                    value in editor.setPlacement(layer.id) { $0.width = value }
                })) {
                    ForEach(LayoutSizeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker("高度", selection: Binding(get: { placement.height ?? .fixed }, set: {
                    value in editor.setPlacement(layer.id) { $0.height = value }
                })) {
                    ForEach(LayoutSizeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                if parent == nil {
                    Picker("滚动", selection: Binding(get: { placement.region ?? .body }, set: {
                        value in editor.setPlacement(layer.id) { $0.region = value }
                    })) {
                        ForEach(LayoutRegion.allCases) { region in Text(region.title).tag(region) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coordinate(_ label: String, title: String, value: CGFloat, range: ClosedRange<CGFloat>, apply: @escaping (CGFloat) -> Void) -> some View {
        if parent?.kind == .setting {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(palette.propertyLabel)
                Spacer(minLength: 4)
                Text(Double(value).formatted(Self.numberFormat)).monospacedDigit()
            }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(Double(value).formatted(Self.numberFormat))
        } else {
            number(label, title: title, value: value, range: range, apply: apply)
        }
    }

    private static let numberFormat: FloatingPointFormatStyle<Double> = .number.grouping(.never).precision(.fractionLength(0...2))

    private func number(_ label: String, title: String? = nil, value: CGFloat, range: ClosedRange<CGFloat>, unit: String? = nil,
                        apply: @escaping (CGFloat) -> Void) -> some View {
        InspectorEntry(
            label: label, accessibilityTitle: title, value: Double(value).formatted(Self.numberFormat), palette: palette,
            hint: "\(Double(range.lowerBound).formatted(Self.numberFormat))–\(Double(range.upperBound).formatted(Self.numberFormat)) pt",
            unit: unit
        ) { text in
            guard let parsed = InspectorNumber.parse(text), range.contains(parsed) else { return false }
            apply(parsed)
            return true
        }
    }
}

enum InspectorNumber {
    static func parse(_ text: String, locale: Locale = .current) -> CGFloat? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        let fullRange = NSRange(input.startIndex..., in: input)
        var consumed = fullRange
        var result: AnyObject?
        guard !input.isEmpty,
              (try? formatter.getObjectValue(&result, for: input, range: &consumed)) != nil,
              consumed == fullRange,
              let number = result as? NSNumber, number.doubleValue.isFinite else { return nil }
        return CGFloat(number.doubleValue)
    }
}

struct InspectorEntry: View {
    let label: String
    var accessibilityTitle: String? = nil
    let value: String
    let palette: WorkbenchPalette
    var hint: String? = nil
    var unit: String? = nil
    let commit: (String) -> Bool

    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.propertyLabel)
                    .accessibilityHidden(true)
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(hint == nil ? .leading : .trailing)
                    .monospacedDigit()
                    .font(.system(size: 13))
                    .focused($focused)
                    .accessibilityLabel(accessibilityTitle ?? label)
                    .accessibilityIdentifier("inspector-\(label)")
                    .onSubmit { save() }
                    .onExitCommand {
                        invalid = false
                        draft = value
                        focused = false
                    }
                if let unit {
                    Text(unit).font(.system(size: 11)).foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(palette.field, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(invalid ? Color.red : focused ? palette.accent : palette.fieldSeam,
                                  lineWidth: focused || invalid ? 1.5 : 0.5)
                    .allowsHitTesting(false)
            }
            if invalid, let hint {
                Text("请输入 \(hint)")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, value in
            draft = value
            invalid = false
        }
        .onChange(of: focused) { wasFocused, focused in
            if wasFocused && !focused { save() }
        }
    }

    private func save() {
        guard draft != value else {
            invalid = false
            return
        }
        invalid = !commit(draft)
    }
}


private struct MultilineDesignText: View {
    let label: String
    let text: String
    let palette: WorkbenchPalette
    let apply: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(2...5)
            .font(.system(size: 13))
            .padding(8)
            .background(palette.field, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? palette.accent : palette.fieldSeam)
                    .allowsHitTesting(false)
            }
            .focused($focused)
            .accessibilityIdentifier("inspector-\(label)")
            .onChange(of: text, initial: true) { _, value in draft = value }
            .onChange(of: focused) { wasFocused, focused in
                if wasFocused && !focused { commit() }
            }
            .onSubmit { commit() }
            .onExitCommand {
                draft = text
                focused = false
            }
    }

    private func commit() {
        if draft != text { apply(draft) }
    }
}
