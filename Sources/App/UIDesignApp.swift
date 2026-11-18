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
            .task(id: configuration.fileURL) {
                session.allowsLocalMCP = false
                if let url = configuration.fileURL { await session.serveLocalMCP(for: url) }
            }
            .onAppear {
                if launch.focusSearch { session.requestSearch() }
            }
            .onChange(of: undoManager, initial: true) { _, manager in
                session.design?.undoManager = manager
            }
            .alert("无法导入图片", isPresented: Binding(
                get: { session.design?.imageIssue != nil },
                set: { if !$0 { session.design?.imageIssue = nil } }
            )) {} message: {
                Text(session.design?.imageIssue ?? "")
            }
            .onChange(of: configuration.document.project) { _, project in
                if let design = session.design, design.selection == nil { design.select(nil) }
                session.run.publish(project)
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
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("新建联系人示例") {
                newDocument { DesignFile(project: .contactExample()) }
            }
            Button("新建交互示例") {
                newDocument { DesignFile(project: .interactionExample()) }
            }
        }
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
                    ForEach(session.editor == nil ? [.phone, .largePhone] : ReviewDevice.allCases) { device in
                        Text(device.name).tag(device)
                    }
                }
                if let editor = session.editor {
                    Toggle("允许本机 MCP", isOn: $session.allowsLocalMCP)
                    Button("显示个人库") {
                        session.libraryVisible = true
                        session.navigatorTab = .personal
                    }
                    Button("存入个人库：所选图层…") { editor.requestLibrarySave(layers: true) }
                        .disabled(editor.selectedTemplateLayers.isEmpty)
                    Button("存入个人库：页面或流程…") { editor.requestLibrarySave(layers: false) }
                    Menu("画板比例") { aspectOptions(editor) }
                    Toggle("展开整页", isOn: Binding(get: { editor.showsFullPage }, set: { editor.showsFullPage = $0 }))
                    Toggle("仅改\(editor.page.deviceLayout.title)布局",
                           isOn: Binding(get: { editor.usesDeviceLayout }, set: { editor.usesDeviceLayout = $0 }))
                    Button("恢复通用布局", action: editor.restoreSharedLayout).disabled(!editor.usesDeviceLayout)
                    Menu("参考布局") {
                        Button("无") { editor.setReference(nil) }
                        ForEach(ReferenceLayout.allCases) { reference in
                            Button(reference.title) { editor.setReference(reference) }
                        }
                    }
                    Button("导入对照底图…") { editor.importImage(reference: true) }
                    Menu("排列所选图层") { arrangementCommands(editor) }
                    Button("复制图层", action: editor.duplicateSelection)
                        .keyboardShortcut("d")
                        .disabled(editor.selection == nil)
                }
                Toggle("吸附", isOn: $session.snapEnabled)
                Menu("缩放") { CanvasZoomOptions(session: session) }
            }
        }
        CommandMenu("运行") {
            if let session, session.editor != nil {
                Button("在 iPhone 模拟器运行", action: session.runPhone)
                Button("在默认浏览器运行", action: session.runWeb)
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(session.run.webBusy)
                Divider()
                Button("导出选中页面…", action: session.exportSelection)
                    .disabled(session.run.exportBusy)
                Button("导出完整工程…", action: session.exportProject)
                    .disabled(session.run.exportBusy)
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
