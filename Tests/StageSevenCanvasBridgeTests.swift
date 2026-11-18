import Foundation
import Testing
@testable import UIDesign

struct StageSevenCanvasBridgeTests {
    @Test func offlineBatchesConflictAndNeverWritePartialEdits() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "Test.uidesign")
        let source = DesignProject.interactionExample()
        try DesignCodec.encoded(source).write(to: file)
        let bridge = try CanvasBridge(projectURL: file, root: directory)
        let revision = try DesignBatch.revision(source)
        let title = try #require(source.page.layers.first)
        let edit = CanvasOperation(kind: .text, ids: [title.id], text: "离线修改")
        let outcomes = try bridge.withLock {
            try bridge.runOffline(CanvasBridgeRequest(.edit, page: source.page.id, revision: revision, operations: [edit]))
        }
        let saved = try Data(contentsOf: file)
        #expect(outcomes.revision != revision)
        #expect(try DesignCodec.read(saved).page.layers.first?.text == "离线修改")
        #expect(throws: CanvasBatchError.self) {
            try bridge.withLock {
                try bridge.runOffline(CanvasBridgeRequest(.edit, page: source.page.id, revision: revision, operations: [edit]))
            }
        }
        #expect(throws: CanvasBatchError.self) {
            try bridge.withLock {
                try bridge.runOffline(CanvasBridgeRequest(.edit, page: source.page.id, revision: outcomes.revision,
                                                         operations: [edit, CanvasOperation(kind: .gap, ids: [title.id], value: 16)]))
            }
        }
        #expect(try Data(contentsOf: file) == saved)
    }

    @Test @MainActor func liveBatchesUseEditorsSingleUndoAndRequirePermission() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "Test.uidesign")
        let source = DesignProject.interactionExample()
        try DesignCodec.encoded(source).write(to: fileURL)
        let file = DesignFile(project: source)
        let session = ReviewSession(document: file)
        let undo = UndoManager()
        session.design?.undoManager = undo
        let bridge = try CanvasBridge(projectURL: fileURL)
        let task = Task { await session.serveLocalMCP(for: fileURL) }
        defer { task.cancel() }

        for _ in 0..<25 {
            if try bridge.activeLease() != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try bridge.activeLease() != nil)
        func request(_ payload: CanvasBridgeRequest) async throws -> CanvasBridgeResponse {
            try bridge.enqueue(payload)
            for _ in 0..<50 {
                if let response = try bridge.receive(payload) { return response }
                try await Task.sleep(for: .milliseconds(30))
            }
            throw CanvasBridgeError.timeout
        }
        let denied = try await request(CanvasBridgeRequest(.read))
        #expect(denied.error == CanvasBridgeError.accessDisabled.localizedDescription)
        session.allowsLocalMCP = true
        let state = try await request(CanvasBridgeRequest(.read))
        #expect(state.project == source)
        let title = try #require(source.page.layers.first)
        let group = try #require(source.page.layers.last)
        let batch = CanvasBridgeRequest(.edit, page: source.page.id, revision: state.revision, operations: [
            CanvasOperation(kind: .text, ids: [title.id], text: "已由 MCP 修改"),
            CanvasOperation(kind: .gap, ids: [group.id], value: 16)
        ])
        let accepted = try await request(batch)
        #expect(accepted.error == nil)
        #expect(file.project.page.layers.first?.text == "已由 MCP 修改")
        #expect(file.project.page.layers.last?.geometry?.gap == 16)
        let failed = try await request(CanvasBridgeRequest(.edit, page: source.page.id, revision: state.revision,
                                                          operations: [CanvasOperation(kind: .text, ids: [title.id], text: "过期版本")]))
        #expect(failed.revision == accepted.revision)
        #expect(failed.error != nil)
        #expect(file.project.page.layers.first?.text == "已由 MCP 修改")
        undo.undo()
        #expect(file.project == source)
        task.cancel()
        await task.value
    }
}
