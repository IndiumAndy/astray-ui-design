import Foundation

@MainActor extension ReviewSession {
    func serveLocalMCP(for url: URL) async {
        guard let editor = design, let bridge = try? CanvasBridge(projectURL: url) else { return }
        let lease = CanvasBridgeLease(owner: UUID(), processID: ProcessInfo.processInfo.processIdentifier)
        do {
            guard try bridge.acquire(lease) else { return }
            defer { bridge.release(lease) }
            while !Task.isCancelled {
                for command in try bridge.requests() {
                    if Task.isCancelled { return }
                    if command.deadline <= Date() {
                        bridge.abandon(command)
                        continue
                    }
                    var response = CanvasBridgeResponse(editorOpen: true)
                    do {
                        guard allowsLocalMCP else { throw CanvasBridgeError.accessDisabled }
                        switch command.kind {
                        case .read:
                            response.project = editor.project
                            response.revision = try DesignBatch.revision(editor.project)
                        case .edit:
                            guard let page = command.page, let revision = command.revision,
                                  let batch = command.operations else { throw CanvasBridgeError.invalidRequest }
                            response.revision = try editor.applyCanvasBatch(batch, page: page, revision: revision)
                        case .simulator:
                            guard let input = command.input else { throw CanvasBridgeError.invalidRequest }
                            response.screenshot = try await run.simulator.perform(input)
                        }
                    } catch {
                        if let conflict = error as? CanvasBatchError,
                           case .conflict(let revision) = conflict { response.revision = revision }
                        response.error = error.localizedDescription
                    }
                    try bridge.respond(response, to: command)
                }
                try await Task.sleep(for: .milliseconds(170))
            }
        } catch is CancellationError {
            return
        } catch {
            run.issue = PreviewIssue(text: error.localizedDescription)
        }
    }
}
