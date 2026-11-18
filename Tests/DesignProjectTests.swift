import Foundation
import SwiftUI
import Testing
@testable import UIDesign

struct DesignProjectTests {
    @Test func documentRetainsFramesTextAndGroupIdentities() throws {
        var project = DesignProject()
        var title = layer(.title, x: 22.5, y: 80)
        title.text = "设置账户 • 空 格"
        var setting = layer(.setting, x: 32, y: 164)
        setting.spacing = 28
        setting.children[0].text = "邮件摘要"
        setting.children[1].isOn = false
        project.page.layers = [title, setting]
        project.page.device = .largePhone

        let reopened = try DesignFile.read(DesignFile.encoded(project))
        #expect(reopened == project)
        #expect(reopened.page.selection(setting.children[1].id)?.parent?.id == setting.id)
    }

    @Test func versionAndDamagedFilesAreRejected() throws {
        #expect(throws: DesignFileError.unsupportedVersion(19)) {
            try DesignFile.read(Data("{\"version\":19}".utf8))
        }
        #expect(throws: DesignFileError.unreadable) {
            try DesignFile.read(Data("not json".utf8))
        }
        var project = DesignProject()
        let duplicate = layer(.button, x: 12, y: 80)
        project.page.layers = [duplicate, duplicate]
        #expect(throws: DesignFileError.invalidLayers) { try DesignFile.encoded(project) }
    }

    @Test func edgesCenterAndEqualSpacingMatchTheCommittedCoordinates() {
        var page = DesignPage()
        let first = layer(.button, x: 20, y: 100)
        let second = layer(.button, x: 20, y: 172)
        page.layers = [first, second]
        let frame = CGRect(x: 23, y: 248, width: 144, height: 48)
        let snapped = CanvasSnapping.place(frame, kind: .button, on: page, excluding: nil, scale: 1, enabled: true)
        #expect(snapped.frame.origin == CGPoint(x: 20, y: 244))
        #expect(snapped.guides.compactMap(\.distance) == [24, 24])
        #expect(snapped.guides.contains { $0.start.x == 92 && $0.end.x == 92 })

        let wider = CGRect(x: 18, y: 104, width: 150, height: 48)
        let centered = CanvasSnapping.place(wider, kind: .button, on: page, excluding: nil, scale: 1, enabled: true)
        #expect(centered.frame.minX == 17)

        let unsnapped = CanvasSnapping.place(frame, kind: .button, on: page, excluding: nil, scale: 1, enabled: false)
        #expect(unsnapped.frame == frame)
        #expect(unsnapped.guides.isEmpty)
        let zoomedIn = CanvasSnapping.place(frame, kind: .button, on: page, excluding: nil, scale: 4, enabled: true)
        #expect(zoomedIn.frame == frame)
    }

    @Test func snappingBalancesTheMiddleAndExcludesTheMovingLayer() {
        var page = DesignPage()
        let middle = layer(.button, x: 30, y: 191)
        page.layers = [layer(.button, x: 30, y: 104), middle, layer(.button, x: 30, y: 274)]
        let frame = middle.frame.offsetBy(dx: 2, dy: -1)
        let snapped = CanvasSnapping.place(frame, kind: .button, on: page, excluding: middle.id, scale: 1, enabled: true)
        #expect(snapped.frame.minY == 189)
        #expect(snapped.guides.compactMap(\.distance) == [37, 37])
    }

    @Test func inspectorRejectsPartiallyParsedNumbers() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        #expect(InspectorNumber.parse(" 24.5 ", locale: english) == 24.5)
        #expect(InspectorNumber.parse("24,5", locale: german) == 24.5)
        #expect(InspectorNumber.parse("24pt", locale: english) == nil)
        #expect(InspectorNumber.parse("24 5", locale: english) == nil)
        #expect(InspectorNumber.parse("24,5", locale: english) == nil)
    }

    @Test func inspectorOpeningKeepsTheArtboardUnderThePointer() {
        let device = ReviewDevice.phone.size
        let noInspector = CanvasLayout(window: CGSize(width: 1091, height: 759), device: device, zoom: .fit, flow: false)
        let inspector = CanvasLayout(window: CGSize(width: 818, height: 759), device: device, zoom: .fit, flow: false, inspectorInset: 273)
        let point = CGPoint(x: 123, y: 456)
        #expect(inspector.canvasPoint(point) == noInspector.canvasPoint(point))
        let roundTrip = inspector.documentPoint(inspector.canvasPoint(point))
        #expect(abs(roundTrip.x - point.x) < 0.0001)
        #expect(abs(roundTrip.y - point.y) < 0.0001)
    }

    @MainActor @Test func editsUndoIndividuallyAndInspectorRemembersManualChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let file = DesignFile()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = ReviewSession(document: file, defaults: defaults)
        let editor = try #require(session.editor)
        editor.undoManager = undo
        #expect(!session.trailingPaneVisible)
        editor.insert(.setting)
        #expect(session.trailingPaneVisible)
        session.toggleInspector()

        let setting = try #require(editor.selection?.layer)
        let moved = setting.frame.offsetBy(dx: 13, dy: 6)
        editor.setFrame(moved, of: setting.id)
        editor.select(setting.children[1].id)
        #expect(!session.trailingPaneVisible)
        editor.update(setting.children[1].id, action: "切换开关") { $0.isOn = true }
        #expect(undo.undoActionName == "移动图层")
        editor.update(setting.children[1].id, action: "切换开关") { $0.isOn = false }
        #expect(editor.selection?.layer.isOn == false)
        undo.undo()
        #expect(editor.selection?.layer.isOn == true)
        #expect(editor.page.selection(setting.id)?.layer.frame == moved)
        undo.undo()
        #expect(editor.page.selection(setting.id)?.layer.frame == setting.frame)
        undo.redo()
        #expect(editor.page.selection(setting.id)?.layer.frame == moved)
        session.snapEnabled = false
        #expect(!ReviewSession(defaults: defaults).snapEnabled)
    }

    private func layer(_ kind: LayerKind, x: CGFloat, y: CGFloat) -> DesignLayer {
        DesignLayer(kind: kind, frame: CGRect(origin: CGPoint(x: x, y: y), size: kind.defaultSize))
    }
}
