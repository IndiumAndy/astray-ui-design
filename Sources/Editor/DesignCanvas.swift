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
    let run: PreviewController
    let dismissPreview: () -> Void

    @State private var tracking: Tracking?
    @State private var live: LiveChange?
    @State private var canvasFocused = false
    @State private var wirePoint: CGPoint?
    @State private var boardDrag: (id: UUID, origin: CGPoint)?
    @State private var marquee: CGRect?
    @State private var templateDropFrame: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let layout = makeLayout(viewport, scale: editor.magnification, pan: editor.pan)
            ZStack(alignment: .topLeading) {
                CanvasRulers(layout: layout, palette: palette)
                    .accessibilityHidden(true)
                ZStack(alignment: .topLeading) {
                    ForEach(editor.project.pages.filter { $0.id != editor.page.id }, id: \.id) { page in
                        let frame = boardFrame(page, layout: layout)
                        if frame.insetBy(dx: 0, dy: -32).intersects(CGRect(origin: .zero, size: viewport)) {
                            backgroundBoard(page, frame: frame, scale: layout.scale)
                        }
                    }
                    board(layout)
                    connections(layout)
                    guides(layout)
                    outline(layout)
                    Canvas { context, _ in
                        for page in editor.project.pages where editor.selectedBoards.contains(page.id) {
                            context.stroke(Path(boardFrame(page, layout: layout)), with: .color(palette.accent), lineWidth: 2)
                        }
                        for frame in [marquee, templateDropFrame].compactMap({ $0 }) {
                            context.fill(Path(frame), with: .color(palette.accent.opacity(0.10)))
                            context.stroke(Path(frame), with: .color(palette.accent),
                                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
                    SimulatorPanel(simulator: run.simulator, width: width, height: viewport.height - 48,
                                   palette: palette, close: dismissPreview)
                    .task { await run.startPhone(editor) }
                    .onDisappear { run.simulator.stop() }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: preview.isCentered ? .center : .topTrailing)
                }
            }
            .background(palette.canvas)
            .clipped()
            .onChange(of: editor.overviewRequest) { _, _ in fitBoards(viewport) }
        }
        .onChange(of: snapEnabled) { _, _ in
            if case let .move(id, frame, _)? = live {
                live = .move(id, frame, [])
            } else if case .drop = live {
                live = nil
            }
        }
        .onChange(of: editor.page.id) { _, _ in
            tracking = nil
            live = nil
            wirePoint = nil
            boardDrag = nil
            editor.connectionSetup = nil
        }
        .sheet(isPresented: Binding(get: { editor.connectionSetup != nil }, set: {
            if !$0 { editor.connectionSetup = nil }
        })) {
            if let layer = editor.page.selection(editor.connectionSetup)?.layer {
                EventSettings(editor: editor, layer: layer)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画布")
    }

    private func makeLayout(_ viewport: CGSize, scale: CGFloat?, pan: CGPoint) -> CanvasLayout {
        let stable = CanvasLayout(window: viewport, device: editor.boardSize(using: editor.layout), zoom: zoom, flow: false,
                     trailingClearance: preview.canvasClearance, magnification: scale, pan: pan, inspectorInset: inspectorInset,
                     fitHeight: editor.page.size.height)
        guard let boardDrag, boardDrag.id == editor.page.id, let origin = editor.boardOrigins()[boardDrag.id] else { return stable }
        let moved = CGPoint(x: pan.x + (boardDrag.origin.x - origin.x) * stable.scale,
                            y: pan.y + (boardDrag.origin.y - origin.y) * stable.scale)
        return CanvasLayout(window: viewport, device: editor.boardSize(using: editor.layout), zoom: zoom, flow: false,
                            trailingClearance: preview.canvasClearance, magnification: stable.scale, pan: moved,
                            inspectorInset: inspectorInset, fitHeight: editor.page.size.height)
    }

    private func fitBoards(_ viewport: CGSize) {
        let origins = editor.boardOrigins()
        let current = origins[editor.page.id] ?? .zero
        let bounds = editor.project.pages.reduce(CGRect.null) { bounds, page in
            let size = page.id == editor.page.id ? editor.boardSize(using: editor.layout) : page.size
            return bounds.union(CGRect(origin: origins[page.id] ?? .zero, size: size))
        }
        let width = max(1, viewport.width - CanvasLayout.ruler - preview.canvasClearance - 64)
        let height = max(1, viewport.height - CanvasLayout.boardTop - 32)
        let scale = min(0.76, max(0.1, min(width / bounds.width, height / bounds.height)))
        let unpanned = makeLayout(viewport, scale: scale, pan: .zero)
        let left = CanvasLayout.ruler + 32 + max(0, (width - bounds.width * scale) / 2)
        let first = unpanned.canvasPoint(CGPoint(x: bounds.minX - current.x, y: bounds.minY - current.y))
        editor.magnification = scale
        editor.pan = CGPoint(x: left - first.x, y: CanvasLayout.boardTop - first.y)
    }

    private func boardFrame(_ page: DesignPage, layout: CanvasLayout) -> CGRect {
        let origins = editor.boardOrigins()
        func origin(_ id: UUID) -> CGPoint {
            if let boardDrag, boardDrag.id == id { return boardDrag.origin }
            return origins[id] ?? .zero
        }
        let current = origin(editor.page.id)
        let target = origin(page.id)
        let size = page.id == editor.page.id ? editor.boardSize(using: editor.layout) : page.size
        return layout.canvasRect(CGRect(origin: CGPoint(x: target.x - current.x, y: target.y - current.y), size: size))
    }

    private func backgroundBoard(_ page: DesignPage, frame: CGRect, scale: CGFloat) -> some View {
        let phonePalette = IOSSamplePalette(scheme: scheme)
        let contacts = editor.project.contacts ?? []
        let scene = ScreenLayout(page: page.runtime(styles: editor.project.buttonStyles ?? [], contacts: contacts, canvas: true),
                                 width: page.size.width, height: page.size.height, top: page.safeTop, bottom: page.safeBottom, device: editor.usesDeviceLayout ? page.deviceLayout : nil)
        let layers = Dictionary(uniqueKeysWithValues: page.allLayers.map { ($0.id.uuidString, $0) })
        return VStack(spacing: 0) {
            Text(page.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .frame(width: frame.width, height: 32, alignment: .leading)
            DevicePage(size: page.size, scale: scale) {
                ZStack(alignment: .topLeading) {
                    if page.safeTop > 0 { IOSArtboard { _ in Color.clear } }
                    else { phonePalette.grouped }
                    DesignReferenceView(page: page, offset: nil, palette: palette)
                    ForEach(scene.renderOrder, id: \.self) { id in
                        if let layer = layers[id],
                           let bounds = scene.artboardFrame(id, top: page.safeTop, bottom: page.safeBottom, height: page.size.height) {
                            DesignLayerView(layer: layer, size: bounds.size, palette: phonePalette,
                                            contacts: contacts, radius: layer.cornerRadius ?? editor.buttonStyle(for: layer)?.radius ?? 8)
                                .position(x: bounds.midX, y: bounds.midY)
                        }
                    }
                }
                .frame(width: page.size.width, height: page.size.height)
                .clipped()
            }
            .background {
                Rectangle().fill(palette.field).shadow(color: .black.opacity(0.08), radius: 12, y: 2)
            }
            .overlay { Rectangle().strokeBorder(palette.artboardSeam, lineWidth: 0.5) }
        }
        .position(x: frame.midX, y: frame.midY - 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.title)
        .accessibilityAction(named: "选择画板") { editor.showPage(page.id); editor.focusCanvas() }
    }

    private func port(in frame: CGRect) -> CGPoint { CGPoint(x: frame.maxX + 10, y: frame.midY) }

    private func connections(_ layout: CanvasLayout) -> some View {
        let pages = editor.project.pages
        let boards = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, boardFrame($0, layout: layout)) })
        return Canvas { context, bounds in
            let viewport = CGRect(origin: .zero, size: bounds)
            for page in pages {
                guard let source = boards[page.id] else { continue }
                let links = page.allLayers.filter { $0.behavior?.action != nil || $0.destination != nil }
                guard !links.isEmpty else { continue }
                let active = page.id == editor.page.id
                let scene = active ? editor.layout : ScreenLayout(page: page.runtime(styles: editor.project.buttonStyles ?? [],
                                                                                     contacts: editor.project.contacts ?? [], canvas: true),
                                                                  width: page.size.width, height: page.size.height, top: page.safeTop,
                                                                  bottom: page.safeBottom, device: editor.usesDeviceLayout ? page.deviceLayout : nil)
                for layer in links {
                    let frame = active ? displayedFrame(layer, layout: scene) :
                        scene.artboardFrame(layer.id.uuidString, top: page.safeTop, bottom: page.safeBottom, height: page.size.height) ?? layer.frame
                    let scaled = CGRect(x: source.minX + frame.minX * layout.scale, y: source.minY + frame.minY * layout.scale,
                                        width: frame.width * layout.scale, height: frame.height * layout.scale)
                    guard scaled.intersects(source) else { continue }
                    let selected = active && editor.selectedID == layer.id
                    let start = port(in: scaled)
                    if selected && wirePoint != nil { continue }
                    let action = layer.behavior?.action
                    let id = action?.target.flatMap(UUID.init(uuidString:)) ?? layer.destination
                    if let id, let target = boards[id], viewport.intersects(source.union(target)) {
                        let end = CGPoint(x: target.minX, y: target.minY + 24)
                        drawWire(from: start, to: end, in: context, emphasized: selected, dashed: action?.kind == .sheet)
                    } else if selected, let action {
                        let end = CGPoint(x: start.x + 24, y: start.y)
                        drawWire(from: start, to: end, in: context, emphasized: true, dashed: false)
                        let label = Text(action.name ?? action.kind.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.ink)
                        let text = context.resolve(label)
                        let size = text.measure(in: CGSize(width: 128, height: 24))
                        let chip = CGRect(x: end.x + 4, y: end.y - 11, width: size.width + 12, height: 22)
                        context.fill(Path(roundedRect: chip, cornerRadius: 4), with: .color(palette.field))
                        context.draw(text, at: CGPoint(x: chip.midX, y: chip.midY))
                    }
                }
            }
            if let selection = editor.selection, selection.layer.kind.hasAction {
                let frame = layout.canvasRect(selectionFrame(selection))
                if let source = boards[editor.page.id], source.intersects(frame) {
                    let start = port(in: frame)
                    if let wirePoint {
                        drawWire(from: start, to: wirePoint, in: context, emphasized: true, dashed: true)
                        if let target = dropBoard(at: wirePoint, layout: layout), let rect = boards[target.id] {
                            context.stroke(Path(rect), with: .color(palette.accent), lineWidth: 2)
                        }
                    }
                    let handle = Path(ellipseIn: CGRect(origin: start, size: .zero).insetBy(dx: -5, dy: -5))
                    context.fill(handle, with: .color(palette.field))
                    context.stroke(handle, with: .color(palette.accent), lineWidth: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawWire(from start: CGPoint, to end: CGPoint, in context: GraphicsContext, emphasized: Bool, dashed: Bool) {
        let reach = max(28, min(240, abs(end.x - start.x) * 0.5))
        let control = CGPoint(x: end.x - reach, y: end.y)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: start.x + reach, y: start.y), control2: control)
        path.move(to: CGPoint(x: end.x - 7, y: end.y - 4))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 7, y: end.y + 4))
        context.stroke(path, with: .color(palette.accent.opacity(emphasized ? 1 : 0.48)),
                       style: StrokeStyle(lineWidth: emphasized ? 2 : 1.25, dash: dashed ? [5, 4] : []))
    }

    private func dropBoard(at point: CGPoint, layout: CanvasLayout) -> DesignPage? {
        editor.project.pages.reversed().first { page in
            page.id != editor.page.id && boardFrame(page, layout: layout).insetBy(dx: 0, dy: -16).contains(point)
        }
    }

    private func board(_ layout: CanvasLayout) -> some View {
        let page = editor.page
        let phonePalette = IOSSamplePalette(scheme: scheme)
        let resolved = editor.layout
        let boardSize = editor.boardSize(using: resolved)
        let layers = Dictionary(uniqueKeysWithValues: page.allLayers.map { ($0.id.uuidString, $0) })
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(page.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if editor.usesDeviceLayout && layout.board.width >= 200 {
                    Text(editor.scopeTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                if layout.board.width >= 120 {
                    Text("\(Int(page.size.width)) × \(Int(page.size.height))").font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(palette.measure)
                }
            }
            .frame(width: layout.board.width, height: 32)
            .accessibilityAddTraits(.isHeader)

            DevicePage(size: boardSize, scale: layout.scale) {
                ZStack(alignment: .topLeading) {
                    if page.safeTop > 0 { IOSArtboard { _ in Color.clear } }
                    else { phonePalette.grouped }
                    DesignReferenceView(page: page, offset: editor.referenceOffset, palette: palette)
                    let ordered = resolved.renderOrder.compactMap { layers[$0] }
                    let bodyTop = page.safeTop + resolved.headerHeight
                    let bodyEnd = boardSize.height - page.safeBottom - resolved.footerHeight
                    components(ordered.filter { resolved.items[$0.id.uuidString]?.region == .body },
                               scene: resolved, palette: phonePalette)
                        .frame(width: boardSize.width, height: boardSize.height)
                        .mask(alignment: .top) {
                            Rectangle().frame(height: max(0, bodyEnd - bodyTop)).offset(y: bodyTop)
                        }
                    if resolved.headerHeight > 0 {
                        phonePalette.cell.frame(width: boardSize.width, height: resolved.headerHeight)
                            .position(x: boardSize.width / 2, y: page.safeTop + resolved.headerHeight / 2)
                    }
                    if resolved.footerHeight > 0 {
                        phonePalette.cell.frame(width: boardSize.width, height: resolved.footerHeight)
                            .position(x: boardSize.width / 2, y: bodyEnd + resolved.footerHeight / 2)
                    }
                    components(ordered.filter { resolved.items[$0.id.uuidString]?.region != .body },
                               scene: resolved, palette: phonePalette)
                    if editor.showsFullPage && boardSize.height > page.size.height {
                        Rectangle().strokeBorder(palette.measure, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .frame(width: boardSize.width, height: 1)
                            .overlay(alignment: .topTrailing) {
                                Text("首屏").font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(palette.field)
                                    .offset(y: -24)
                            }
                            .position(x: boardSize.width / 2, y: page.size.height)
                            .accessibilityLabel("首屏边界")
                    }
                    if case let .drop(kind, frame, _)? = live {
                        DesignLayerView(layer: DesignLayer(kind: kind), size: frame.size, palette: phonePalette)
                            .opacity(0.62)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: boardSize.width, height: boardSize.height)
                .clipped()
            }
            .overlay {
                if page.layers.isEmpty, page.reference == nil, live == nil {
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

    private func components(_ layers: [DesignLayer], scene: ScreenLayout, palette: IOSSamplePalette) -> some View {
        let size = editor.boardSize(using: scene)
        let bodyTop = editor.page.safeTop + scene.headerHeight
        let bodyBottom = size.height - editor.page.safeBottom - scene.footerHeight
        return ZStack(alignment: .topLeading) {
            ForEach(layers) { layer in
                let frame = displayedFrame(layer, layout: scene)
                let isOnBoard = scene.items[layer.id.uuidString]?.region != .body
                    || (frame.maxY > bodyTop && frame.minY < bodyBottom)
                DesignLayerView(layer: layer, size: frame.size, palette: palette,
                                spacing: displayedSpacing(layer), contacts: editor.project.contacts ?? [],
                                radius: layer.cornerRadius ?? editor.buttonStyle(for: layer)?.radius ?? 8)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityElement(children: .combine)
                    .accessibilityHidden(!isOnBoard)
                    .accessibilityLabel(layer.name)
                    .accessibilityAddTraits(editor.selectedIDs.contains(layer.id) ? .isSelected : [])
                    .accessibilityAction(named: "选择") {
                        editor.select(layer.id)
                        editor.focusCanvas()
                    }
                    .accessibilityActions {
                        if layer.kind.hasAction {
                            Button("设置事件") {
                                editor.select(layer.id)
                                editor.connectionSetup = layer.id
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func outline(_ layout: CanvasLayout) -> some View {
        let scene = editor.layout
        let board = CGRect(origin: .zero, size: editor.boardSize(using: scene))
        if let selection = outlineSelection, board.intersects(selectionFrame(selection)) {
            let frame = layout.canvasRect(selectionFrame(selection))
            Canvas { context, _ in
                if let parent = selection.parent {
                    context.stroke(Path(layout.canvasRect(displayedFrame(parent))), with: .color(palette.accent),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                for id in editor.additionalSelection {
                    if let layer = editor.page.selection(id)?.layer {
                        context.stroke(Path(layout.canvasRect(displayedFrame(layer))), with: .color(palette.accent), lineWidth: 1)
                    }
                }
                context.stroke(Path(frame), with: .color(palette.accent), lineWidth: canvasFocused ? 2 : 1)
                if selection.parent?.kind != .setting {
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
        let scene = editor.layout
        if let selection = editor.selection, selection.layer.kind.hasAction,
           port(in: layout.canvasRect(selectionFrame(selection))).near(point, by: 9) {
            tracking = Tracking(start: point, pan: editor.pan, action: .connect(selection.layer.id))
            return
        }
        let origins = editor.boardOrigins()
        if let page = ([editor.page] + editor.project.pages.filter { $0.id != editor.page.id }).first(where: { page in
            let frame = boardFrame(page, layout: layout)
            return CGRect(x: frame.minX, y: frame.minY - 32, width: frame.width, height: 32).contains(point)
        }) {
            if event.modifierFlags.contains(.shift) {
                var selection = editor.selectedBoards
                if selection.remove(page.id) == nil { selection.insert(page.id) }
                editor.selectBoards(selection)
                return
            }
            tracking = Tracking(start: point, pan: editor.pan, action: .board(page.id, origins[page.id] ?? .zero))
            return
        }
        if !boardFrame(editor.page, layout: layout).contains(point), let page = dropBoard(at: point, layout: layout) {
            tracking = Tracking(start: point, pan: editor.pan, action: .otherPage(page.id))
            return
        }
        if let selection = editor.selection, selection.parent?.kind != .setting {
            let layer = selection.layer
            let frame = layout.canvasRect(editor.frame(of: layer, using: scene))
            if let corner = Corner.allCases.first(where: { $0.point(in: frame).near(point, by: 8) }) {
                tracking = Tracking(start: point, pan: editor.pan, action: .resize(layer, frame: editor.frame(of: layer, using: scene), corner))
                return
            }
            if layer.kind == .setting, frame.width >= 72, spacingHandle(layer, layout: layout).near(point, by: 8) {
                tracking = Tracking(start: point, pan: editor.pan, action: .spacing(layer))
                return
            }
        }
        let roots = editor.page.layers.sorted {
            let rank: [LayoutRegion: Int] = [.body: 0, .header: 1, .footer: 1]
            return rank[$0.placement(for: editor.scope).region ?? .body, default: 0]
                < rank[$1.placement(for: editor.scope).region ?? .body, default: 0]
        }
        guard let root = roots.last(where: { editor.frame(of: $0, using: scene).contains(location) }) else {
            let action: Tracking.Action
            if event.modifierFlags.contains(.shift) {
                action = .marquee
            } else if let image = editor.page.referenceImage, !image.isLocked, !image.isHidden,
               editor.page.bounds.contains(location) {
                action = .reference(image.offset)
            } else {
                action = .background
            }
            tracking = Tracking(start: point, pan: editor.pan, action: action)
            return
        }
        if event.modifierFlags.contains(.shift) {
            editor.toggleSelection(root.id)
            return
        }
        let clicked = hit(root, at: location, deep: event.modifierFlags.contains(.command),
                          double: event.clickCount == 2, scene: scene)
        if event.clickCount == 2 {
            if clicked.kind.isContainer || clicked.kind == .setting { editor.enter(clicked.id) }
            else {
                editor.select(clicked.id)
                if root.kind != .setting || clicked.id == root.id || event.modifierFlags.contains(.command) {
                    editor.startTextEditing()
                }
            }
            return
        }
        let parent = editor.page.selection(clicked.id)?.parent
        if parent?.kind == .setting {
            editor.select(clicked.id)
        } else if let parent, parent.placement(for: editor.scope).arrangement != .free {
            tracking = Tracking(start: point, pan: editor.pan, action: .reorder(clicked, parent))
        } else {
            tracking = Tracking(start: point, pan: editor.pan,
                                action: .move(clicked, frame: editor.frame(of: clicked, using: scene)))
        }
    }

    private func hit(_ layer: DesignLayer, at point: CGPoint, deep: Bool, double: Bool, scene: ScreenLayout) -> DesignLayer {
        guard deep || double || editor.enteredGroup == layer.id || editor.enteredGroup.map({
            id in layer.descendants.contains { $0.id == id }
        }) == true else { return layer }
        guard let child = editor.siblings(of: layer).last(where: { editor.frame(of: $0, using: scene).contains(point) })
        else { return layer }
        return deep ? hit(child, at: point, deep: true, double: false, scene: scene) : child
    }

    private func drag(_ point: CGPoint, layout: CanvasLayout) {
        guard let tracking, !point.near(tracking.start, by: 3) || live != nil else { return }
        let dx = (point.x - tracking.start.x) / layout.scale
        let dy = (point.y - tracking.start.y) / layout.scale
        switch tracking.action {
        case .pan, .background, .otherPage:
            editor.pan = CGPoint(x: tracking.pan.x + point.x - tracking.start.x,
                                 y: tracking.pan.y + point.y - tracking.start.y)
        case .marquee:
            marquee = CGRect(x: min(point.x, tracking.start.x), y: min(point.y, tracking.start.y),
                             width: abs(point.x - tracking.start.x), height: abs(point.y - tracking.start.y))
        case .connect:
            wirePoint = point
        case let .board(id, origin):
            boardDrag = (id, CGPoint(x: origin.x + dx, y: origin.y + dy))
        case let .move(layer, frame):
            let pinned = (layer.placement(for: editor.scope).region ?? .body) != .body
            let proposed = frame.offsetBy(dx: dx, dy: pinned ? 0 : dy)
            if editor.page.selection(layer.id)?.parent != nil {
                live = .move(layer.id, proposed, [])
            } else {
                let result = snap(proposed, kind: layer.kind, excluding: layer.id, layout: layout)
                live = .move(layer.id, result.frame, result.guides)
            }
        case let .resize(layer, frame, corner):
            let bounds = CGRect(x: 0, y: 0, width: editor.page.bounds.width, height: DesignPage.maximumContentHeight)
            live = .move(layer.id, corner.resize(frame, minimum: layer.kind.minimumSize, dx: dx, dy: dy, within: bounds), [])
        case let .reorder(layer, parent):
            let scene = editor.layout
            let position = layout.documentPoint(point)
            let siblings = editor.siblings(of: parent)
            if let target = siblings.enumerated().min(by: {
                distance(position, editor.frame(of: $0.element, using: scene))
                    < distance(position, editor.frame(of: $1.element, using: scene))
            }) {
                let frame = editor.frame(of: target.element, using: scene)
                let guide = CanvasGuide(start: CGPoint(x: frame.minX, y: frame.minY), end: CGPoint(x: frame.maxX, y: frame.minY))
                live = .reorder(layer.id, target.offset, [guide])
            }
        case let .reference(origin):
            editor.referenceOffset = CGPoint(x: origin.x + dx, y: origin.y + dy)
        case let .spacing(layer):
            let frame = editor.frame(of: layer)
            let gap = min(max(0, (displayedGap(layer) - 2 * dx)), max(0, min(96, frame.width - 108)))
            let right = layer.childFrame(layer.children[1], in: frame, spacing: gap).minX
            let y = frame.midY
            let guide = CanvasGuide(start: CGPoint(x: right - gap, y: y), end: CGPoint(x: right, y: y), distance: gap)
            live = .spacing(layer.id, frame, gap, [guide])
        }
    }

    private func finish(_ point: CGPoint, layout: CanvasLayout) {
        defer {
            tracking = nil
            live = nil
            boardDrag = nil
            wirePoint = nil
            marquee = nil
        }
        guard let tracking else { return }
        drag(point, layout: layout)
        if case .marquee = tracking.action {
            if let marquee {
                editor.selectBoards(Set(editor.project.pages.filter {
                    boardFrame($0, layout: layout).intersects(marquee)
                }.map(\.id)))
            }
            return
        }
        if case let .connect(id) = tracking.action {
            if wirePoint != nil, let page = dropBoard(at: point, layout: layout) {
                let kind: ActionKind = NSEvent.modifierFlags.contains(.option) ? .sheet : .navigate
                editor.connect(id, to: .page(kind, page.id))
            } else {
                editor.connectionSetup = id
            }
            return
        }
        if case let .board(id, origin) = tracking.action {
            if let boardDrag {
                if id == editor.page.id {
                    editor.pan.x += (boardDrag.origin.x - origin.x) * layout.scale
                    editor.pan.y += (boardDrag.origin.y - origin.y) * layout.scale
                }
                editor.moveBoard(id, to: boardDrag.origin)
            } else if id != editor.page.id { editor.showPage(id) }
            return
        }
        if case let .otherPage(id) = tracking.action, point.near(tracking.start, by: 3) {
            editor.showPage(id)
            return
        }
        if case .reference = tracking.action, let offset = editor.referenceOffset {
            editor.updateReference("移动对照底图") { $0.offset = offset }
            editor.referenceOffset = nil
        }
        switch live {
        case let .move(id, frame, _):
            let resizing: Bool
            if case .resize = tracking.action { resizing = true } else { resizing = false }
            editor.setFrame(frame, of: id, resizing: resizing)
            editor.select(id)
        case let .reorder(id, index, _):
            editor.reorder(id, to: index)
            editor.select(id)
        case let .spacing(id, _, gap, _):
            editor.setSpacing(gap, of: id)
        default:
            if point.near(tracking.start, by: 3) {
                switch tracking.action {
                case let .move(layer, _), let .reorder(layer, _): editor.select(layer.id)
                case .background: editor.select(nil)
                default: break
                }
            }
        }
    }

    private func receive(_ payload: CanvasDragPayload?, at point: CGPoint, commit: Bool, layout: CanvasLayout) -> Bool {
        let destination = layout.documentPoint(point)
        templateDropFrame = nil
        if case .template(let id) = payload,
           let template = PersonalLibrary.shared.templates.first(where: { $0.id == id }),
           point.x >= CanvasLayout.ruler, point.y >= CanvasLayout.ruler {
            let pageFrame = CGRect(origin: .zero, size: editor.boardSize(using: editor.layout))
            if template.kind.insertsLayers, !pageFrame.contains(destination) { return false }
            if commit {
                editor.insertTemplate(template, at: destination)
            } else if template.kind.insertsLayers {
                let bounds = template.project.page.layers.reduce(CGRect.null) { $0.union($1.frame) }
                if !bounds.isNull {
                    templateDropFrame = layout.canvasRect(CGRect(origin: destination, size: bounds.size).intersection(pageFrame))
                }
            } else {
                templateDropFrame = boardFrame(editor.page, layout: layout)
            }
            return true
        }
        guard case .component(let kind) = payload, LayerKind.catalog.contains(kind), CGRect(origin: .zero, size: editor.boardSize(using: editor.layout)).contains(destination),
              point.x >= CanvasLayout.ruler, point.y >= CanvasLayout.ruler else {
            if case .drop = live { live = nil }
            return false
        }
        let size = kind.defaultSize
        let origin = CGPoint(x: destination.x - size.width / 2, y: destination.y - size.height / 2)
        let result = snap(CGRect(origin: origin, size: size), kind: kind, excluding: nil, layout: layout)
        if commit {
            let target = editor.page.allLayers.last { layer in
                layer.kind == .layout && editor.frame(of: layer).contains(destination)
            }
            editor.insert(kind, frame: result.frame, into: target?.id)
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
        if flags.contains(.command), event.charactersIgnoringModifiers == "d", editor.selection != nil {
            editor.duplicateSelection()
            return true
        }
        guard flags.intersection([.command, .control]).isEmpty else { return false }
        if event.keyCode == 53 {
            if tracking != nil {
                tracking = nil
                live = nil
                editor.referenceOffset = nil
                boardDrag = nil
                wirePoint = nil
            } else if let group = editor.enteredGroup {
                editor.select(group)
            } else {
                editor.select(nil)
            }
            return true
        }
        if flags.contains(.option), event.charactersIgnoringModifiers?.lowercased() == "l",
           let layer = editor.selection?.layer, layer.kind.hasAction {
            editor.connectionSetup = layer.id
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
            if let child = editor.siblings(of: layer).first { editor.select(child.id) }
            else if layer.kind == .toggle { editor.update(layer.id, action: "切换开关") { $0.isOn.toggle() } }
            else { editor.startTextEditing() }
        case 51, 117: editor.removeSelection()
        case 123...126:
            if let parent = selected.parent {
                guard parent.kind.isContainer, let index = editor.siblings(of: parent).firstIndex(where: { $0.id == layer.id }) else { return false }
                editor.reorder(layer.id, to: index + (event.keyCode == 123 || event.keyCode == 126 ? -1 : 1))
                return true
            }
            let amount: CGFloat = flags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0
            let dy: CGFloat = event.keyCode == 126 ? -amount : event.keyCode == 125 ? amount : 0
            editor.setFrame(editor.frame(of: layer).offsetBy(dx: dx, dy: dy), of: layer.id, resizing: false)
        default: return false
        }
        return true
    }

    private var outlineSelection: (layer: DesignLayer, parent: DesignLayer?)? {
        if case let .move(id, _, _)? = live { return editor.page.selection(id) }
        return editor.selection
    }

    private func displayedFrame(_ layer: DesignLayer, layout: ScreenLayout? = nil) -> CGRect {
        if case let .move(id, frame, _)? = live, id == layer.id { return frame }
        let frame = editor.frame(of: layer, using: layout)
        if case let .move(id, new, _)? = live, let moved = editor.page.selection(id)?.layer,
           moved.descendants.dropFirst().contains(where: { $0.id == layer.id }) {
            let old = editor.frame(of: moved, using: layout)
            return frame.offsetBy(dx: new.minX - old.minX, dy: new.minY - old.minY)
        }
        return frame
    }

    private func snap(_ frame: CGRect, kind: LayerKind, excluding: UUID?, layout: CanvasLayout) -> SnappedFrame {
        let scene = editor.layout
        let bounds = CGRect(origin: .zero, size: editor.boardSize(using: scene))
        let peers = editor.page.layers.filter { $0.id != excluding }.map { editor.frame(of: $0, using: scene) }
        return CanvasSnapping.place(frame, kind: kind, on: editor.page, excluding: excluding, scale: layout.scale,
                                    enabled: snapEnabled, visibleBounds: bounds, resolvedPeers: peers)
    }

    private func distance(_ point: CGPoint, _ frame: CGRect) -> CGFloat {
        hypot(point.x - frame.midX, point.y - frame.midY)
    }

    private func displayedSpacing(_ layer: DesignLayer) -> CGFloat? {
        if case let .spacing(id, _, gap, _)? = live, id == layer.id { return gap }
        return layer.placement(for: editor.scope).gap
    }

    private func displayedGap(_ layer: DesignLayer) -> CGFloat {
        layer.placement(for: editor.scope).gap ?? layer.spacing
    }

    private func selectionFrame(_ selected: (layer: DesignLayer, parent: DesignLayer?)) -> CGRect {
        guard let parent = selected.parent else { return displayedFrame(selected.layer) }
        return parent.kind == .setting
            ? parent.childFrame(selected.layer, in: displayedFrame(parent), spacing: displayedSpacing(parent))
            : displayedFrame(selected.layer)
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
            case background, pan, marquee
            case board(UUID, CGPoint), connect(UUID), otherPage(UUID)
            case move(DesignLayer, frame: CGRect), resize(DesignLayer, frame: CGRect, Corner)
            case spacing(DesignLayer), reorder(DesignLayer, DesignLayer), reference(CGPoint)
        }

    }

    private enum LiveChange: Equatable {
        case move(UUID, CGRect, [CanvasGuide])
        case spacing(UUID, CGRect, CGFloat, [CanvasGuide])
        case drop(LayerKind, CGRect, [CanvasGuide])
        case reorder(UUID, Int, [CanvasGuide])

        var guides: [CanvasGuide] {
            switch self {
            case let .move(_, _, guides), let .spacing(_, _, _, guides), let .drop(_, _, guides), let .reorder(_, _, guides): guides
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

        func resize(_ frame: CGRect, minimum minSize: CGSize, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
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
