import AppKit
import SwiftUI

// SwiftUI keeps the row's keyboard and accessibility actions. AppKit supplies
// the same local pasteboard type the canvas reads synchronously during hover.
struct ComponentDragSource: NSViewRepresentable {
    let kind: LayerKind
    let activate: () -> Void

    func makeNSView(context: Context) -> Surface { Surface(kind: kind, activate: activate) }

    func updateNSView(_ view: Surface, context: Context) {
        view.kind = kind
        view.activate = activate
    }

    final class Surface: NSView, NSDraggingSource {
        var kind: LayerKind
        var activate: () -> Void
        private var down: CGPoint?

        init(kind: LayerKind, activate: @escaping () -> Void) {
            self.kind = kind
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

            let payload = NSPasteboardItem()
            payload.setData(Data(kind.rawValue.utf8), forType: CanvasPointer.Surface.componentType)
            let item = NSDraggingItem(pasteboardWriter: payload)
            let local = convert(point, from: nil)
            let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.name)
            item.setDraggingFrame(CGRect(x: local.x - 9, y: local.y - 9, width: 18, height: 18), contents: symbol)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .copy : []
        }
    }
}
