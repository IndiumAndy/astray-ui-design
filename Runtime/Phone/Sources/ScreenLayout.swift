import Foundation

enum DeviceLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone, tablet, desktop

    init(width: CGFloat) {
        self = width < 600 ? .phone : width < 1000 ? .tablet : .desktop
    }

    var id: Self { self }
    var title: String {
        switch self {
        case .phone: "手机"
        case .tablet: "平板"
        case .desktop: "桌面"
        }
    }
}

enum LayoutSizeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed, content, fill
    var id: Self { self }
    var title: String {
        switch self {
        case .fixed: "固定值"
        case .content: "随内容"
        case .fill: "填满"
        }
    }
}

enum Arrangement: String, Codable, CaseIterable, Identifiable, Sendable {
    case free, vertical, horizontal, grid
    var id: Self { self }
    var title: String {
        switch self {
        case .free: "自由摆放"
        case .vertical: "纵排"
        case .horizontal: "横排"
        case .grid: "网格"
        }
    }
}

enum LayoutRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case body, header, footer
    var id: Self { self }
    var title: String {
        switch self {
        case .body: "随页面滚动"
        case .header: "固定顶栏"
        case .footer: "固定底栏"
        }
    }
}

struct LayoutBox: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ frame: CGRect) {
        x = frame.minX
        y = frame.minY
        width = frame.width
        height = frame.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct LayerGeometry: Codable, Equatable, Sendable {
    var frame: LayoutBox?
    var width: LayoutSizeMode?
    var height: LayoutSizeMode?
    var arrangement: Arrangement?
    var gap: CGFloat?
    var columns: Int?
    var stackAtNarrowWidth: Bool?
    var order: [String]?
    var region: LayoutRegion?

    func applying(_ override: Self?) -> Self {
        guard let override else { return self }
        return Self(frame: override.frame ?? frame, width: override.width ?? width, height: override.height ?? height,
                    arrangement: override.arrangement ?? arrangement, gap: override.gap ?? gap,
                    columns: override.columns ?? columns, stackAtNarrowWidth: override.stackAtNarrowWidth ?? stackAtNarrowWidth,
                    order: override.order ?? order, region: override.region ?? region)
    }

    var isValid: Bool {
        (frame.map { [$0.x, $0.y, $0.width, $0.height].allSatisfy { (0...24_000).contains($0) }
            && $0.width > 0 && $0.height > 0 } ?? true)
        && (gap.map { (0...192).contains($0) } ?? true)
        && (columns.map { (2...6).contains($0) } ?? true)
        && (order.map { Set($0).count == $0.count } ?? true)
    }
}

struct ScreenLayout {
    struct Item: Equatable {
        let frame: CGRect
        let region: LayoutRegion
    }

    let items: [String: Item]
    let bodyHeight: CGFloat
    let headerHeight: CGFloat
    let footerHeight: CGFloat
    let renderOrder: [String]

    func artboardFrame(_ id: String, top: CGFloat, bottom: CGFloat, height: CGFloat) -> CGRect? {
        guard let item = items[id] else { return nil }
        let offset: CGFloat
        switch item.region {
        case .header: offset = top
        case .body: offset = top + headerHeight
        case .footer: offset = height - bottom - footerHeight
        }
        return item.frame.offsetBy(dx: 0, dy: offset)
    }

    init(page: RuntimePage, width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat = 0,
         device: DeviceLayout?, textScale: CGFloat = 1) {
        var engine = Engine(width: width, height: max(0, height - top - bottom), baseWidth: page.width,
                            device: device, textScale: textScale, layers: page.layers)
        headerHeight = engine.placeRoots(.header, top: top)
        footerHeight = engine.placeRoots(.footer, top: top)
        engine.height = max(0, engine.height - headerHeight - footerHeight)
        let bodyEnd = engine.placeRoots(.body, top: top)
        bodyHeight = max(engine.height, bodyEnd + 24)
        items = engine.items
        renderOrder = engine.renderOrder
    }

    private struct Engine {
        let width: CGFloat
        var height: CGFloat
        let baseWidth: CGFloat
        let device: DeviceLayout?
        let textScale: CGFloat
        var items: [String: Item] = [:]
        var renderOrder: [String] = []
        let hierarchy: [String?: [RuntimeLayer]]

        init(width: CGFloat, height: CGFloat, baseWidth: CGFloat, device: DeviceLayout?, textScale: CGFloat,
             layers: [RuntimeLayer]) {
            self.width = width
            self.height = height
            self.baseWidth = baseWidth
            self.device = device
            self.textScale = textScale
            hierarchy = Dictionary(grouping: layers, by: \.parent)
        }

        func geometry(_ layer: RuntimeLayer) -> LayerGeometry {
            (layer.geometry ?? LayerGeometry()).applying(device.flatMap { layer.overrides?[$0.rawValue] })
        }

