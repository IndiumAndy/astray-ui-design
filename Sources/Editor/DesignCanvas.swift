import AppKit
import SwiftUI

struct DesignCanvas: View {
    @Environment(\.colorScheme) private var scheme
    let editor: DesignEditing
    let zoom: CanvasZoom
    let snapEnabled: Bool
    let preview: PreviewPlacement
    let palette: WorkbenchPalette
    let inspectorInset: CGFloat
    let dismissPreview: () -> Void

    @State private var tracking: Tracking?
    @State private var live: LiveChange?
    @State private var canvasFocused = false

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let layout = makeLayout(viewport, scale: editor.magnification, pan: editor.pan)
            ZStack(alignment: .topLeading) {
                CanvasRulers(layout: layout, palette: palette)
                    .accessibilityHidden(true)
                ZStack(alignment: .topLeading) {
                    board(layout)
                    guides(layout)
                    outline(layout)
                }
                .frame(width: viewport.width, height: viewport.height)
                .mask(alignment: .bottomTrailing) {
                    Rectangle().frame(width: max(0, viewport.width - CanvasLayout.ruler),
                                      height: max(0, viewport.height - CanvasLayout.ruler))
                }
                if canvasFocused && editor.selection == nil {
                    Rectangle().strokeBorder(palette.accent, lineWidth: 2)
                        .padding([.top, .leading], CanvasLayout.ruler)
                        .accessibilityHidden(true)
                }
                CanvasPointer(
                    focusRequest: editor.focusRequest,
                    down: { down($0, event: $1, forcePan: $2, layout: layout) },
                    drag: { drag($0, layout: layout) },
                    up: { finish($0, layout: layout) },
                    pan: panBy,
                    zoom: { magnify($0, at: $1, layout: layout, viewport: viewport) },
                    key: key,
                    focus: { focused in Task { @MainActor in canvasFocused = focused } },
                    drop: { receive($0, at: $1, commit: $2, layout: layout) }
                )
                .accessibilitySortPriority(1)
                if let id = editor.textEditor, let selected = editor.page.selection(id) {
                    let frame = layout.canvasRect(selectionFrame(selected))
                    CanvasTextEditor(
                        initial: selected.layer.text, label: selected.layer.kind.name,
                        palette: palette, finish: { text in
                            editor.endTextEditing(text)
                        }, returnFocus: editor.focusCanvas
                    )
                    .id(id)
                    .frame(width: min(max(112, frame.width), viewport.width - 36))
                    .padding(.leading, min(max(CanvasLayout.ruler + 4, frame.minX),
                                           viewport.width - min(max(112, frame.width), viewport.width - 36) - 4))
                    .padding(.top, min(max(CanvasLayout.ruler + 4, frame.midY - 14), viewport.height - 32))
                }
                if let width = preview.width {
                    PhonePreview(
                        state: .blank, device: editor.page.device, arrangement: ReviewArrangement(),
                        width: width, availableHeight: viewport.height - 64, palette: palette,
                        page: editor.page, close: dismissPreview
                    )
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: preview.isCentered ? .center : .topTrailing)
                }
            }
            .background(palette.canvas)
            .clipped()
        }
        .onChange(of: snapEnabled) { _, _ in
            if case let .move(id, frame, _)? = live {
                live = .move(id, frame, [])
            } else if case .drop = live {
                live = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画布")
    }

    private func makeLayout(_ viewport: CGSize, scale: CGFloat?, pan: CGPoint) -> CanvasLayout {
        CanvasLayout(window: viewport, device: editor.page.device.size, zoom: zoom, flow: false,
                     trailingClearance: preview.canvasClearance, magnification: scale, pan: pan, inspectorInset: inspectorInset)
    }

    private func board(_ layout: CanvasLayout) -> some View {
        let page = editor.page
        let phonePalette = IOSSamplePalette(scheme: scheme)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(page.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if layout.board.width >= 120 {
                    Text(page.device.dimensions).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(palette.measure)
                }
            }
            .frame(width: layout.board.width, height: 32)
            .accessibilityAddTraits(.isHeader)

            DevicePage(size: page.bounds.size, scale: layout.scale) {
                ZStack(alignment: .topLeading) {
                    IOSArtboard { _ in Color.clear }
                    ForEach(page.layers) { layer in
                        let frame = displayedFrame(layer)
                        let spacing = displayedSpacing(layer)
                        DesignLayerView(layer: layer, size: frame.size, palette: phonePalette, spacing: spacing)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(layer.name)
                            .accessibilityAddTraits(editor.selectedID == layer.id ? .isSelected : [])
                            .accessibilityAction(named: "选择") {
                                editor.select(layer.id)
                                editor.focusCanvas()
                            }
                    }
                    if case let .drop(kind, frame, _)? = live {
                        DesignLayerView(layer: DesignLayer(kind: kind), size: frame.size, palette: phonePalette)
                            .opacity(0.62)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: page.bounds.width, height: page.bounds.height)
                .clipped()
            }
            .overlay {
                if page.layers.isEmpty, live == nil {
                    BlankArtboard(palette: palette)
                        .padding(.top, (IOSLayout.statusHeight - IOSLayout.homeHeight) * layout.scale)
                }
            }
            .background {
                Rectangle().fill(palette.field).shadow(color: .black.opacity(0.08), radius: 12, y: 2)
            }
            .overlay {
                Rectangle().strokeBorder(palette.artboardSeam, lineWidth: 0.5)
            }
        }
        .position(x: layout.first.x + layout.board.width / 2, y: layout.first.y + (layout.board.height - 32) / 2)
    }

    @ViewBuilder
    private func outline(_ layout: CanvasLayout) -> some View {
        if let selection = outlineSelection {
            let frame = layout.canvasRect(selectionFrame(selection))
            Canvas { context, _ in
                if let parent = selection.parent {
                    context.stroke(Path(layout.canvasRect(displayedFrame(parent))), with: .color(palette.accent),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                context.stroke(Path(frame), with: .color(palette.accent), lineWidth: canvasFocused ? 2 : 1)
                if selection.parent == nil {
                    for corner in Corner.allCases {
                        let handle = CGRect(origin: corner.point(in: frame), size: .zero).insetBy(dx: -3, dy: -3)
                        context.fill(Path(handle), with: .color(palette.field))
                        context.stroke(Path(handle), with: .color(palette.accent), lineWidth: 1.25)
                    }
                }
                if selection.layer.kind == .setting, frame.width >= 72 {
                    let center = spacingHandle(selection.layer, layout: layout)
                    let handle = Path(roundedRect: CGRect(x: center.x - 3, y: center.y - 8, width: 6, height: 16), cornerRadius: 3)
                    context.fill(handle, with: .color(palette.field))
                    context.stroke(handle, with: .color(palette.accent), lineWidth: 1.25)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func guides(_ layout: CanvasLayout) -> some View {
        Canvas { context, _ in
            for guide in live?.guides ?? [] {
                let start = layout.canvasPoint(guide.start)
                let end = layout.canvasPoint(guide.end)
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let distance = guide.distance {
                    let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    let label = context.resolve(Text(Double(distance).formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(palette.ink))
                    let size = label.measure(in: CGSize(width: 100, height: 24))
                    let badge = CGRect(x: midpoint.x - size.width / 2 - 4, y: midpoint.y - size.height / 2 - 1,
                                       width: size.width + 8, height: size.height + 2)
                    context.fill(Path(roundedRect: badge, cornerRadius: 4), with: .color(palette.field))
                    context.draw(label, at: midpoint)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func down(_ point: CGPoint, event: NSEvent, forcePan: Bool, layout: CanvasLayout) {
        live = nil
        let location = layout.documentPoint(point)
        guard !forcePan, point.x >= CanvasLayout.ruler, point.y >= CanvasLayout.ruler else {
            tracking = Tracking(start: point, pan: editor.pan, action: .pan)
            return
        }
        if let selection = editor.selection, selection.parent == nil {
            let layer = selection.layer
            let frame = layout.canvasRect(layer.frame)
            if let corner = Corner.allCases.first(where: { $0.point(in: frame).near(point, by: 8) }) {
                tracking = Tracking(start: point, pan: editor.pan, action: .resize(layer, corner))
                return
            }
            if layer.kind == .setting, frame.width >= 72, spacingHandle(layer, layout: layout).near(point, by: 8) {
                tracking = Tracking(start: point, pan: editor.pan, action: .spacing(layer))
                return
            }
        }
        guard let layer = editor.page.layers.last(where: { $0.frame.contains(location) }) else {
            tracking = Tracking(start: point, pan: editor.pan, action: .background)
            return
        }
        if layer.kind == .setting, event.clickCount == 2 || event.modifierFlags.contains(.command) || editor.enteredGroup == layer.id {
            if let child = layer.children.first(where: { layer.childFrame($0, in: layer.frame).contains(location) }) {
                editor.select(child.id)
                if event.clickCount > 2 { editor.startTextEditing() }
            } else {
                editor.enter(layer.id)
            }
            if event.clickCount == 2 || editor.selectedID != layer.id { return }
        } else if event.clickCount == 2 {
            editor.select(layer.id)
            editor.startTextEditing()
            return
        }
        tracking = Tracking(start: point, pan: editor.pan, action: .move(layer))
    }

    private func drag(_ point: CGPoint, layout: CanvasLayout) {
        guard let tracking, !point.near(tracking.start, by: 3) || live != nil else { return }
        let dx = (point.x - tracking.start.x) / layout.scale
        let dy = (point.y - tracking.start.y) / layout.scale
        switch tracking.action {
        case .pan, .background:
            editor.pan = CGPoint(x: tracking.pan.x + point.x - tracking.start.x,
                                 y: tracking.pan.y + point.y - tracking.start.y)
        case let .move(layer):
            let result = CanvasSnapping.place(layer.frame.offsetBy(dx: dx, dy: dy), kind: layer.kind,
                                             on: editor.page, excluding: layer.id, scale: layout.scale, enabled: snapEnabled)
            live = .move(layer.id, result.frame, result.guides)
        case let .resize(layer, corner):
            let frame = corner.resize(layer, dx: dx, dy: dy, within: editor.page.bounds)
            live = .move(layer.id, frame, [])
        case let .spacing(layer):
            let gap = min(max(0, layer.spacing - 2 * dx), layer.maximumSpacing)
            let right = layer.childFrame(layer.children[1], in: layer.frame, spacing: gap).minX
            let y = layer.frame.midY
            let guide = CanvasGuide(start: CGPoint(x: right - gap, y: y), end: CGPoint(x: right, y: y), distance: gap)
            live = .spacing(layer.id, layer.frame, gap, [guide])
        }
    }

    private func finish(_ point: CGPoint, layout: CanvasLayout) {
        defer {
            tracking = nil
            live = nil
        }
        guard let tracking else { return }
        drag(point, layout: layout)
        switch live {
        case let .move(id, frame, _):
            editor.setFrame(frame, of: id)
            editor.select(id)
        case let .spacing(id, _, gap, _):
            editor.setSpacing(gap, of: id)
        default:
            if point.near(tracking.start, by: 3) {
                switch tracking.action {
                case let .move(layer): editor.select(layer.id)
                case .background: editor.select(nil)
                default: break
                }
            }
        }
    }

    private func receive(_ kind: LayerKind?, at point: CGPoint, commit: Bool, layout: CanvasLayout) -> Bool {
        let destination = layout.documentPoint(point)
        guard let kind, LayerKind.catalog.contains(kind), editor.page.bounds.contains(destination),
              point.x >= CanvasLayout.ruler, point.y >= CanvasLayout.ruler else {
            if case .drop = live { live = nil }
            return false
        }
        let size = kind.defaultSize
        let origin = CGPoint(x: destination.x - size.width / 2, y: destination.y - size.height / 2)
        let result = CanvasSnapping.place(CGRect(origin: origin, size: size), kind: kind, on: editor.page,
                                         excluding: nil, scale: layout.scale, enabled: snapEnabled)
        if commit {
            editor.insert(kind, frame: result.frame)
            live = nil
        } else {
            live = .drop(kind, result.frame, result.guides)
        }
        return true
    }

    private func panBy(_ delta: CGPoint) {
        guard tracking == nil else { return }
        editor.pan = CGPoint(x: editor.pan.x + delta.x, y: editor.pan.y + delta.y)
    }

    private func magnify(_ amount: CGFloat, at point: CGPoint, layout: CanvasLayout, viewport: CGSize) {
        guard tracking == nil else { return }
        let scale = min(max(layout.scale * amount, 0.1), 4)
        let unpanned = makeLayout(viewport, scale: scale, pan: .zero)
        let anchored = unpanned.canvasPoint(layout.documentPoint(point))
        editor.magnification = scale
        editor.pan = CGPoint(x: point.x - anchored.x, y: point.y - anchored.y)
    }

    private func key(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.intersection([.command, .control]).isEmpty else { return false }
        if event.keyCode == 53 {
            if tracking != nil {
                tracking = nil
                live = nil
            } else if let group = editor.enteredGroup {
                editor.select(group)
            } else {
                editor.select(nil)
            }
            return true
        }
        if flags.contains(.option), [123, 124, 125, 126].contains(event.keyCode) {
            editor.selectAdjacent(forward: event.keyCode == 124 || event.keyCode == 125)
            return true
        }
        guard !flags.contains(.option), let selected = editor.selection else { return false }
        let layer = selected.layer
        switch event.keyCode {
        case 36, 76:
            if layer.kind == .setting { editor.select(layer.children[0].id) }
            else if layer.kind == .toggle { editor.update(layer.id, action: "切换开关") { $0.isOn.toggle() } }
            else { editor.startTextEditing() }
        case 51, 117: editor.removeSelection()
        case 123...126:
            guard selected.parent == nil else { return false }
            let amount: CGFloat = flags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0
            let dy: CGFloat = event.keyCode == 126 ? -amount : event.keyCode == 125 ? amount : 0
            editor.setFrame(layer.frame.offsetBy(dx: dx, dy: dy), of: layer.id)
        default: return false
        }
        return true
    }

    private var outlineSelection: (layer: DesignLayer, parent: DesignLayer?)? {
        if case let .move(id, _, _)? = live { return editor.page.selection(id) }
        return editor.selection
    }

    private func displayedFrame(_ layer: DesignLayer) -> CGRect {
        if case let .move(id, frame, _)? = live, id == layer.id { return frame }
        return layer.frame
    }

    private func displayedSpacing(_ layer: DesignLayer) -> CGFloat? {
        if case let .spacing(id, _, gap, _)? = live, id == layer.id { return gap }
        return nil
    }

    private func selectionFrame(_ selected: (layer: DesignLayer, parent: DesignLayer?)) -> CGRect {
        guard let parent = selected.parent else { return displayedFrame(selected.layer) }
        return parent.childFrame(selected.layer, in: displayedFrame(parent), spacing: displayedSpacing(parent))
    }

    private func spacingHandle(_ layer: DesignLayer, layout: CanvasLayout) -> CGPoint {
        let frame = displayedFrame(layer)
        let spacing = displayedSpacing(layer) ?? layer.spacing
        let edge = layer.childFrame(layer.children[1], in: frame, spacing: spacing).minX
        return layout.canvasPoint(CGPoint(x: edge - spacing / 2, y: frame.midY))
    }

    private struct Tracking {
        let start: CGPoint
        let pan: CGPoint
        let action: Action

        enum Action {
            case background, pan, move(DesignLayer), resize(DesignLayer, Corner), spacing(DesignLayer)
        }

    }

    private enum LiveChange: Equatable {
        case move(UUID, CGRect, [CanvasGuide])
        case spacing(UUID, CGRect, CGFloat, [CanvasGuide])
        case drop(LayerKind, CGRect, [CanvasGuide])

        var guides: [CanvasGuide] {
            switch self {
            case let .move(_, _, guides), let .spacing(_, _, _, guides), let .drop(_, _, guides): guides
            }
        }
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }

        func point(in frame: CGRect) -> CGPoint {
            CGPoint(x: isLeft ? frame.minX : frame.maxX, y: isTop ? frame.minY : frame.maxY)
        }

        func resize(_ layer: DesignLayer, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
            let frame = layer.frame
            let minSize = layer.kind.minimumSize
            let left = isLeft ? min(max(frame.minX + dx, bounds.minX), frame.maxX - minSize.width) : frame.minX
            let right = isLeft ? frame.maxX : max(min(frame.maxX + dx, bounds.maxX), frame.minX + minSize.width)
            let top = isTop ? min(max(frame.minY + dy, bounds.minY), frame.maxY - minSize.height) : frame.minY
            let bottom = isTop ? frame.maxY : max(min(frame.maxY + dy, bounds.maxY), frame.minY + minSize.height)
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }
}

private extension CGPoint {
    func near(_ other: CGPoint, by tolerance: CGFloat) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

private struct CanvasTextEditor: View {
    @State private var draft: String
    @State private var active = true
    @FocusState private var focused: Bool
    let label: String
    let palette: WorkbenchPalette
    let finish: (String?) -> Void
    let returnFocus: () -> Void

    init(initial: String, label: String, palette: WorkbenchPalette,
         finish: @escaping (String?) -> Void, returnFocus: @escaping () -> Void) {
        _draft = State(initialValue: initial)
        self.label = label
        self.palette = palette
        self.finish = finish
        self.returnFocus = returnFocus
    }

    var body: some View {
        TextField(label, text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .focused($focused)
            .accessibilityIdentifier("canvas-text-editor")
            .task { focused = true }
            .onSubmit { complete(draft, restore: true) }
            .onExitCommand { complete(nil, restore: true) }
            .onChange(of: focused) { wasFocused, focused in
                if wasFocused && !focused { complete(draft, restore: false) }
            }
    }

    private func complete(_ text: String?, restore: Bool) {
        guard active else { return }
        active = false
        finish(text)
        if restore { returnFocus() }
    }
}
