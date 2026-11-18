import Foundation
import Testing
@testable import UIDesign

struct StageFiveTemplateTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB4QAAAAASUVORK5CYII=")!

    @Test func movingTheDocumentRetainsImagesStylesOverridesAndLinks() throws {
        var project = DesignProject.interactionExample()
        let style = ButtonDesignStyle(id: UUID(), name: "样式", height: 56, radius: 10)
        project.buttonStyles = [style]
        let button = try #require(project.page.allLayers.first { $0.kind == .button })
        project.page.update(button.id) {
            $0.styleID = style.id
            $0.deviceLayouts = ["phone": LayerGeometry(width: .fill)]
        }
        var image = DesignLayer(kind: .image, frame: CGRect(x: 24, y: 500, width: 144, height: 112))
        image.image = png
        project.page.layers.append(image)
        project.page.referenceImage = ReferenceImage(data: png, name: "本地参考.png")

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appending(path: "项目A")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let filename = "可移动设计.uidesign"
        try DesignFile.encoded(project).write(to: original.appending(path: filename), options: .atomic)
        let destination = root.appending(path: "移动后")
        try FileManager.default.moveItem(at: original, to: destination)
        let reopened = try DesignFile.read(Data(contentsOf: destination.appending(path: filename)))
        #expect(reopened == project)
        #expect(reopened.page.referenceImage?.data == png)
        #expect(reopened.page.layers.last?.image == png)
    }

    @Test func flowCopiesKeepRowBindingsAndOnlyTheChosenLinks() throws {
        let source = DesignProject.interactionExample()
        let detail = try #require(source.pages.first { $0.title == "联系人详情" })
        let selection = TemplateSelection.pages([source.page.id, detail.id])
        #expect(PersonalTemplate.linkedPages(in: source, selection: selection).count == 3)
        let item = try PersonalTemplate.capture(name: "通讯录流程", from: source, selection: selection, includeLinkedPages: false)
        #expect(item.kind == .flow)
        let host = DesignProject()
        let first = try item.instantiate(into: host)
        let second = try item.instantiate(into: first.project)
        #expect(second.project.pages.count == 5)
        #expect(first.page != second.page)
        for result in [first, second] {
            let page = result.project.page(withID: result.page)
            let row = try #require(page.allLayers.first { $0.kind == .contactList })
            let target = try #require(row.behavior?.action?.target.flatMap(UUID.init(uuidString:)))
            #expect(target != detail.id)
            #expect(result.project.page(withID: target).title == "联系人详情")
            #expect(row.behavior?.list?.emptyAction == nil)
            #expect(page.allLayers.first { $0.kind == .listRow }?.behavior?.action == nil)
            let record = try #require(row.behavior?.list?.sample.rows.dropFirst().first)
            let renderer = try #require(result.project.page(withID: target).runtime(styles: [])
                .layers.first { $0.behavior?.binding?.key == "phone" })
            #expect(renderer.originalValue(data: RuntimeData(), record: record) == .text("202-555-0162"))
        }
        let full = try PersonalTemplate.capture(name: "通讯录含外链", from: source, selection: selection, includeLinkedPages: true)
        let fullCopy = try full.instantiate()
        #expect(fullCopy.project.pages.count == source.pages.count)
        let row = try #require(fullCopy.project.page.allLayers.first { $0.kind == .contactList })
        let emptyTarget = try #require(row.behavior?.list?.emptyAction?.target.flatMap(UUID.init(uuidString:)))
        #expect(fullCopy.project.page(withID: emptyTarget).title == "新建联系人")
    }

    @Test func duplicateFormCopiesHaveIndependentGroupsAndKeepBusinessKeys() throws {
        let source = DesignProject.interactionExample()
        let settings = try #require(source.pages.first { $0.title == "设置" })
        let group = try #require(settings.layers.first { $0.kind == .layout })
        let item = try PersonalTemplate.capture(name: "设置表单", from: source,
                                                selection: .layers(page: settings.id, layers: [group]), includeLinkedPages: false)
        #expect(item.kind == .group)
        let first = try item.instantiate(into: DesignProject())
        let second = try item.instantiate(into: first.project)
        let page = second.project.page(withID: second.page).runtime(styles: [])
        let actions = page.layers.compactMap(\.behavior?.action).filter { $0.name == "saveProfile" }
        #expect(actions.compactMap(\.form) == ["profile", "profile-2"])
        let forms = actions.compactMap(\.form).map { name in
            FormSubmission(form: name, layers: page.layers, value: { _ in .text(name) }, state: { _ in .normal })
        }
        #expect(forms.map { $0.values.keys.sorted() } == Array(repeating: ["email", "name", "nickname", "password"], count: 2))
        #expect(Set(forms[0].fields.map(\.id)).isDisjoint(with: forms[1].fields.map(\.id)))
    }

    @MainActor @Test func savingAnUpdatedTemplateDoesNotChangeExistingProjectsAndUndoRemovesWholeInsertion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = PersonalLibrary(directory: directory)
        var source = DesignProject()
        var field = DesignLayer(kind: .button, frame: CGRect(x: 24, y: 76, width: 144, height: 48))
        field.text = "第一版"
        let style = ButtonDesignStyle(id: UUID(), name: "主操作", height: 56, radius: 12)
        field.styleID = style.id
        source.buttonStyles = [style]
        source.page.layers = [field]
        let item = try PersonalTemplate.capture(name: "主操作", from: source,
                                                selection: .layers(page: source.page.id, layers: [field]), includeLinkedPages: false)
        try library.save(item)
        #expect(PersonalLibrary(directory: directory).templates == [item])
        let old = try item.instantiate().project
        let oldStyle = try #require(old.buttonStyles?.first)
        #expect(oldStyle.id != style.id)

        field.text = "第二版"
        source.page.layers = [field]
        source.buttonStyles?[0].radius = 18
        let update = try PersonalTemplate.capture(name: "主操作", replacing: item.id, from: source,
                                                  selection: .layers(page: source.page.id, layers: [field]), includeLinkedPages: false)
        try library.save(update)
        #expect(PersonalLibrary(directory: directory).templates == [update])
        #expect(old.page.layers.first?.text == "第一版")
        #expect(old.buttonStyles?.first?.radius == 12)
        let newer = try update.instantiate().project
        #expect(newer.page.layers.first?.text == "第二版")
        #expect(newer.buttonStyles?.first?.radius == 18)

        let file = DesignFile(project: old)
        let editor = DesignEditing(file: file)
        let undo = UndoManager()
        editor.undoManager = undo
        editor.insertTemplate(update, at: CGPoint(x: 32, y: 148))
        #expect(editor.page.layers.map(\.text) == ["第一版", "第二版"])
        #expect(editor.page.layers.last?.frame.origin == CGPoint(x: 32, y: 148))
        undo.undo()
        #expect(file.project == old)
    }
}
