import AppKit
import Observation

@MainActor @Observable
final class PreviewController {
    let simulator = SimulatorPreview()
    private(set) var webBusy = false
    var issue: PreviewIssue?
    private var server: PreviewServer?
    private var startingServer: Task<URL, Error>?
    private var entry: UUID?

    func publish(_ project: DesignProject) {
        guard let server else { return }
        do { try server.publish(project.runtime(startingAt: entry)) }
        catch { issue = PreviewIssue(text: error.localizedDescription) }
    }

    func startPhone(_ editor: DesignEditing) async {
        do {
            let address = try await address(for: editor)
            guard !Task.isCancelled else { return }
            await simulator.start(address)
        } catch { issue = PreviewIssue(text: error.localizedDescription) }
    }

    func openBrowser(_ editor: DesignEditing) async {
        guard !webBusy else { return }
        webBusy = true
        defer { webBusy = false }
        do {
            let address = try await address(for: editor)
            let dist = try await PreviewBuild.shared.output("Web")
            try server?.serveWeb(from: dist)
            guard NSWorkspace.shared.open(address) else {
                throw PreviewIssue(text: "无法打开默认浏览器。请检查系统设置中的默认浏览器")
            }
        } catch { issue = PreviewIssue(text: error.localizedDescription) }
    }

    func setEntry(_ editor: DesignEditing) {
        entry = editor.page.id
        publish(editor.project)
    }

    func export(_ editor: DesignEditing, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "设计源码"
        panel.prompt = "导出"
        let design = editor.project.runtime()
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            Task.detached { [weak self] in
                do { try ProjectExport.write(design, to: url) }
                catch { await self?.report(error) }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }

    private func report(_ error: Error) { issue = PreviewIssue(text: error.localizedDescription) }

    private func address(for editor: DesignEditing) async throws -> URL {
        if entry == nil { entry = editor.page.id }
        if let startingServer {
            publish(editor.project)
            return try await startingServer.value
        }
        let server = try PreviewServer()
        self.server = server
        try server.publish(editor.project.runtime(startingAt: entry))
        let start = Task { try await server.open() }
        startingServer = start
        do { return try await start.value }
        catch {
            self.server = nil
            startingServer = nil
            throw error
        }
    }
}
