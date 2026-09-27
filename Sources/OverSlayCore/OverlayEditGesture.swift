import Foundation

/// One edit transaction. Every preview derives from mouse-down geometry, never from a snapped preview.
public struct OverlayEditGesture {
    public let activeID: String
    public let originals: [String: OverlayRect]
    public let mode: OverlayResizeEdges?
    public let options: OverlaySnapOptions
    public private(set) var preview: [String: OverlayRect]
    public private(set) var changed = false
    public private(set) var ended = false
    private var snapSession = OverlaySnapSession()
    private var screenID: String?
    public var snappedEdges: OverlayResizeEdges { snapSession.snappedEdges }

    public init(activeID: String, originals: [String: OverlayRect], mode: OverlayResizeEdges?, options: OverlaySnapOptions) {
        self.activeID = activeID; self.originals = originals; self.mode = mode; self.options = options
        preview = originals
    }

    public mutating func update(raw: OverlayRect, screenID: String, screen: OverlayRect,
                                targets: [OverlaySnapTarget]) -> [String: OverlayRect] {
        guard !ended, let start = originals[activeID] else { return preview }
        if !changed && raw == start { return preview }
        changed = true
        if self.screenID != screenID { snapSession.reset(); self.screenID = screenID }
        if let mode {
            preview[activeID] = snapSession.snap(raw, mode: mode, gridOrigin: (screen.x, screen.y), targets: targets, options: options)
        } else {
            let translated = originals.mapValues { $0.translated(x: raw.x - start.x, y: raw.y - start.y) }
            let bounds = translated.values.reduce(raw) { $0.union($1) }
            let snapped = snapSession.snap(bounds, gridOrigin: (screen.x, screen.y), targets: targets, options: options)
            preview = translated.mapValues { $0.translated(x: snapped.x - bounds.x, y: snapped.y - bounds.y) }
        }
        return preview
    }

    public mutating func finish() -> [String: OverlayRect] {
        ended = true; snapSession.reset(); return preview
    }

    public mutating func cancel() -> [String: OverlayRect] {
        ended = true; snapSession.reset(); preview = originals; return originals
    }
}
