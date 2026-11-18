import Foundation
import Testing
@testable import UIDesign

struct StageThreeLayoutTests {
    @MainActor @Test func arrangementReflowsAndResizingOnlyFixesTheChangedAxis() throws {
        let editor = DesignEditing(file: DesignFile())
        let first = CGRect(x: 24, y: 100, width: 260, height: 44)
        editor.insert(.input, frame: first)
        let firstField = try #require(editor.selectedID)
        editor.insert(.input, frame: first.offsetBy(dx: 0, dy: 90))
        let field = try #require(editor.selectedID)
        editor.insert(.input, frame: first.offsetBy(dx: 0, dy: 180))
        let other = try #require(editor.selectedID)
        editor.toggleSelection(firstField)
        editor.toggleSelection(field)
        editor.arrangeSelection(.vertical)
        let group = try #require(editor.selection?.layer)
        #expect(group.children.map(\.id) == [firstField, field, other])
        editor.setPlacement(field) { $0.width = .fill; $0.height = .content }
        let before = try #require(editor.layout.items[field.uuidString]?.frame)
        #expect(before.width == 342)

        editor.update(firstField, action: "编辑提示文字") { $0.fieldHint = "请填写证件姓名" }
        let after = try #require(editor.layout.items[field.uuidString]?.frame)
        #expect(after.minY > before.minY)
        let next = try #require(editor.layout.items[other.uuidString]?.frame)
        #expect(next.minY - after.maxY == 12)

        let selected = try #require(editor.page.selection(field)?.layer)
        let displayed = editor.frame(of: selected)
        editor.setFrame(CGRect(origin: displayed.origin, size: CGSize(width: 240, height: displayed.height)), of: field)
        let resized = try #require(editor.page.selection(field)?.layer)
        #expect(editor.frame(of: resized).width == 240)
        #expect(resized.geometry?.width == .fixed)
        #expect(resized.geometry?.height == .content)

        editor.setPlacement(field) { $0.width = .fill }
        editor.setDevice(.tablet)
        let expanded = try #require(editor.layout.items[field.uuidString]?.frame)
        #expect(expanded.width == 772)
        #expect(try DesignFile.read(DesignFile.encoded(editor.project)) == editor.project)
    }

    @MainActor @Test func deviceOrderIsIndependentAndTextIsShared() throws {
        let editor = DesignEditing(file: DesignFile())
        editor.setDevice(.desktop)
        editor.insert(.actionBar)
        let group = try #require(editor.selection?.layer)
        editor.setPlacement(group.id) { $0.width = .fill; $0.stackAtNarrowWidth = true }
        let ids = group.children.map(\.id)
        let desktop = editor.layout
        #expect(desktop.items[ids[0].uuidString]?.frame.minY == desktop.items[ids[1].uuidString]?.frame.minY)

        editor.setDevice(.phone)
        editor.usesDeviceLayout = true
        editor.reorder(ids[1], to: 0)
        editor.update(ids[1], action: "编辑文字") { $0.text = "提交" }
        let phone = editor.layout
        #expect((phone.items[ids[1].uuidString]?.frame.minY ?? 0) < (phone.items[ids[0].uuidString]?.frame.minY ?? 0))
        #expect(editor.page.selection(ids[1])?.layer.text == "提交")

        editor.setDevice(.tablet)
        let tablet = editor.layout
        #expect((tablet.items[ids[0].uuidString]?.frame.minX ?? 0) < (tablet.items[ids[1].uuidString]?.frame.minX ?? 0))
        editor.setDevice(.phone)
        editor.restoreSharedLayout()
        let restored = editor.layout
        #expect((restored.items[ids[0].uuidString]?.frame.minY ?? 0) < (restored.items[ids[1].uuidString]?.frame.minY ?? 0))
        #expect(editor.page.selection(ids[1])?.layer.text == "提交")
    }

