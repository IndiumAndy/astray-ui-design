import AppKit
import Observation

@MainActor @Observable
final class PreviewController {
    let simulator = SimulatorPreview()
    private(set) var webBusy = false
    var issue: PreviewIssue?
    var exportRequest: SourceExportRequest?
    var exportReview: ExportUpdate?
    private(set) var exportBusy = false
    private var server: PreviewServer?
    private var startingServer: Task<URL, Error>?
    private var entry: UUID?
    @ObservationIgnored private var exportPanel: NSSavePanel?

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

    func requestExport(_ editor: DesignEditing, selectedOnly: Bool) {
        let selected = editor.selectedBoards.isEmpty ? [editor.page.id] : editor.selectedBoards
        exportRequest = SourceExportRequest(selectedOnly: selectedOnly, pageIDs: selected)
    }

    func chooseExportDirectory(_ target: SourceExportTarget) {
        guard exportPanel == nil else { return }
        let panel: NSSavePanel
        if target.updating {
            let picker = NSOpenPanel()
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            picker.allowsMultipleSelection = false
            picker.prompt = "查看差异"
            panel = picker
        } else {
            let picker = NSSavePanel()
            picker.nameFieldStringValue = "设计源码"
            picker.prompt = "导出"
            panel = picker
        }
        exportPanel = panel
        panel.begin { [weak self] response in
            guard let self else { return }
            let url = self.exportPanel?.url
            self.exportPanel = nil
            guard response == .OK, let url else { return }
            self.startExport(target, to: url)
        }
    }

    private func startExport(_ target: SourceExportTarget, to url: URL) {
        exportBusy = true
        Task { @MainActor in
            defer { exportBusy = false }
            do {
                let plan = try await Task.detached { () throws -> ExportUpdate? in
                    if target.updating { return try ProjectExport.prepareUpdate(target.export, to: url) }
                    try ProjectExport.write(target.export, to: url)
                    return nil
                }.value
                exportReview = plan
            } catch { report(error) }
        }
    }

    func applyExport(_ update: ExportUpdate, choices: Set<String>) {
        exportBusy = true
        Task { @MainActor in
            defer { exportBusy = false }
            do {
                try await Task.detached { try update.apply(replacingConflicts: choices) }.value
            } catch { report(error) }
        }
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