        func raw(_ layer: RuntimeLayer) -> CGRect {
            geometry(layer).frame?.rect ?? CGRect(x: layer.x, y: layer.y, width: layer.width, height: layer.height)
        }

        mutating func placeRoots(_ region: LayoutRegion, top: CGFloat) -> CGFloat {
            var end: CGFloat = 0
            for layer in hierarchy[nil] ?? [] where (geometry(layer).region ?? .body) == region {
                let spec = geometry(layer)
                let frame = raw(layer)
                let ratio = width / max(1, baseWidth)
                let leading = spec.width == nil ? frame.minX * ratio : frame.minX
                let minimum = min(width, layer.minimumWidth)
                let x = min(max(0, leading), max(0, width - minimum))
                let y = region == .body ? max(0, frame.minY - top) : end
                let available = max(0, width - x - (spec.width == .fill ? min(24, x) : 0))
                let w = extent(layer, available: available, proportional: ratio)
                    .clamped(to: minimum...max(minimum, width - x))
                let plan = measure(layer, width: w, availableHeight: max(0, height - y))
                place(plan, at: CGPoint(x: x, y: y), region: region)
                end = max(end, y + plan.size.height)
            }
            return end
        }

        func measure(_ layer: RuntimeLayer, width: CGFloat, availableHeight: CGFloat) -> Plan {
            let spec = geometry(layer)
            let frame = raw(layer)
            let mode = spec.height
            let baseHeight = layer.styleHeight ?? frame.height
            let proposedHeight = switch mode {
            case .fill: max(layer.minimumHeight, availableHeight)
            case .fixed: frame.height
            case .content, .none: baseHeight
            }
            var children = hierarchy[layer.id] ?? []
            if let order = spec.order {
                let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
                children = children.enumerated().sorted {
                    (rank[$0.element.id] ?? order.count, $0.offset) < (rank[$1.element.id] ?? order.count, $1.offset)
                }.map(\.element)
            }
            if children.isEmpty {
                let intrinsic = intrinsicHeight(layer, width: width)
                let height = mode == .content ? intrinsic : proposedHeight
                return Plan(id: layer.id, size: CGSize(width: width, height: max(height, layer.contentMinimum ?? 0)), children: [])
            }

            let arrangement = spec.arrangement ?? .free
            let narrow = spec.stackAtNarrowWidth == true && width < 420
            let columnCount = switch arrangement {
            case .vertical, .free: 1
            case .horizontal: narrow ? 1 : children.count
            case .grid: narrow ? 1 : min(children.count, spec.columns ?? 2)
            }
            let gap = columnCount > 1
                ? min(spec.gap ?? 12, max(0, (width - 16 * CGFloat(columnCount)) / CGFloat(columnCount - 1)))
                : spec.gap ?? 12
            var plans: [ChildPlan] = []
            var bottom: CGFloat = 0
            if arrangement == .free {
                for child in children {
                    let frame = raw(child)
                    let x = min(frame.minX, max(0, width - child.minimumWidth))
                    let w = extent(child, available: max(0, width - x))
                    let plan = measure(child, width: w, availableHeight: max(0, proposedHeight - frame.minY))
                    plans.append(ChildPlan(origin: CGPoint(x: x, y: frame.minY), plan: plan))
                    bottom = max(bottom, frame.minY + plan.size.height)
                }
            } else {
                let rowCount = (children.count + columnCount - 1) / columnCount
                let rowHeight = max(0, (proposedHeight - gap * CGFloat(rowCount - 1)) / CGFloat(rowCount))
                for start in stride(from: 0, to: children.count, by: columnCount) {
                    let row = Array(children[start..<min(children.count, start + columnCount)])
                    let count = arrangement == .grid ? columnCount : row.count
                    let available = max(0, width - gap * CGFloat(count - 1))
                    let cell = available / CGFloat(count)
                    let widths = rowWidths(row, arrangement: arrangement, columns: count, width: available, cell: cell)
                    var x: CGFloat = 0
                    var maxHeight: CGFloat = 0
                    for (child, w) in zip(row, widths) {
                        let plan = measure(child, width: w, availableHeight: mode == .content ? raw(child).height : rowHeight)
                        plans.append(ChildPlan(origin: CGPoint(x: x, y: bottom), plan: plan))
                        x += (arrangement == .grid ? cell : w) + gap
                        maxHeight = max(maxHeight, plan.size.height)
                    }
                    bottom += maxHeight + gap
                }
                bottom -= gap
            }
            // Keep overflowing children reachable when a fixed container is smaller than its contents.
            let measured = max(layer.minimumHeight, mode == .content ? bottom : max(proposedHeight, bottom))
            if layer.isActionRow && arrangement == .horizontal && !narrow {
                plans = plans.map { child in
                    let y = max(0, (measured - child.plan.size.height) / 2)
                    return ChildPlan(origin: CGPoint(x: child.origin.x, y: y), plan: child.plan)
                }
            }
            return Plan(id: layer.id, size: CGSize(width: width, height: measured), children: plans)
        }

