import Foundation
import Testing
@testable import UIDesign

struct StageFourBehaviorTests {
    @Test func formsValidateInReadingOrderAndIsolateTheirValues() throws {
        let project = DesignProject.interactionExample()
        let settings = try #require(project.pages.first { $0.title == "设置" })
        let layers = settings.runtime(styles: []).layers
        let values = ["name": "", "password": "short", "email": "bad@", "signature": "旅行与摄影"]
        let submission = FormSubmission(form: "profile", layers: layers,
                                        value: { .text(values[$0.eventKey] ?? "小林") }, state: { _ in .normal })
        #expect(submission.fields.filter { submission.errors[$0.id] != nil }.map(\.eventKey) == ["name", "password", "email"])
        #expect(submission.values.keys.sorted() == ["email", "name", "nickname", "password"])
        #expect(submission.errorsByLayer(DesignActionResult(fieldErrors: ["email": "邮箱已被使用", "signature": "忽略"]))
            == [try #require(layers.first { $0.eventKey == "email" }?.id): "邮箱已被使用"])
        let second = FormSubmission(form: "signature", layers: layers, value: { .text(values[$0.eventKey] ?? "") },
                                    state: { _ in .normal })
        #expect(second.values == ["signature": .text("旅行与摄影")])
        #expect(second.errors.isEmpty)
        #expect(FieldRules(required: true, maximum: 1).error(for: "👩‍👩‍👧‍👦") == nil)
        #expect(FieldRules(required: true, maximum: 1).error(for: "  ") != nil)
    }

    @Test func hostValuesAndRowsTakePrecedenceOverSamples() throws {
        let project = DesignProject.interactionExample()
        let runtime = project.runtime()
        let fields = runtime.pages.flatMap(\.layers)
        let nickname = try #require(fields.first { $0.behavior?.binding?.key == "nickname" })
        #expect(nickname.originalValue(data: RuntimeData(), record: nil) == .text("小林"))
        #expect(nickname.originalValue(data: RuntimeData(values: ["nickname": .text("林乔")]), record: nil) == .text("林乔"))
        #expect(nickname.originalValue(data: RuntimeData(values: ["nickname": .text("")]), record: nil) == .text(""))
        let phone = try #require(fields.first { $0.behavior?.binding?.key == "phone" })
        let sample = try #require(fields.first { $0.kind == "contactList" }?.behavior?.list?.sample)
        #expect(sample.rows.count == 3)
        #expect(phone.originalValue(data: RuntimeData(), record: sample.rows[1]) == .text("202-555-0162"))
        #expect(ListContent(state: .loading, rows: sample.rows).resolvedState == .loading)
        #expect(ListContent(state: .failed, rows: sample.rows).resolvedState == .failed)
        #expect(ListContent().resolvedState == .empty)
    }

    @MainActor @Test func boardMovementAndLinkDeletionPreserveDocumentSemantics() throws {
        let project = DesignProject.interactionExample()
        let undo = UndoManager()
        let editor = DesignEditing(file: DesignFile(project: project))
        editor.undoManager = undo
        let settings = try #require(project.pages.first { $0.title == "设置" })
        editor.moveBoard(settings.id, to: CGPoint(x: -160, y: 420))
        #expect(editor.boardOrigins()[settings.id] == CGPoint(x: -160, y: 420))
        #expect(editor.project.runtime() == project.runtime())
        let encoded = try DesignFile.encoded(editor.project)
        #expect(try DesignFile.read(encoded) == editor.project)
        undo.undo()
        #expect(editor.project == project)
        editor.showPage(settings.id)
        editor.removePage()
        #expect(editor.project.page.allLayers.first { $0.kind == .listRow }?.behavior?.action == nil)
        undo.undo()
        #expect(editor.project == project)
    }

    @Test func expandedListReservesPageHeight() throws {
        let project = DesignProject.interactionExample()
        var page = project.runtime().pages[0]
        let list = try #require(page.layers.firstIndex { $0.kind == "contactList" })
        let help = try #require(page.layers.first { $0.text == "关于" })
        page.layers[list].contentMinimum = 56 * 20
        let layout = ScreenLayout(page: page, width: 390, height: 844, top: 56, device: .phone)
        let listFrame = try #require(layout.items[page.layers[list].id]?.frame)
        let helpFrame = try #require(layout.items[help.id]?.frame)
        #expect(listFrame.height == 1120)
        #expect(helpFrame.minY >= listFrame.maxY)
        #expect(layout.bodyHeight >= helpFrame.maxY)
    }
}
