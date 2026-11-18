import SwiftUI

struct WorkbenchToolbar: View {
    @Bindable var session: ReviewSession
    let layout: WorkbenchLayout
    let palette: WorkbenchPalette
    let title: String
    @State private var showsArtboard = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                toolbarButton(
                    "sidebar.left",
                    title: session.libraryVisible ? "隐藏侧栏" : "显示侧栏",
                    tooltip: "侧栏（⌥⌘L）",
                    active: session.libraryVisible
                ) {
                    session.libraryVisible.toggle()
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, WorkbenchLayout.windowControlsClearance)
            .frame(width: session.libraryVisible ? layout.sidebarWidth : WorkbenchLayout.closedNavigatorToolbarWidth)

            ZStack {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: max(0, layout.canvasWidth / 2 - 84), alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)

                HStack(spacing: 8) {
                    toolbarButton("plus", title: "插入组件", tooltip: "打开组件库") {
                        session.requestSearch()
                    }

                    toolbarButton(
                        "iphone",
                        title: "iPhone 预览",
                        tooltip: session.previewVisible ? "关闭 iPhone 预览（⌥⌘P）" : "打开 iPhone 预览（⌥⌘P）",
                        active: session.previewVisible
                    ) {
                        session.previewVisible.toggle()
                    }

                    if let editor = session.editor {
                        toolbarButton("rectangle", title: "画板设置", tooltip: "设备、参考布局与底图",
                                      active: showsArtboard || editor.usesDeviceLayout,
                                      value: editor.scopeTitle) { showsArtboard.toggle() }
                            .popover(isPresented: $showsArtboard, arrowEdge: .bottom) {
                                ArtboardControls(editor: editor, palette: palette)
                            }
                        Menu {
                            Button("在 iPhone 模拟器运行", action: session.runPhone)
                            Button("在默认浏览器运行", action: session.runWeb)
                                .disabled(session.run.webBusy)
                            Divider()
                            Button("导出源码", action: session.exportProject)
                        } label: {
                            ToolbarFace(palette: palette) {
                                if session.run.webBusy {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "play").font(.system(size: 14, weight: .medium))
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("运行与导出")
                    }

                    palette.groupSeam
                        .frame(width: 1, height: 14)
                        .accessibilityHidden(true)

                    Menu {
                        CanvasZoomOptions(session: session)
                    } label: {
                        ToolbarFace(palette: palette) {
                            Text("\(Int((layout.canvasScale * 100).rounded()))%")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("画布缩放")
                    .accessibilityValue("\(Int((layout.canvasScale * 100).rounded()))%")
                    .help("画布缩放")

                    toolbarButton(
                        session.snapEnabled ? "checkmark.square" : "square.dashed",
                        title: "吸附",
                        tooltip: session.snapEnabled ? "关闭吸附" : "打开吸附",
                        active: session.snapEnabled,
                        value: session.snapEnabled ? "开启" : "关闭"
                    ) {
                        session.snapEnabled.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: WorkbenchLayout.toolbarHeight)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .accessibilityHidden(true)
            }

            HStack {
                Spacer(minLength: 0)
                toolbarButton(
                    "sidebar.right",
                    title: "属性检查器",
                    tooltip: session.trailingPaneVisible ? "隐藏检查器（⌥⌘I）" : "显示检查器（⌥⌘I）",
                    active: session.trailingPaneVisible
                ) {
                    session.toggleInspector()
                }
            }
            .padding(.trailing, 8)
            .frame(width: session.trailingPaneVisible ? layout.inspectorWidth : WorkbenchLayout.closedInspectorToolbarWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作台工具栏")
    }

    private func toolbarButton(
        _ symbol: String, title: String, tooltip: String, active: Bool = false, value: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ToolbarFace(palette: palette, active: active) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(symbol.hasPrefix("checkmark.square") || symbol == "square.dashed" ? "toolbar-snap" : symbol)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(tooltip)
    }
}

private struct ToolbarFace<Content: View>: View {
    let palette: WorkbenchPalette
    var active = false
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        content
            .foregroundStyle(active ? palette.ink : palette.secondary)
            .frame(width: 28, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(active ? palette.active : hovered ? palette.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
