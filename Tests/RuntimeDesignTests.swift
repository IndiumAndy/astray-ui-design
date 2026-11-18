import Foundation
import Testing
@testable import UIDesign

struct RuntimeDesignTests {
    @Test func stageOneFileMigratesWithStableLayerAndPageIDs() throws {
        var project = DesignProject()
        project.page.layers = [DesignLayer(kind: .input, frame: CGRect(x: 12, y: 100, width: 256, height: 48))]
        let data = try DesignFile.encoded(project)
        for version in [1, 2, 3] {
            let raw = String(decoding: data, as: UTF8.self).replacingOccurrences(
                of: "\"version\" : \(DesignProject.currentVersion)", with: "\"version\" : \(version)"
            )
            #expect(raw.contains("\"version\" : \(version)"))
            #expect(try DesignFile.read(Data(raw.utf8)) == project)
        }
    }

    @MainActor @Test func eachPageEditsAndDeletedLinksUndoTogether() throws {
        let project = DesignProject.contactExample()
        let undo = UndoManager()
        let editor = DesignEditing(file: DesignFile(project: project))
        editor.undoManager = undo
        let detail = try #require(project.pages.last)
        editor.showPage(detail.id)
        let button = try #require(detail.layers.last)
        editor.setFrame(button.frame.offsetBy(dx: 0, dy: 24), of: button.id)
        #expect(editor.project.page == project.page)
        #expect(editor.page.layers.last?.frame.minY == button.frame.minY + 24)
        editor.removePage()
        #expect(editor.project.pages.count == 1)
        #expect(editor.project.page.layers.last?.destination == nil)
        let runtime = editor.project.runtime(startingAt: detail.id)
        #expect(runtime.entry == project.page.id.uuidString)
        undo.undo()
        #expect(editor.project.page.layers.last?.destination == detail.id)
        #expect(editor.project.pages.count == 2)
    }

    @Test func previewServerUsesSameAddressForCommittedChanges() async throws {
        let server = try PreviewServer()
        let url = try await server.open()
        let resource = url.appending(path: "design.json")
        var project = DesignProject.contactExample()
        try server.publish(project.runtime())
        let (before, response) = try await URLSession.shared.data(from: resource)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let decoder = JSONDecoder()
        #expect(try decoder.decode(RuntimeDesign.self, from: before) == project.runtime())
        project.page.layers[0].text = "通讯录"
        try server.publish(project.runtime())
        let (after, _) = try await URLSession.shared.data(from: resource)
        #expect(try decoder.decode(RuntimeDesign.self, from: after) == project.runtime())
        let (_, denied) = try await URLSession.shared.data(from: url.deletingLastPathComponent().appending(path: "design.json"))
        #expect((denied as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func exportShipsSourcesAndDoesNotReplaceExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let design = DesignProject.contactExample().runtime()
        try ProjectExport.write(design, to: directory)
        let swift = try String(contentsOf: directory.appending(path: "iPhone/Sources/GeneratedPages.swift"), encoding: .utf8)
        let react = try String(contentsOf: directory.appending(path: "Web/src/GeneratedPages.jsx"), encoding: .utf8)
        #expect(swift.contains("components.saveContact()"))
        #expect(react.contains("onClick={context.save}"))
        #expect(throws: (any Error).self) { try ProjectExport.write(design, to: directory) }
        let payload = try Data(contentsOf: directory.appending(path: "iPhone/Sources/Design.json"))
        #expect(try JSONDecoder().decode(RuntimeDesign.self, from: payload) == design)
    }
}
