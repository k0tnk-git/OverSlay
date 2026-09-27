import Foundation

public struct OverlayRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func translated(x dx: Double, y dy: Double) -> Self {
        Self(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func union(_ other: Self) -> Self {
        Self(x: min(x, other.x), y: min(y, other.y),
             width: max(maxX, other.maxX) - min(x, other.x),
             height: max(maxY, other.maxY) - min(y, other.y))
    }
}

public struct OverlaySnapTarget: Sendable {
    public var id: String
    public var rect: OverlayRect
    public init(id: String, rect: OverlayRect) { self.id = id; self.rect = rect }
}

public struct OverlaySnapOptions: Sendable {
    public var grid: Bool
    public var edges: Bool
    public var gridStep: Double
    public var enterDistance: Double
    public var exitDistance: Double

    public init(grid: Bool, edges: Bool, gridStep: Double = 8, enterDistance: Double = 6, exitDistance: Double = 10) {
        self.grid = grid; self.edges = edges; self.gridStep = max(1, gridStep)
        self.enterDistance = max(0, enterDistance); self.exitDistance = max(enterDistance, exitDistance)
    }
}

public struct OverlayResizeEdges: Sendable {
    public var left, right, bottom, top: Bool
    public var square: Bool
    public init(left: Bool = false, right: Bool = false, bottom: Bool = false, top: Bool = false, square: Bool = false) {
        self.left = left; self.right = right; self.bottom = bottom; self.top = top; self.square = square
    }

    public func squareFrame(from raw: OverlayRect, side: Double) -> OverlayRect {
        OverlayRect(x: left ? raw.maxX - side : right ? raw.minX : (raw.minX + raw.maxX - side) / 2,
                    y: bottom ? raw.maxY - side : top ? raw.minY : (raw.minY + raw.maxY - side) / 2,
                    width: side, height: side)
    }
}

public enum OverlayResizeHandle: CaseIterable, Sendable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    public func edges(square: Bool = false) -> OverlayResizeEdges {
        OverlayResizeEdges(left: self == .left || self == .topLeft || self == .bottomLeft,
                           right: self == .right || self == .topRight || self == .bottomRight,
                           bottom: self == .bottom || self == .bottomLeft || self == .bottomRight,
                           top: self == .top || self == .topLeft || self == .topRight, square: square)
    }

    public func resized(_ original: OverlayRect, dx: Double, dy: Double, square: Bool = false) -> OverlayRect {
        let e = edges(square: square)
        let dw = e.left ? -dx : e.right ? dx : 0
        let dh = e.bottom ? -dy : e.top ? dy : 0
        if square {
            let delta = (e.left || e.right) && (!(e.top || e.bottom) || abs(dw) >= abs(dh)) ? dw : dh
            return e.squareFrame(from: original, side: min(1000, max(64, original.width + delta)))
        }
        let w = min(1000, max(32, original.width + dw))
        let h = min(1000, max(32, original.height + dh))
        return OverlayRect(x: e.left ? original.maxX - w : original.x,
                           y: e.bottom ? original.maxY - h : original.y, width: w, height: h)
    }
}

/// Holds edge targets for one pointer gesture, preventing jitter around snap boundaries.
public struct OverlaySnapSession {
    private struct Latch { var targetID: String; var movingEdge: String }
    private var xLatch: Latch?
    private var yLatch: Latch?
    public var snappedEdges: OverlayResizeEdges {
        OverlayResizeEdges(left: xLatch?.movingEdge == "min", right: xLatch?.movingEdge == "max",
                           bottom: yLatch?.movingEdge == "min", top: yLatch?.movingEdge == "max")
    }

    public init() {}

    public mutating func reset() { xLatch = nil; yLatch = nil }

