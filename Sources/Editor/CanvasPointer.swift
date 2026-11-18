import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CanvasDragPayload {
    case component(LayerKind)
    case template(UUID)

    var data: Data {
        switch self {
        case .component(let kind): Data(kind.rawValue.utf8)
        case .template(let id): Data(id.uuidString.utf8)
        }
    }

    init?(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        if let kind = LayerKind(rawValue: raw) { self = .component(kind) }
        else if let id = UUID(uuidString: raw) { self = .template(id) }
        else { return nil }
    }
}

struct CanvasPointer: NSViewRepresentable {
    let focusRequest: Int
    let down: (CGPoint, NSEvent, Bool) -> Void
    let drag: (CGPoint) -> Void
    let up: (CGPoint) -> Void
    let pan: (CGPoint) -> Void
    let zoom: (CGFloat, CGPoint) -> Void
    let key: (NSEvent) -> Bool
    let focus: (Bool) -> Void
    let drop: (CanvasDragPayload?, CGPoint, Bool) -> Bool

    func makeNSView(context: Context) -> Surface { Surface(input: self) }

    func updateNSView(_ view: Surface, context: Context) {
        let requestedFocus = view.input.focusRequest != focusRequest
        view.input = self
        if requestedFocus {
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }

    final class Surface: NSView {
        static let componentType = NSPasteboard.PasteboardType(UTType.uiDesignComponent.identifier)
        var input: CanvasPointer
        private var spaceHeld = false
        private var originalDragKind: CanvasDragPayload?

        init(input: CanvasPointer) {
            self.input = input
            super.init(frame: .zero)
            registerForDraggedTypes([Self.componentType])
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("画布操作")
            setAccessibilityIdentifier("canvas-pointer")
            setAccessibilityHelp("方向键移动选中图层，回车编辑文字，空格拖动平移")
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: spaceHeld ? .openHand : .arrow)
        }

        override func becomeFirstResponder() -> Bool {
            input.focus(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
            input.focus(false)
            return true
        }

        override func mouseDown(with event: NSEvent) { start(event, panning: spaceHeld) }
        override func mouseDragged(with event: NSEvent) { input.drag(location(event)) }
        override func mouseUp(with event: NSEvent) { input.up(location(event)) }
        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 { start(event, panning: true) }
        }
        override func otherMouseDragged(with event: NSEvent) {
            if event.buttonNumber == 2 { input.drag(location(event)) }
        }
        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { input.up(location(event)) }
        }

        private func start(_ event: NSEvent, panning: Bool) {
            window?.makeFirstResponder(self)
            input.down(location(event), event, panning)
        }

        override func scrollWheel(with event: NSEvent) {
            if event.modifierFlags.contains(.command) {
                input.zoom(exp(event.scrollingDeltaY * 0.018), location(event))
            } else {
                input.pan(CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
            }
        }

        override func magnify(with event: NSEvent) {
            input.zoom(1 + event.magnification, location(event))
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                spaceHeld = true
                window?.invalidateCursorRects(for: self)
            } else if event.keyCode == 48 {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
            } else if !input.key(event) {
                super.keyDown(with: event)
            }
        }

        override func keyUp(with event: NSEvent) {
            guard event.keyCode == 49 else { return super.keyUp(with: event) }
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let data = sender.draggingPasteboard.data(forType: Self.componentType)
            originalDragKind = data.flatMap(CanvasDragPayload.init(data:))
            return draggingUpdated(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            input.drop(originalDragKind, convert(sender.draggingLocation, from: nil), false) ? .copy : []
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            originalDragKind = nil
            _ = input.drop(nil, .zero, false)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            defer { originalDragKind = nil }
            return input.drop(originalDragKind, convert(sender.draggingLocation, from: nil), true)
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            originalDragKind = nil
            _ = input.drop(nil, .zero, false)
        }

        private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    }
}
