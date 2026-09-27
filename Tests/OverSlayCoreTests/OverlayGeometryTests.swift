import XCTest
@testable import OverSlayCore

final class OverlayGeometryTests: XCTestCase {
    private let screen = OverlayRect(x: 0, y: 0, width: 800, height: 600)
    private func rect(_ x: Double, _ y: Double, _ w: Double = 80, _ h: Double = 60) -> OverlayRect {
        OverlayRect(x: x, y: y, width: w, height: h)
    }

    func testAllEightHandlesKeepOppositeEdgesAndOnlyChangeActiveDimensions() {
        let start = rect(100, 100, 120, 100)
        let expected: [OverlayResizeHandle: OverlayRect] = [
            .top: rect(100, 100, 120, 115), .bottom: rect(100, 115, 120, 85),
            .left: rect(110, 100, 110, 100), .right: rect(100, 100, 130, 100),
            .topLeft: rect(110, 100, 110, 115), .topRight: rect(100, 100, 130, 115),
            .bottomLeft: rect(110, 115, 110, 85), .bottomRight: rect(100, 115, 130, 85)
        ]
        for handle in OverlayResizeHandle.allCases {
            XCTAssertEqual(handle.resized(start, dx: 10, dy: 15), expected[handle], "\(handle)")
        }
    }

