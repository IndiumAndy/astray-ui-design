import SwiftUI

struct Workbench: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast

    @Bindable var session: ReviewSession
    let focusSearchOnLaunch: Bool

    private var palette: WorkbenchPalette { WorkbenchPalette(appearance, contrast) }

    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { session.libraryVisible ? .all : .detailOnly },
            set: { session.libraryVisible = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columns) {
            ComponentLibrary(
                palette: palette,
                focusOnLaunch: focusSearchOnLaunch,
                searchRequest: session.searchRequest,
                searchRevealsLibrary: session.searchRevealsLibrary
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 272)
        } detail: {
            ReviewCanvas(state: session.state, device: session.device, zoom: session.zoom, palette: palette)
                .inspector(isPresented: $session.trailingPaneVisible) {
                    trailingPane
                        .inspectorColumnWidth(min: 256, ideal: 288, max: 352)
                }
                .toolbar { tools }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(session.state.documentTitle)
    }

    @ToolbarContentBuilder
    private var tools: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: session.newDesign) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建")
            .help("新建（⌘N）")
        }
        .unframed()

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("画板设备", selection: $session.device) {
                    ForEach(ReviewDevice.allCases) { device in
                        Text("\(device.name) · \(device.dimensions)").tag(device)
                    }
                }
            } label: {
                Image(systemName: "iphone")
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("画板设备")
            .accessibilityValue(session.device.name)
            .help("画板设备 · \(session.device.name)")

            Menu {
                Picker("缩放", selection: $session.zoom) {
                    ForEach(CanvasZoom.allCases) { zoom in
                        Text(zoom.title).tag(zoom)
                    }
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("画布缩放")
            .accessibilityValue(session.zoom.title)
            .help("画布缩放 · \(session.zoom.title)")

            Button {
                session.snapEnabled.toggle()
            } label: {
                Image(systemName: session.snapEnabled ? "checkmark.square" : "square.dashed")
                    .foregroundStyle(session.snapEnabled ? palette.accent : palette.secondary)
            }
            .accessibilityLabel("吸附")
            .accessibilityValue(session.snapEnabled ? "开启" : "关闭")
            .help(session.snapEnabled ? "关闭吸附" : "打开吸附")
        }
        .unframed()

        ToolbarItem(placement: .primaryAction) {
            Button {
                session.trailingPaneVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(session.trailingPaneVisible ? palette.accent : palette.secondary)
            }
            .disabled(session.state == .blank)
            .accessibilityLabel(session.state == .flow ? "iPhone 预览" : "检查器")
            .accessibilityValue(session.trailingPaneVisible ? "显示" : "隐藏")
            .help(session.trailingPaneVisible ? "隐藏右栏（⌥⌘I）" : "显示右栏（⌥⌘I）")
        }
        .unframed()
    }

    @ViewBuilder
    private var trailingPane: some View {
        switch session.state {
        case .blank:
            EmptyView()
        case .selection:
            SelectionInspector(device: session.device, palette: palette)
        case .flow:
            PhonePreview(device: session.device, palette: palette)
        }
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder
    func unframed() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
