import AppKit
import SwiftUI

// SwiftUI keeps the row's keyboard and accessibility actions. AppKit supplies
// the same local pasteboard type the canvas reads synchronously during hover.
struct ComponentDragSource: NSViewRepresentable {
    let payload: CanvasDragPayload
    let symbol: String
    let title: String
    let activate: () -> Void

    init(kind: LayerKind, activate: @escaping () -> Void) {
        self.init(payload: .component(kind), symbol: kind.symbol, title: kind.name, activate: activate)
    }

    init(payload: CanvasDragPayload, symbol: String, title: String, activate: @escaping () -> Void) {
        self.payload = payload
        self.symbol = symbol
        self.title = title
        self.activate = activate
    }

    func makeNSView(context: Context) -> Surface { Surface(payload: payload, symbol: symbol, title: title, activate: activate) }

    func updateNSView(_ view: Surface, context: Context) {
        view.payload = payload
        view.symbol = symbol
        view.title = title
        view.activate = activate
    }

    final class Surface: NSView, NSDraggingSource {
        var payload: CanvasDragPayload
        var symbol: String
        var title: String
        var activate: () -> Void
        private var down: CGPoint?

        init(payload: CanvasDragPayload, symbol: String, title: String, activate: @escaping () -> Void) {
            self.payload = payload
            self.symbol = symbol
            self.title = title
            self.activate = activate
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { nil }

        override func mouseDown(with event: NSEvent) { down = event.locationInWindow }

        override func mouseUp(with event: NSEvent) {
            guard down != nil else { return }
            down = nil
            if bounds.contains(convert(event.locationInWindow, from: nil)) { activate() }
        }

        override func mouseDragged(with event: NSEvent) {
            let point = event.locationInWindow
            guard let down, hypot(point.x - down.x, point.y - down.y) >= 3 else { return }
            self.down = nil

            let pasteboard = NSPasteboardItem()
            pasteboard.setData(payload.data, forType: CanvasPointer.Surface.componentType)
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let local = convert(point, from: nil)
            let symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.setDraggingFrame(CGRect(x: local.x - 9, y: local.y - 9, width: 18, height: 18), contents: symbol)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .copy : []
        }
    }
}
