import Foundation
import Testing
@testable import UIDesign

struct StageSixExportTests {
    @Test func onlySelectedPagesAndExternalHostEventsAreExported() throws {
        let project = DesignProject.interactionExample()
        let source = try SourceExport(project: project, scope: .pages([project.page.id]))
        #expect(source.runtime.pages.map(\.title) == ["通讯录"])
        #expect(source.runtime.entry == project.page.id.uuidString)
        #expect(source.links.count == 4)
        let row = try #require(source.runtime.pages[0].layers.first { $0.kind == "contactList" })
        let detail = try #require(project.pages.first { $0.title == "联系人详情" })
        #expect(row.behavior?.action == DesignAction(kind: .named, name: "openPage:\(detail.id.uuidString)"))
        #expect(row.behavior?.list?.sample.rows[1].fields["name"] == .text("陈亦舟"))
        #expect(row.behavior?.list?.emptyAction?.kind == .named)
        #expect(source.links.contains { $0.targetTitle == "关于通讯录" && $0.presentation == "sheet" })

        let pair = try SourceExport(project: project, scope: .pages([project.page.id, detail.id]))
        let included = try #require(pair.runtime.pages[0].layers.first { $0.kind == "contactList" })
        #expect(included.behavior?.action == .page(.navigate, detail.id))
        #expect(pair.runtime.pages.map(\.title) == ["通讯录", "联系人详情"])
        #expect(pair.links.count == 3)
        let complete = try SourceExport(project: project, scope: .complete)
        #expect(complete.runtime.pages.count == project.pages.count)
        #expect(complete.links.isEmpty)
        #expect(throws: ExportProblem.self) { try SourceExport(project: project, scope: .pages([])) }
    }

    @Test func legacyRowDestinationBecomesHostCallback() throws {
        let project = DesignProject.contactExample()
        let source = try SourceExport(project: project, scope: .pages([project.page.id]))
        let row = try #require(source.runtime.pages[0].layers.first { $0.kind == "contactList" })
        #expect(row.destination == nil)
        #expect(row.behavior?.action?.kind == .named)
        #expect(source.runtime.contacts == project.contacts ?? [])
        #expect(source.links.first?.trigger == "row")
    }

    @Test func reexportPreservesHostAndManualFilesUntilExplicitReplacement() throws {
        var project = DesignProject.interactionExample()
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let export = try SourceExport(project: project, scope: .complete)
        try ProjectExport.write(export, to: root)
        let host = root.appending(path: "Web/src/contactActions.js")
        let jsx = root.appending(path: "Web/src/GeneratedPages.jsx")
        let data = root.appending(path: "Web/src/Design.json")
        let manual = root.appending(path: "Notes.txt")
        let before = try Data(contentsOf: data)
        try Data("host logic".utf8).write(to: host)
        try Data("manual JSX".utf8).write(to: jsx)
        try Data("host file".utf8).write(to: manual)

        let button = try #require(project.page.allLayers.first { $0.kind == .button })
        project.page.update(button.id) { $0.frame.origin.x += 16 }
        let changed = try SourceExport(project: project, scope: .complete)
        let firstReview = try ProjectExport.prepareUpdate(changed, to: root)
        #expect(firstReview.changes.first { $0.path == "Web/src/GeneratedPages.jsx" }?.state == .conflict)
        #expect(firstReview.changes.first { $0.path == "Web/src/contactActions.js" }?.state == .host)
        #expect(firstReview.changes.first { $0.path == "Web/src/GeneratedPages.jsx" }?.textComparison?.1.contains("关于") == true)
        // Review is read-only; cancelling does not invoke apply.
        #expect(try Data(contentsOf: data) == before)
        #expect(try String(contentsOf: jsx, encoding: .utf8) == "manual JSX")

        try firstReview.apply(replacingConflicts: [])
        #expect(try Data(contentsOf: data) != before)
        #expect(try String(contentsOf: jsx, encoding: .utf8) == "manual JSX")
        #expect(try String(contentsOf: host, encoding: .utf8) == "host logic")
        let secondReview = try ProjectExport.prepareUpdate(changed, to: root)
        try secondReview.apply(replacingConflicts: ["Web/src/GeneratedPages.jsx", "Web/src/contactActions.js"])
        #expect(try String(contentsOf: jsx, encoding: .utf8).contains("function Page1"))
        #expect(try String(contentsOf: host, encoding: .utf8) == "host logic")
        #expect(try String(contentsOf: manual, encoding: .utf8) == "host file")

        let manifest = try JSONDecoder().decode(ExportManifest.self,
                                                from: Data(contentsOf: root.appending(path: ExportManifest.filename)))
        #expect(manifest.pages.count == project.pages.count)
        #expect(manifest.generatedFiles["Web/src/GeneratedPages.jsx"] == ExportManifest.digest(try Data(contentsOf: jsx)))
    }

    @Test func updateRechecksConcurrentWritesAndRejectsSymlinkedFiles() throws {
        var project = DesignProject.interactionExample()
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectExport.write(try SourceExport(project: project, scope: .complete), to: root)
        project.page.title = "另一个标题"
        let changed = try SourceExport(project: project, scope: .complete)
        let plan = try ProjectExport.prepareUpdate(changed, to: root)
        let data = root.appending(path: "Web/src/Design.json")
        let before = Data("written after review".utf8)
        try before.write(to: data)
        #expect(throws: ExportProblem.self) { try plan.apply(replacingConflicts: []) }
        #expect(try Data(contentsOf: data) == before)
        try FileManager.default.removeItem(at: data)
        let untouched = root.appending(path: "Untouched.txt")
        try Data("keep".utf8).write(to: untouched)
        try FileManager.default.createSymbolicLink(at: data, withDestinationURL: untouched)
        #expect(throws: ExportProblem.self) { try ProjectExport.prepareUpdate(changed, to: root) }
        #expect(try String(contentsOf: untouched, encoding: .utf8) == "keep")
    }
}
