import SwiftUI

@main
struct UIDesignApp: App {
    private let launch = ReviewLaunch(arguments: ProcessInfo.processInfo.arguments)

    init() {
        // Let AppKit handle the launch event. A plain launch starts blank;
        // a Finder open event creates only the requested document windows.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: { DesignFile() }) { configuration in
            WorkbenchDocument(configuration: configuration, launch: launch)
        }
        .defaultSize(width: launch.width, height: launch.height)
        .defaultLaunchBehavior(.presented)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { WorkbenchCommands() }
    }
}

private struct WorkbenchDocument: View {
    @Environment(\.undoManager) private var undoManager
    @State private var session: ReviewSession
    let configuration: ReferenceFileDocumentConfiguration<DesignFile>
    let launch: ReviewLaunch

    init(configuration: ReferenceFileDocumentConfiguration<DesignFile>, launch: ReviewLaunch) {
        self.configuration = configuration
        self.launch = launch
        _session = State(initialValue: ReviewSession(
            state: configuration.fileURL == nil ? launch.state : .blank, document: configuration.document
        ))
    }

    var body: some View {
        Workbench(session: session, title: documentTitle)
            .frame(minWidth: 1080, minHeight: 640)
            .background(.background)
            .background {
                WindowControlsAlignment(attachDocument: configuration.document.attach)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .preferredColorScheme(launch.appearance)
            .ignoresSafeArea(.container, edges: .top)
            .focusedSceneValue(\.workbenchSession, session)
            .onAppear {
                if launch.focusSearch { session.requestSearch() }
            }
            .onChange(of: undoManager, initial: true) { _, manager in
                session.design?.undoManager = manager
            }
            .onChange(of: configuration.document.project.page) { _, page in
                if page.selection(session.design?.selectedID) == nil { session.design?.select(nil) }
            }
    }

    private var documentTitle: String {
        if session.state != .blank { return session.state.documentTitle }
        return configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "未命名设计"
    }
}

private extension FocusedValues {
    @Entry var workbenchSession: ReviewSession?
}

private struct WorkbenchCommands: Commands {
    @FocusedValue(\.workbenchSession) private var session

    var body: some Commands {
        CommandMenu("工作台") {
            if let session {
                @Bindable var session = session
                Button(session.libraryVisible ? "隐藏侧栏" : "显示侧栏") {
                    session.libraryVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("搜索组件", action: session.requestSearch)
                    .keyboardShortcut("f")
                Button(session.trailingPaneVisible ? "隐藏检查器" : "显示检查器", action: session.toggleInspector)
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
                Menu("缩放") { CanvasZoomOptions(session: session) }
            }
        }
        CommandMenu("设计稿") {
            if let session {
                ForEach(ReviewState.allCases) { state in
                    Button(state == .blank ? "返回项目画板" : state.reviewTitle) { session.open(state) }
                        .keyboardShortcut(state.shortcut, modifiers: [.command, .option])
                }
            }
        }
    }
}