        func rowWidths(_ row: [RuntimeLayer], arrangement: Arrangement, columns: Int, width: CGFloat, cell: CGFloat) -> [CGFloat] {
            guard arrangement != .grid, columns > 1 else {
                return row.map { extent($0, available: cell) }
            }
            let fixed = row.map { geometry($0).width == .fill ? 0 : extent($0, available: width) }
            let used = fixed.reduce(0, +)
            let fills = row.count - fixed.filter { $0 > 0 }.count
            let fillMinimum = zip(row, fixed).reduce(0.0) { $0 + ($1.1 == 0 ? $1.0.minimumWidth : 0) }
            let fixedSpace = max(0, width - min(fillMinimum, width / 2))
            let scale = used > fixedSpace && used > 0 ? fixedSpace / used : 1
            let fill = max(0, width - used * scale) / CGFloat(max(1, fills))
            return fixed.map { $0 > 0 ? $0 * scale : fill }
        }

        func extent(_ layer: RuntimeLayer, available: CGFloat, proportional: CGFloat = 1) -> CGFloat {
            let spec = geometry(layer)
            let frame = raw(layer)
            let length = switch spec.width {
            case .fixed: frame.width
            case .content: intrinsicWidth(layer)
            case .fill: available
            case .none: frame.width * proportional
            }
            return min(max(0, available), max(layer.minimumWidth, length))
        }

        func intrinsicWidth(_ layer: RuntimeLayer) -> CGFloat {
            let frame = raw(layer)
            let children = hierarchy[layer.id] ?? []
            if layer.isContainer, !children.isEmpty {
                let spec = geometry(layer)
                let gap = spec.gap ?? 12
                let widths = children.map { child in
                    geometry(child).width == .content ? intrinsicWidth(child) : raw(child).width
                }
                let widest = widths.max() ?? frame.width
                return switch spec.arrangement {
                case .vertical: widest
                case .horizontal: widths.reduce(0, +) + CGFloat(widths.count - 1) * gap
                case .grid: widest * CGFloat(min(widths.count, spec.columns ?? 2))
                    + CGFloat(min(widths.count, spec.columns ?? 2) - 1) * gap
                case .free, .none: zip(children, widths).map { raw($0).minX + $1 }.max() ?? frame.width
                }
            }
            if ["title", "label", "button", "input"].contains(layer.kind) {
                let font: CGFloat = layer.kind == "title" && layer.field != .phone ? 28 : 16
                return (lineWidths(layer.text, font: font).max() ?? 0) + layer.textPadding
            }
            return frame.width
        }

        func lineWidths(_ text: String, font: CGFloat) -> [CGFloat] {
            text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                let count = line.unicodeScalars.reduce(0.0) { $0 + ($1.value < 128 ? 0.56 : 1) }
                return count * font * textScale
            }
        }

        func lineCount(_ text: String, font: CGFloat, width: CGFloat) -> CGFloat {
            lineWidths(text, font: font).reduce(0) { $0 + max(1, ceil($1 / max(1, width))) }
        }

        func intrinsicHeight(_ layer: RuntimeLayer, width: CGFloat) -> CGFloat {
            guard ["title", "label", "button", "input"].contains(layer.kind) else {
                return layer.styleHeight ?? raw(layer).height
            }
            let font: CGFloat = layer.kind == "title" && layer.field != .phone ? 28 : 16
            let lines = layer.kind == "input" ? 1 : lineCount(layer.text, font: font, width: width - layer.textPadding)
            let padding: CGFloat = layer.kind == "input" || layer.kind == "button" ? 16 : 4
            let field = max(layer.minimumHeight, ceil(lines * font * 1.3 * textScale) + padding)
            if let hint = layer.fieldHint, !hint.isEmpty {
                return field + 4 + ceil(lineCount(hint, font: 12, width: width) * 16 * textScale)
            }
            return field
        }

        mutating func place(_ plan: Plan, at point: CGPoint, region: LayoutRegion) {
            items[plan.id] = Item(frame: CGRect(origin: point, size: plan.size), region: region)
            renderOrder.append(plan.id)
            for child in plan.children {
                place(child.plan, at: CGPoint(x: point.x + child.origin.x, y: point.y + child.origin.y), region: region)
            }
        }
    }

    private struct Plan {
        let id: String
        let size: CGSize
        let children: [ChildPlan]
    }

    private struct ChildPlan {
        let origin: CGPoint
        let plan: Plan
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
