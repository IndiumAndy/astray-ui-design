import SwiftUI

@main
struct UIDesignApp: App {
    private let launch = ReviewLaunch(arguments: ProcessInfo.processInfo.arguments)
    @State private var session = ReviewSession()

    var body: some Scene {
        @Bindable var session = session
        Window("UI Design", id: "workbench") {
            Workbench(session: session)
            .frame(minWidth: 1080, minHeight: 640)
            .background(.background)
            .background {
                WindowControlsAlignment()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .preferredColorScheme(launch.appearance)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                session.open(launch.state)
                if launch.focusSearch { session.requestSearch() }
            }
        }
        .defaultSize(width: launch.width, height: launch.height)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建", action: session.newDesign)
                    .keyboardShortcut("n")
            }
            CommandMenu("工作台") {
                Button(session.libraryVisible ? "隐藏侧栏" : "显示侧栏") {
                    session.libraryVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("搜索组件", action: session.requestSearch)
                    .keyboardShortcut("f")
                Button(session.trailingPaneVisible ? "隐藏检查器" : "显示检查器") {
                    session.trailingPaneVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button(session.previewVisible ? "关闭 iPhone 预览" : "打开 iPhone 预览") {
                    session.previewVisible.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Divider()
                Picker("画板设备", selection: $session.device) {
                    ForEach(ReviewDevice.allCases) { device in
                        Text(device.name).tag(device)
                    }
                }
                Toggle("吸附", isOn: $session.snapEnabled)
                Picker("缩放", selection: $session.zoom) {
                    ForEach(CanvasZoom.allCases) { zoom in
                        Text(zoom.title).tag(zoom)
                    }
                }
            }
            CommandMenu("设计稿") {
                ForEach(ReviewState.allCases) { state in
                    Button(state.reviewTitle) { session.open(state) }
                        .keyboardShortcut(state.shortcut, modifiers: [.command, .option])
                }
            }
        }
    }
}
