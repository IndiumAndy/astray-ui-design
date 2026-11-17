import SwiftUI

struct Workbench: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast

    @Bindable var session: ReviewSession
    let focusSearchOnLaunch: Bool

    private var palette: WorkbenchPalette { WorkbenchPalette(appearance, contrast) }

    var body: some View {
        HStack(spacing: 0) {
            if session.libraryVisible {
                ComponentLibrary(
                    palette: palette,
                    focusOnLaunch: focusSearchOnLaunch,
                    searchRequest: session.searchRequest
                )
                .frame(width: 240)
                Divider()
            }

            ReviewCanvas(state: session.state, device: session.device, zoom: session.zoom, palette: palette)
                .layoutPriority(1)

            if session.trailingPaneVisible {
                trailingPane
            }
        }
        .foregroundStyle(palette.ink)
        .navigationTitle(session.state.documentTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    session.libraryVisible.toggle()
                } label: {
                    Label("组件库", systemImage: "sidebar.left")
                }
                .accessibilityLabel(session.libraryVisible ? "隐藏组件库" : "显示组件库")
                .help(session.libraryVisible ? "隐藏组件库" : "显示组件库")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("画板设备", selection: $session.device) {
                        ForEach(ReviewDevice.allCases) { device in
                            Text("\(device.name) · \(device.dimensions)").tag(device)
                        }
                    }
                } label: {
                    Label(session.device.name, systemImage: "iphone")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("画板设备")
                .accessibilityValue(session.device.name)
                .help("画板设备")

                Menu {
                    Picker("缩放", selection: $session.zoom) {
                        ForEach(CanvasZoom.allCases) { zoom in
                            Text(zoom.title).tag(zoom)
                        }
                    }
                } label: {
                    Text(session.zoom.title)
                }
                .accessibilityLabel("缩放")
                .accessibilityValue(session.zoom.title)
                .help("画布缩放")

                Toggle(isOn: $session.snapEnabled) {
                    Text("吸附")
                }
                .toggleStyle(.checkbox)
                .help(session.snapEnabled ? "关闭吸附" : "打开吸附")

                if session.state != .blank {
                    Button {
                        session.trailingPaneVisible.toggle()
                    } label: {
                        Label(
                            session.state == .flow ? "iPhone 预览" : "检查器",
                            systemImage: session.state == .flow ? "play.rectangle" : "sidebar.right"
                        )
                    }
                    .help(session.trailingPaneVisible ? "隐藏右栏" : "显示右栏")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: session.newDesign) {
                    Label("新建", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accentFill)
                .help("新建（⌘N）")
            }
        }
        .toolbarRole(.editor)
    }

    @ViewBuilder
    private var trailingPane: some View {
        switch session.state {
        case .blank:
            EmptyView()
        case .selection:
            Divider()
            SelectionInspector(device: session.device, palette: palette)
                .frame(width: 272)
        case .flow:
            Divider()
            PhonePreview(device: session.device, palette: palette)
                .frame(width: 304)
        }
    }
}
