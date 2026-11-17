import SwiftUI

@main
struct UIDesignApp: App {
    private let launch = ReviewLaunch(arguments: ProcessInfo.processInfo.arguments)
    @State private var session = ReviewSession()

    var body: some Scene {
        @Bindable var session = session
        Window("UI Design", id: "workbench") {
            Workbench(
                session: session,
                focusSearchOnLaunch: launch.focusSearch
            )
            .frame(minWidth: 1080, minHeight: 640)
            .background(.background)
            .preferredColorScheme(launch.appearance)
            .onAppear { session.open(launch.state) }
        }
        .defaultSize(width: launch.width, height: launch.height)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建", action: session.newDesign)
                    .keyboardShortcut("n")
            }
            CommandMenu("工作台") {
                Button(session.libraryVisible ? "隐藏组件库" : "显示组件库") {
                    session.libraryVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("搜索组件", action: session.requestSearch)
                    .keyboardShortcut("f")
                Button(session.trailingPaneVisible ? "隐藏右栏" : "显示右栏") {
                    session.trailingPaneVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(session.state == .blank)
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