    public mutating func snap(
        _ raw: OverlayRect,
        mode: OverlayResizeEdges? = nil,
        gridOrigin: (x: Double, y: Double),
        targets: [OverlaySnapTarget],
        options: OverlaySnapOptions
    ) -> OverlayRect {
        let isMove: Bool
        if case .none = mode { isMove = true } else { isMove = false }
        let moving = mode ?? OverlayResizeEdges(left: true, bottom: true)
        var result = raw

        if options.grid {
            let xEdge = isMove || moving.left ? raw.minX : moving.right ? raw.maxX : nil
            let yEdge = isMove || moving.bottom ? raw.minY : moving.top ? raw.maxY : nil
            if let xEdge {
                let snapped = gridOrigin.x + floor((xEdge - gridOrigin.x) / options.gridStep + 0.5) * options.gridStep
                if isMove { result.x = snapped }
                else if moving.left { result.x = snapped; result.width = raw.maxX - snapped }
                else { result.width = snapped - raw.minX }
            }
            if let yEdge {
                let snapped = gridOrigin.y + floor((yEdge - gridOrigin.y) / options.gridStep + 0.5) * options.gridStep
                if isMove { result.y = snapped }
                else if moving.bottom { result.y = snapped; result.height = raw.maxY - snapped }
                else { result.height = snapped - raw.minY }
            }
        }

        var squareSide = moving.left || moving.right ? result.width : result.height
        if options.edges {
            let xCandidates = candidates(axis: "x", raw: raw, mode: mode, targets: targets)
            let yCandidates = candidates(axis: "y", raw: raw, mode: mode, targets: targets)
            let (dx, newXLatch) = Self.selectedDelta(candidates: xCandidates, latch: xLatch, threshold: options)
            let (dy, newYLatch) = Self.selectedDelta(candidates: yCandidates, latch: yLatch, threshold: options)
            let squareMode = mode?.square ?? false
            let squareAxis: String?
            if squareMode, let dx, let dy {
                let heldX = xLatch != nil && newXLatch?.targetID == xLatch?.targetID && newXLatch?.movingEdge == xLatch?.movingEdge
                let heldY = yLatch != nil && newYLatch?.targetID == yLatch?.targetID && newYLatch?.movingEdge == yLatch?.movingEdge
                squareAxis = heldX || (!heldY && abs(dx) <= abs(dy)) ? "x" : "y"
            } else {
                squareAxis = nil
            }
            xLatch = squareAxis == "y" ? nil : newXLatch
            yLatch = squareAxis == "x" ? nil : newYLatch
            if let dx, squareAxis != "y" {
                if isMove { result.x = raw.x + dx }
                else if moving.left { result.x = raw.x + dx; result.width = raw.maxX - result.x }
                else if moving.right { result.width = raw.width + dx }
                squareSide = result.width
            }
            if let dy, squareAxis != "x" {
                if isMove { result.y = raw.y + dy }
                else if moving.bottom { result.y = raw.y + dy; result.height = raw.maxY - result.y }
                else if moving.top { result.height = raw.height + dy }
                squareSide = result.height
            }
            if squareMode {
                if squareAxis == "x" { result.height = result.width }
                else if squareAxis == "y" { result.width = result.height }
                else if dx != nil { result.height = result.width }
                else if dy != nil { result.width = result.height }
            }
        } else { reset() }

        if let mode, mode.square {
            return mode.squareFrame(from: raw, side: min(1000, max(64, squareSide)))
        } else if let mode {
            if mode.left || mode.right {
                result.width = min(1000, max(32, result.width))
                if mode.left { result.x = raw.maxX - result.width }
            }
            if mode.bottom || mode.top {
                result.height = min(1000, max(32, result.height))
                if mode.bottom { result.y = raw.maxY - result.height }
            }
        }
        return result
    }

    private struct Candidate { var id: String; var movingEdge: String; var delta: Double }

    private func candidates(axis: String, raw: OverlayRect, mode: OverlayResizeEdges?, targets: [OverlaySnapTarget]) -> [Candidate] {
        let horizontal = axis == "x"
        let active: [(String, Double)]
        if let mode {
            if horizontal {
                active = mode.left ? [("min", raw.minX)] : mode.right ? [("max", raw.maxX)] : []
            } else {
                active = mode.bottom ? [("min", raw.minY)] : mode.top ? [("max", raw.maxY)] : []
            }
        } else {
            active = horizontal ? [("min", raw.minX), ("max", raw.maxX)] : [("min", raw.minY), ("max", raw.maxY)]
        }
        var result: [Candidate] = []
        for (edge, value) in active {
            for target in targets {
                let transverseOverlap: Bool
                if horizontal {
                    transverseOverlap = min(raw.maxY, target.rect.maxY) >= max(raw.minY, target.rect.minY) - 24
                } else {
                    transverseOverlap = min(raw.maxX, target.rect.maxX) >= max(raw.minX, target.rect.minX) - 24
                }
                guard target.id == "screen" || transverseOverlap else { continue }
                let targetMin = horizontal ? target.rect.minX : target.rect.minY
                let targetMax = horizontal ? target.rect.maxX : target.rect.maxY
                let values: [(String, Double)]
                if target.id == "screen" {
                    values = edge == "min" ? [("min", targetMin)] : [("max", targetMax)]
                } else {
                    values = [("min", targetMin), ("max", targetMax)]
                }
                for (targetEdge, coordinate) in values {
                    if let mode {
                        let size = (horizontal ? raw.width : raw.height) + (edge == "min" ? value - coordinate : coordinate - value)
                        guard size >= (mode.square ? 64 : 32), size <= 1000 else { continue }
                    }
                    result.append(Candidate(id: target.id + ":" + targetEdge, movingEdge: edge, delta: coordinate - value))
                }
            }
        }
        return result
    }

    private static func selectedDelta(candidates: [Candidate], latch: Latch?, threshold: OverlaySnapOptions) -> (Double?, Latch?) {
        if let held = latch,
           let candidate = candidates.first(where: { $0.id == held.targetID && $0.movingEdge == held.movingEdge }),
           abs(candidate.delta) <= threshold.exitDistance { return (candidate.delta, held) }
        guard let candidate = candidates.filter({ abs($0.delta) <= threshold.enterDistance }).sorted(by: {
            let a = abs($0.delta), b = abs($1.delta)
            if a != b { return a < b }
            let aIsScreen = $0.id.hasPrefix("screen:")
            let bIsScreen = $1.id.hasPrefix("screen:")
            if aIsScreen != bIsScreen { return aIsScreen }
            return $0.id == $1.id ? $0.movingEdge < $1.movingEdge : $0.id < $1.id
        }).first else { return (nil, nil) }
        return (candidate.delta, Latch(targetID: candidate.id, movingEdge: candidate.movingEdge))
    }
}