    func testSquareCornersShrinkAndKeepOppositeCorner() {
        let start = rect(100, 100, 120, 120)
        XCTAssertEqual(OverlayResizeHandle.bottomRight.resized(start, dx: -20, dy: 10, square: true), rect(100, 120, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.topLeft.resized(start, dx: 20, dy: -10, square: true), rect(120, 100, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.bottomLeft.resized(start, dx: 20, dy: 10, square: true), rect(120, 120, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.topRight.resized(start, dx: -20, dy: -10, square: true), rect(100, 100, 100, 100))
    }

    func testSquareEdgeHandlesKeepTransverseCenter() {
        let start = rect(100, 100, 120, 120)
        XCTAssertEqual(OverlayResizeHandle.right.resized(start, dx: -20, dy: 400, square: true), rect(100, 110, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.left.resized(start, dx: 20, dy: 400, square: true), rect(120, 110, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.top.resized(start, dx: 400, dy: -20, square: true), rect(110, 100, 100, 100))
        XCTAssertEqual(OverlayResizeHandle.bottom.resized(start, dx: 400, dy: 20, square: true), rect(110, 120, 100, 100))
    }

    func testSquareCornerDominantDeltaAndHorizontalTie() {
        let start = rect(100, 100, 120, 120)
        XCTAssertEqual(OverlayResizeHandle.topRight.resized(start, dx: -10, dy: 20, square: true).width, 140)
        XCTAssertEqual(OverlayResizeHandle.topRight.resized(start, dx: -20, dy: 20, square: true).width, 100)
    }

    func testResizeLimitsKeepAnchors() {
        XCTAssertEqual(OverlayResizeHandle.bottomLeft.resized(rect(100, 100), dx: 500, dy: 500), rect(148, 128, 32, 32))
        XCTAssertEqual(OverlayResizeHandle.left.resized(rect(100, 100, 120, 120), dx: 500, dy: 0, square: true), rect(156, 128, 64, 64))
        XCTAssertEqual(OverlayResizeHandle.right.resized(rect(100, 100), dx: 5000, dy: 0).width, 1000)
    }

    func testGridUsesScreenOriginAndRoundsNegativeMidpointTowardPositive() {
        var session = OverlaySnapSession()
        let result = session.snap(rect(-1004, -504), gridOrigin: (-1000, -500), targets: [], options: .init(grid: true, edges: false))
        XCTAssertEqual(result, rect(-1000, -500))
    }

    func testFourPreferenceCombinationsAndEdgeOverridesGrid() {
        let target = OverlaySnapTarget(id: "peer", rect: rect(102, 100, 200, 200))
        for grid in [false, true] {
            for edges in [false, true] {
                var session = OverlaySnapSession()
                let result = session.snap(rect(99, 151), gridOrigin: (0, 0), targets: [target], options: .init(grid: grid, edges: edges))
                XCTAssertEqual(result.x, edges ? 102 : grid ? 96 : 99)
                XCTAssertEqual(result.y, grid ? 152 : 151)
            }
        }
    }

    func testHysteresisIncludesEntryAndExitBoundariesAndReleasesBeyondExit() {
        var session = OverlaySnapSession()
        let targets = [OverlaySnapTarget(id: "screen", rect: screen)]
        let options = OverlaySnapOptions(grid: false, edges: true)
        XCTAssertEqual(session.snap(rect(6, 100), gridOrigin: (0, 0), targets: targets, options: options).x, 0)
        XCTAssertEqual(session.snap(rect(10, 100), gridOrigin: (0, 0), targets: targets, options: options).x, 0)
        XCTAssertEqual(session.snap(rect(11, 100), gridOrigin: (0, 0), targets: targets, options: options).x, 11)
        XCTAssertEqual(session.snap(rect(7, 100), gridOrigin: (0, 0), targets: targets, options: options).x, 7)
    }

    func testCurrentTargetWinsUntilExitAndResetDropsLatch() {
        var session = OverlaySnapSession()
        let targets = [OverlaySnapTarget(id: "screen", rect: screen), OverlaySnapTarget(id: "peer", rect: rect(10, 100, 300, 200))]
        let options = OverlaySnapOptions(grid: false, edges: true)
        XCTAssertEqual(session.snap(rect(1, 150), gridOrigin: (0, 0), targets: targets, options: options).x, 0)
        XCTAssertEqual(session.snap(rect(9, 150), gridOrigin: (0, 0), targets: targets, options: options).x, 0)
        session.reset()
        XCTAssertEqual(session.snap(rect(9, 150), gridOrigin: (0, 0), targets: targets, options: options).x, 10)
    }

    func testScreenWinsEqualDistanceAndStablePeerIDWinsIndependentOfOrder() {
        let a = OverlaySnapTarget(id: "a", rect: rect(100, 100, 200, 200))
        let b = OverlaySnapTarget(id: "b", rect: rect(104, 100, 200, 200))
        for targets in [[a, b], [b, a]] {
            var session = OverlaySnapSession()
            XCTAssertEqual(session.snap(rect(102, 150), gridOrigin: (0, 0), targets: targets, options: .init(grid: false, edges: true)).x, 100)
        }
        var session = OverlaySnapSession()
        XCTAssertEqual(session.snap(rect(3, 100), gridOrigin: (0, 0), targets: [OverlaySnapTarget(id: "a", rect: rect(6, 100, 300, 300)), OverlaySnapTarget(id: "screen", rect: screen)], options: .init(grid: false, edges: true)).x, 0)
    }

    func testDistantPeersIgnoredBut24PointGapAccepted() {
        let target = OverlaySnapTarget(id: "peer", rect: rect(100, 100, 200, 100))
        for gap in [24.0, 25.0] {
            var session = OverlaySnapSession()
            XCTAssertEqual(session.snap(rect(103, 200 + gap), gridOrigin: (0, 0), targets: [target], options: .init(grid: false, edges: true)).x, gap == 24 ? 100 : 103)
        }
    }

    func testInvalidResizeCandidateDoesNotLatchOrBlockValidCandidate() {
        var session = OverlaySnapSession()
        let raw = rect(100, 100, 33, 60)
        let targets = [OverlaySnapTarget(id: "invalid", rect: rect(131, 100, 200, 200)), OverlaySnapTarget(id: "valid", rect: rect(136, 100, 200, 200))]
        XCTAssertEqual(session.snap(raw, mode: .init(right: true), gridOrigin: (0, 0), targets: targets, options: .init(grid: false, edges: true)).width, 36)
    }

    func testSquareSnapCanShrinkAndKeepsCenterForSideHandle() {
        var session = OverlaySnapSession()
        let result = session.snap(rect(100, 100, 100, 100), mode: .init(right: true, square: true), gridOrigin: (0, 0), targets: [OverlaySnapTarget(id: "peer", rect: rect(196, 100, 300, 300))], options: .init(grid: true, edges: true))
        XCTAssertEqual(result, rect(100, 102, 96, 96))
    }

    func testSquareIncompatibleAxisTargetsChooseCloserThenHorizontalTie() {
        for y in [202.0, 204.0] {
            var session = OverlaySnapSession()
            let targets = [OverlaySnapTarget(id: "x", rect: rect(196, 110, 300, 300)), OverlaySnapTarget(id: "y", rect: rect(110, y, 300, 300))]
            let result = session.snap(rect(100, 100, 100, 100), mode: .init(right: true, top: true, square: true), gridOrigin: (0, 0), targets: targets, options: .init(grid: false, edges: true))
            XCTAssertEqual(result.width, y == 202 ? 102 : 96)
            XCTAssertEqual(result.height, result.width)
        }
    }

    func testGroupDragIndependentOfGrabbedMemberAndPreviewHistory() {
        let originals = ["a": rect(101, 100), "b": rect(250, 100)]
        for id in ["a", "b"] {
            var gesture = OverlayEditGesture(activeID: id, originals: originals, mode: nil, options: .init(grid: true, edges: false))
            _ = gesture.update(raw: originals[id]!.translated(x: 5, y: 0), screenID: "1", screen: screen, targets: [])
            let result = gesture.update(raw: originals[id]!.translated(x: 11, y: 0), screenID: "1", screen: screen, targets: [])
            XCTAssertEqual(result["a"], rect(112, 104))
            XCTAssertEqual(result["b"], rect(261, 104))
            XCTAssertEqual(gesture.finish(), result)
        }
    }

    func testClickNeverSnapsAndCancelRejectsLateUpdates() {
        let originals = ["a": rect(101, 101)]
        var click = OverlayEditGesture(activeID: "a", originals: originals, mode: nil, options: .init(grid: true, edges: true))
        XCTAssertEqual(click.update(raw: originals["a"]!, screenID: "1", screen: screen, targets: []), originals)
        XCTAssertFalse(click.changed)
        XCTAssertEqual(click.finish(), originals)
        var drag = OverlayEditGesture(activeID: "a", originals: originals, mode: nil, options: .init(grid: true, edges: true))
        _ = drag.update(raw: rect(111, 112), screenID: "1", screen: screen, targets: [])
        XCTAssertEqual(drag.cancel(), originals)
        XCTAssertEqual(drag.update(raw: rect(120, 130), screenID: "1", screen: screen, targets: []), originals)
        XCTAssertEqual(drag.finish(), originals)
    }

    func testScreenSwitchResetsEdgeLatch() {
        var gesture = OverlayEditGesture(activeID: "a", originals: ["a": rect(100, 100)], mode: nil, options: .init(grid: false, edges: true))
        let targets = [OverlaySnapTarget(id: "peer", rect: rect(0, 100, 400, 400))]
        XCTAssertEqual(gesture.update(raw: rect(2, 100), screenID: "1", screen: screen, targets: targets)["a"]?.x, 0)
        XCTAssertEqual(gesture.update(raw: rect(9, 100), screenID: "2", screen: screen, targets: targets)["a"]?.x, 9)
    }

    func testLegacyPreferencesDefaultOnAndExplicitOffSurvivesRoundTrip() throws {
        let id = UUID()
        let old: [String: String] = ["defaultProfileID": id.uuidString, "selectedProfileID": id.uuidString, "lastManualProfileID": id.uuidString]
        var decoded = try JSONDecoder().decode(ProfilePreferences.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.snapToGrid); XCTAssertTrue(decoded.snapToEdges)
        decoded.snapToGrid = false; decoded.snapToEdges = false
        let restored = try JSONDecoder().decode(ProfilePreferences.self, from: JSONEncoder().encode(decoded))
        XCTAssertFalse(restored.snapToGrid); XCTAssertFalse(restored.snapToEdges)
        XCTAssertEqual(restored.selectedProfileID, id)
    }
}
