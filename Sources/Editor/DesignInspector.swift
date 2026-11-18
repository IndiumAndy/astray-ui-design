import SwiftUI

struct DesignInspector: View {
    let editor: DesignEditing
    let layer: DesignLayer
    let parent: DesignLayer?
    let palette: WorkbenchPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(layer.kind.name, systemImage: layer.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                geometry
                if layer.kind.editsText {
                    InspectorEntry(label: layer.kind == .input ? "占位文字" : "文字", value: layer.text, palette: palette) { text in
                        editor.update(layer.id, action: "编辑文字") { $0.text = text }
                        return true
                    }
                }
                if layer.kind == .setting {
                    number("间距", value: layer.spacing, range: 0...layer.maximumSpacing, unit: "pt") {
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
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(palette.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("属性检查器")
    }

    private var geometry: some View {
        let frame = parent.map { $0.childFrame(layer, in: $0.frame) } ?? layer.frame
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("位置与大小").font(.system(size: 12, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("pt").font(.system(size: 11)).foregroundStyle(palette.muted)
                    .accessibilityLabel("单位，点")
            }
            HStack(spacing: 8) {
                coordinate("X", title: "X 坐标", value: frame.minX, range: 0...max(0, editor.page.bounds.width - frame.width)) {
                    editor.setFrame(frame.offsetBy(dx: $0 - frame.minX, dy: 0), of: layer.id)
                }
                coordinate("Y", title: "Y 坐标", value: frame.minY, range: 0...max(0, editor.page.bounds.height - frame.height)) {
                    editor.setFrame(frame.offsetBy(dx: 0, dy: $0 - frame.minY), of: layer.id)
                }
            }
            HStack(spacing: 8) {
                coordinate("W", title: "宽度", value: frame.width, range: layer.kind.minimumSize.width...max(layer.kind.minimumSize.width, editor.page.bounds.width - frame.minX)) {
                    editor.setFrame(CGRect(x: frame.minX, y: frame.minY, width: $0, height: frame.height), of: layer.id)
                }
                coordinate("H", title: "高度", value: frame.height, range: layer.kind.minimumSize.height...max(layer.kind.minimumSize.height, editor.page.bounds.height - frame.minY)) {
                    editor.setFrame(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: $0), of: layer.id)
                }
            }
        }
    }

    @ViewBuilder
    private func coordinate(_ label: String, title: String, value: CGFloat, range: ClosedRange<CGFloat>, apply: @escaping (CGFloat) -> Void) -> some View {
        if parent != nil {
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

private struct InspectorEntry: View {
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