    @MainActor @Test func longPageKeepsBarsOutsideScrollingAndReorderIsUndoable() throws {
        let editor = DesignEditing(file: DesignFile())
        let undo = UndoManager()
        editor.undoManager = undo
        editor.insert(.title)
        let header = try #require(editor.selectedID)
        editor.setPlacement(header) { $0.region = .header }
        editor.select(nil)
        editor.insert(.layout)
        let group = try #require(editor.selectedID)
        for _ in 0..<20 { editor.insert(.setting, into: group) }
        editor.select(nil)
        editor.insert(.actionBar, frame: CGRect(x: 24, y: 70, width: 342, height: 48))
        let footer = try #require(editor.selectedID)
        editor.setPlacement(footer) { $0.region = .footer }
        let parent = try #require(editor.page.selection(group)?.layer)
        let row = parent.children[17]
        let before = editor.frame(of: row)
        let viewport = editor.boardSize(using: editor.layout)
        #expect(viewport.height == 844)
        #expect(before.minY > viewport.height)
        #expect(editor.layout.items[header.uuidString]?.region == .header)
        #expect(editor.layout.items[footer.uuidString]?.region == .footer)
        #expect(editor.layout.footerHeight == 48)
        editor.showsFullPage = true
        #expect(editor.boardSize(using: editor.layout).height > before.maxY)
        editor.reorder(row.id, to: 2)
        #expect(editor.frame(of: row).minY < viewport.height)
        undo.undo()
        #expect(editor.frame(of: row) == before)
        #expect(try DesignFile.read(DesignFile.encoded(editor.project)) == editor.project)
    }

    @MainActor @Test func sharedStyleUpdatesAllReferencesAndKeepsContentAndActions() throws {
        let editor = DesignEditing(file: DesignFile())
        for index in 0..<5 {
            editor.insert(.button)
            let layer = try #require(editor.selection?.layer)
            editor.update(layer.id, action: "编辑按钮") {
                $0.text = "按钮 \(index + 1)"
                $0.savesContact = index == 3
            }
        }
        let buttons = editor.page.layers
        editor.newButtonStyle(from: buttons[0], name: "主按钮")
        let style = try #require(editor.project.buttonStyles?.first)
        for button in buttons.dropFirst() { editor.useButtonStyle(style.id, for: button) }
        let original = editor.frame(of: buttons[0])
        editor.setFrame(CGRect(origin: original.origin, size: CGSize(width: original.width, height: 64)), of: buttons[0].id)
        #expect(editor.page.layers.map { editor.frame(of: $0).height } == [64, 48, 48, 48, 48])
        let changed = try #require(editor.page.selection(buttons[0].id)?.layer)
        editor.updateButtonStyle(from: changed)
        #expect(editor.page.layers.map { editor.frame(of: $0).height } == [64, 64, 64, 64, 64])
        #expect(editor.page.layers.map(\.text) == buttons.map(\.text))
        #expect(editor.page.layers.map(\.savesContact) == buttons.map(\.savesContact))
        let runtime = editor.project.runtime().pages[0]
        #expect(runtime.layers.allSatisfy { $0.styleHeight == 64 })
    }

    @MainActor @Test func guidesAndBottomImageStayInTheDocument() throws {
        let editor = DesignEditing(file: DesignFile())
        editor.setReference(.login)
        editor.change("导入底图") { $0.referenceImage = ReferenceImage(data: Data([1, 2, 3]), name: "仅供对照.png") }
        let page = editor.page
        let snap = CanvasSnapping.place(CGRect(x: 27, y: 90, width: 342, height: 44),
                                        kind: .title, on: page, excluding: nil, scale: 1, enabled: true)
        #expect(snap.frame.origin == CGPoint(x: 24, y: 88))
        let decoded = try DesignFile.read(DesignFile.encoded(editor.project))
        #expect(decoded.page.referenceImage?.isLocked == true)
        #expect(decoded.page.layers.isEmpty)
        let preview = try RuntimeAssets.encode(decoded.runtime())
        #expect(!String(decoding: preview, as: UTF8.self).contains("reference"))
        #expect(decoded.runtime().pages[0].layers.isEmpty)
    }

    @MainActor @Test func aspectPresetsPreserveContentAndRemoveNestedOrderReferences() throws {
        let editor = DesignEditing(file: DesignFile(project: .contactExample()))
        let layers = editor.page.layers
        for (w, h) in [(1.0, 1.0), (4, 3), (3, 2), (16, 10), (16, 9), (21, 9)] {
            editor.setAspect(width: w, height: h)
            let size = editor.page.size
            #expect(abs(max(size.width, size.height) / min(size.width, size.height) - w / h) < 0.01)
            #expect(editor.page.layers == layers)
        }
        let size = editor.page.size
        editor.setCustomSize(CGSize(width: size.height, height: size.width))
        #expect(editor.page.size.width == size.height)
        editor.insert(.actionBar)
        let group = try #require(editor.selection?.layer)
        editor.reorder(group.children[1].id, to: 0)
        editor.select(group.children[1].id)
        editor.removeSelection()
        #expect(try DesignFile.read(DesignFile.encoded(editor.project)) == editor.project)
    }
}
