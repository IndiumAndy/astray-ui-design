import SwiftUI

struct ArtboardControls: View {
    @Bindable var editor: DesignEditing
    let palette: WorkbenchPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("设备", selection: Binding(
                get: { editor.page.customSize == nil ? editor.page.device : nil },
                set: { if let device = $0 { editor.setDevice(device) } }
            )) {
                ForEach(ReviewDevice.allCases) { device in Text(device.name).tag(Optional(device)) }
                if editor.page.customSize != nil { Text("自定义").tag(nil as ReviewDevice?) }
            }
            HStack(spacing: 8) {
                dimension("宽", value: editor.page.size.width) {
                    editor.setCustomSize(CGSize(width: $0, height: editor.page.size.height))
                }
                dimension("高", value: editor.page.size.height) {
                    editor.setCustomSize(CGSize(width: editor.page.size.width, height: $0))
                }
                Button {
                    editor.rotateCanvas()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityLabel("交换宽高")
                .help("交换宽高")
            }
            Menu("比例") { aspectOptions(editor) }
            Picker("编辑范围", selection: $editor.usesDeviceLayout) {
                Text("通用布局").tag(false)
                Text("仅改\(editor.page.deviceLayout.title)布局").tag(true)
            }
            if editor.usesDeviceLayout {
                Button("恢复通用布局", action: editor.restoreSharedLayout)
                    .disabled(!editor.page.allLayers.contains { $0.deviceLayouts?[editor.page.deviceLayout.rawValue] != nil })
            }
            Toggle("展开整页", isOn: $editor.showsFullPage)
            Divider()
            Picker("参考布局", selection: Binding(get: { editor.page.reference }, set: { editor.setReference($0) })) {
                Text("无").tag(nil as ReferenceLayout?)
                ForEach(ReferenceLayout.allCases) { item in Text(item.title).tag(Optional(item)) }
            }
            if let image = editor.page.referenceImage {
                Text(image.name)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Toggle("显示对照底图", isOn: Binding(get: { !image.isHidden }, set: { visible in
                    editor.updateReference("切换对照底图") { $0.isHidden = !visible }
                }))
                Toggle("锁定位置", isOn: Binding(get: { image.isLocked }, set: { locked in
                    editor.updateReference("切换底图锁定") { $0.isLocked = locked }
                }))
                InspectorEntry(label: "不透明度", value: String(Int((image.opacity * 100).rounded())), palette: palette,
                               hint: "0–100%", unit: "%") { text in
                    guard let opacity = InspectorNumber.parse(text), (0...100).contains(opacity) else { return false }
                    editor.updateReference("调整底图不透明度") { $0.opacity = opacity / 100 }
                    return true
                }
                HStack {
                    Button("更换底图") { editor.importImage(reference: true) }
                    Button("移除底图", action: editor.removeReferenceImage)
                }
            } else {
                Button("导入对照底图…") { editor.importImage(reference: true) }
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画板设置")
    }

    private func dimension(_ label: String, value: CGFloat, commit: @escaping (CGFloat) -> Void) -> some View {
        InspectorEntry(label: label, value: Double(value).formatted(.number.grouping(.never).precision(.fractionLength(0...1))),
                       palette: palette, hint: "160–4096 pt", unit: "pt") { text in
            guard let value = InspectorNumber.parse(text), (160...4096).contains(value) else { return false }
            commit(value)
            return true
        }
    }
}

@MainActor @ViewBuilder func aspectOptions(_ editor: DesignEditing) -> some View {
    Button("1∶1") { editor.setAspect(width: 1, height: 1) }
    Button("4∶3") { editor.setAspect(width: 4, height: 3) }
    Button("3∶2") { editor.setAspect(width: 3, height: 2) }
    Button("16∶10") { editor.setAspect(width: 16, height: 10) }
    Button("16∶9") { editor.setAspect(width: 16, height: 9) }
    Button("21∶9") { editor.setAspect(width: 21, height: 9) }
}

@MainActor @ViewBuilder func arrangementCommands(_ editor: DesignEditing) -> some View {
    ForEach([Arrangement.vertical, .horizontal, .grid]) { arrangement in
        Button(arrangement.title) { editor.arrangeSelection(arrangement) }
            .disabled(editor.selectedIDs.count < 2 || editor.usesDeviceLayout)
    }
}
