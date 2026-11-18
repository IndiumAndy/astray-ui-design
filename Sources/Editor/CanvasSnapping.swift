import Foundation

struct CanvasGuide: Equatable {
    let start: CGPoint
    let end: CGPoint
    var distance: CGFloat?
}

struct SnappedFrame: Equatable {
    let frame: CGRect
    let guides: [CanvasGuide]
}

enum CanvasSnapping {
    static func place(
        _ frame: CGRect, kind: LayerKind, on page: DesignPage,
        excluding id: UUID?, scale: CGFloat, enabled: Bool,
        visibleBounds: CGRect? = nil, resolvedPeers: [CGRect]? = nil
    ) -> SnappedFrame {
        let frame = page.constrain(frame, kind: kind)
        guard enabled else { return SnappedFrame(frame: frame, guides: []) }
        let bounds = visibleBounds ?? page.bounds
        let peers = (resolvedPeers ?? page.layers.filter { $0.id != id }.map(\.frame)) + (page.reference?.guides(in: page) ?? [])
        let tolerance = 6 / scale
        let horizontal = best(.horizontal, frame: frame, bounds: bounds, peers: peers, tolerance: tolerance)
        let vertical = best(.vertical, frame: frame, bounds: bounds, peers: peers, tolerance: tolerance)
        let placed = frame.offsetBy(dx: horizontal?.delta ?? 0, dy: vertical?.delta ?? 0)
        let guides = (horizontal?.guides(for: placed, on: .horizontal) ?? [])
            + (vertical?.guides(for: placed, on: .vertical) ?? [])
        return SnappedFrame(frame: placed, guides: guides)
    }

    private enum Axis {
        case horizontal, vertical

        func limits(_ rect: CGRect) -> ClosedRange<CGFloat> {
            self == .horizontal ? rect.minX...rect.maxX : rect.minY...rect.maxY
        }

        func cross(_ rect: CGRect) -> ClosedRange<CGFloat> {
            self == .horizontal ? rect.minY...rect.maxY : rect.minX...rect.maxX
        }

        func point(_ value: CGFloat, _ cross: CGFloat) -> CGPoint {
            self == .horizontal ? CGPoint(x: value, y: cross) : CGPoint(x: cross, y: value)
        }
    }

    private struct Candidate {
        let delta: CGFloat
        let reference: Reference

        enum Reference {
            case alignment(CGFloat, CGRect)
            case gaps((CGRect?, CGRect?), (CGRect?, CGRect?))
        }

        func guides(for frame: CGRect, on axis: Axis) -> [CanvasGuide] {
            switch reference {
            case let .alignment(value, peer):
                let union = axis.cross(frame.union(peer))
                return [CanvasGuide(start: axis.point(value, union.lowerBound - 8),
                                    end: axis.point(value, union.upperBound + 8))]
            case let .gaps(first, second):
                let pairs = [first, second].map { ($0.0 ?? frame, $0.1 ?? frame) }
                let cross = pairs.flatMap { [axis.cross($0.0).upperBound, axis.cross($0.1).upperBound] }.max() ?? 0
                return pairs.map { left, right in
                    let start = axis.limits(left).upperBound
                    let end = axis.limits(right).lowerBound
                    return CanvasGuide(start: axis.point(start, cross + 8), end: axis.point(end, cross + 8),
                                       distance: end - start)
                }
            }
        }
    }

    private static func best(
        _ axis: Axis, frame: CGRect, bounds: CGRect, peers: [CGRect], tolerance: CGFloat
    ) -> Candidate? {
        let moving = axis.limits(frame)
        let valid = axis.limits(bounds)
        let length = moving.upperBound - moving.lowerBound
        var best: Candidate?

        func offer(_ start: CGFloat, _ reference: Candidate.Reference) {
            let delta = start - moving.lowerBound
            guard abs(delta) <= tolerance, start >= valid.lowerBound,
                  start + length <= valid.upperBound,
                  best.map({ abs(delta) < abs($0.delta) }) ?? true else { return }
            best = Candidate(delta: delta, reference: reference)
        }

        let aligned = peers.filter {
            axis.cross($0).overlaps(axis.cross(frame).expanded(by: 96))
        }
        let cross = axis.cross(frame)
        let nearby = aligned.filter { axis.cross($0).overlaps(cross) }
        let before = nearby.filter { axis.limits($0).upperBound <= moving.lowerBound + tolerance }
            .sorted { axis.limits($0).upperBound > axis.limits($1).upperBound }
        let after = nearby.filter { axis.limits($0).lowerBound >= moving.upperBound - tolerance }
            .sorted { axis.limits($0).lowerBound < axis.limits($1).lowerBound }

        if let previous = before.first, let next = after.first {
            let end = axis.limits(previous).upperBound
            let free = axis.limits(next).lowerBound - end - length
            if free >= 0 { offer(end + free / 2, .gaps((previous, nil), (nil, next))) }
        }
        if before.count > 1 {
            let near = before[0]
            let far = before[1]
            let gap = axis.limits(near).lowerBound - axis.limits(far).upperBound
            if gap >= 0 {
                offer(axis.limits(near).upperBound + gap, .gaps((far, near), (near, nil)))
            }
        }
        if after.count > 1 {
            let near = after[0]
            let far = after[1]
            let gap = axis.limits(far).lowerBound - axis.limits(near).upperBound
            if gap >= 0 {
                offer(axis.limits(near).lowerBound - gap - length, .gaps((nil, near), (near, far)))
            }
        }

        for peer in aligned + [bounds] {
            let target = axis.limits(peer)
            let center = (target.lowerBound + target.upperBound) / 2
            offer(center - length / 2, .alignment(center, peer))
            for edge in [target.lowerBound, target.upperBound] {
                offer(edge, .alignment(edge, peer))
                offer(edge - length, .alignment(edge, peer))
            }
        }

        return best
    }
}

private extension ClosedRange<CGFloat> {
    func expanded(by amount: CGFloat) -> Self { (lowerBound - amount)...(upperBound + amount) }
}
