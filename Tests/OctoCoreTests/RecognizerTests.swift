import Foundation
import Testing
import OctoCore

/// Drives the recognizer with frames 8 ms apart, like a real trackpad (~125 Hz).
final class Sim {
    let recognizer: GestureRecognizer
    var time = 0.0
    var fingers: [Int32: (x: Double, y: Double)] = [:]
    var events: [RecognizerEvent] = []

    init(wantsDouble: Set<String> = [], tuning: Tuning = Tuning()) {
        recognizer = GestureRecognizer(tuning: tuning)
        recognizer.wantsDoubleTap = { resting, side in wantsDouble.contains("\(resting)\(side.rawValue)") }
    }

    func frame() {
        time += 0.008
        let touches = fingers.map { TouchPoint(id: $0.key, x: $0.value.x, y: $0.value.y) }
        events += recognizer.process(time: time, touches: touches)
    }

    func wait(_ seconds: Double) {
        for _ in 0..<max(1, Int((seconds / 0.008).rounded())) { frame() }
    }

    func down(_ id: Int32, _ x: Double, _ y: Double) {
        fingers[id] = (x, y)
        frame()
    }

    func up(_ ids: Int32...) {
        for id in ids { fingers[id] = nil }
        frame()
    }

    func tap(_ id: Int32, _ x: Double, _ y: Double, hold: Double = 0.08) {
        down(id, x, y)
        wait(hold)
        up(id)
    }

    var gestures: [GestureKind] {
        events.compactMap { event in
            switch event {
            case let .gesture(g): return g
            case .tapAccepted, .tapIgnored: return nil
            }
        }
    }
}

@Suite("Tab-switching taps (1 resting finger)")
struct OneFixTapTests {
    @Test func tapRightOfRestingFinger() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42)
        s.wait(0.05)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func tapLeftOfRestingFinger() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 42, 38)
        #expect(s.gestures == [.fixTap(resting: 1, side: .left, taps: 1)])
    }

    @Test func bouncyTapCountsOnce() {
        // The tapping finger lifts and touches again within ~20 ms: one tap, one tab.
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42, hold: 0.07)
        s.frame()
        s.tap(3, 80.5, 42, hold: 0.03)
        s.wait(0.1)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func fastDeliberateTapsStillCount() {
        // Two quick taps with a normal ~120 ms gap are two taps.
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42, hold: 0.07)
        s.wait(0.12)
        s.tap(3, 80, 42, hold: 0.07)
        #expect(s.gestures == Array(repeating: .fixTap(resting: 1, side: .right, taps: 1), count: 2))
    }

    @Test func repeatedTapsFireEachTime() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42)
        s.wait(0.06)
        s.tap(3, 81, 41)
        s.wait(0.06)
        s.tap(4, 80, 43)
        #expect(s.gestures == Array(repeating: .fixTap(resting: 1, side: .right, taps: 1), count: 3))
    }

    @Test func twoFingersLandingTogetherIsNotATap() {
        let s = Sim()
        s.fingers = [1: (60, 40), 2: (80, 42)]
        s.frame()
        s.wait(0.08)
        s.up(1, 2)
        s.wait(0.1)
        #expect(s.gestures.isEmpty)
    }

    @Test func secondFingerTooSoonIsNotATap() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.03)
        s.tap(2, 80, 42)
        #expect(s.gestures.isEmpty)
    }

    @Test func slowPressIsNotATap() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42, hold: 0.4)
        #expect(s.gestures.isEmpty)
    }

    @Test func movingRestingFingerCancels() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        for _ in 0..<8 { s.fingers[1]!.x += 1; s.frame() }
        s.up(2)
        #expect(s.gestures.isEmpty)
    }

    @Test func twoFingerScrollIsNotATap() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        for _ in 0..<10 {
            s.fingers[1]!.y += 1.2
            s.fingers[2]!.y += 1.2
            s.frame()
        }
        s.up(2)
        s.up(1)
        #expect(s.gestures.isEmpty)
    }

    @Test func slidingTapFingerCancels() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        for _ in 0..<6 { s.fingers[2]!.x += 1; s.frame() }
        s.up(2)
        #expect(s.gestures.isEmpty)
    }

    @Test func tapFarAboveIsIgnored() {
        // Thumb resting at the bottom, index tapping higher up: not sideways enough.
        let s = Sim()
        s.down(1, 40, 10)
        s.wait(0.3)
        s.tap(2, 55, 50)
        #expect(s.gestures.isEmpty)
    }

    @Test func extraFingerJoiningCancels() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        s.down(3, 95, 42)
        s.wait(0.05)
        s.up(2)
        s.up(3)
        #expect(s.gestures.isEmpty)
    }

    @Test func liftingBothTogetherIsNotATap() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        s.wait(0.08)
        s.up(1, 2)
        #expect(s.gestures.isEmpty)
    }

    @Test func physicalClickDuringTapCancels() {
        // Pressing the trackpad with the second finger is a click, not a tap.
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        s.wait(0.03)
        s.recognizer.noteMouseDown(time: s.time)
        s.wait(0.08)
        s.up(2)
        #expect(s.gestures.isEmpty)
    }

    @Test func tapToClickRightBeforeLiftStillCounts() {
        // macOS's Tap to click fires as the finger lifts; that must not cancel the gesture.
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.down(2, 80, 42)
        s.wait(0.08)
        s.recognizer.noteMouseDown(time: s.time)
        s.up(2)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func reportsAcceptedTaps() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42)
        #expect(s.events.contains(.tapAccepted(resting: 1, side: .right)))
    }
}

@Suite("Hard-reload double-tap (2 resting fingers)")
struct TwoFixTests {
    func restTwo(_ s: Sim) {
        s.down(1, 60, 40)
        s.down(2, 78, 43)
        s.wait(0.2)
    }

    @Test func doubleTapLeftOfTwoRestingFingers() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        s.wait(0.1)
        s.tap(4, 41, 39)
        s.wait(0.5)
        #expect(s.gestures == [.fixTap(resting: 2, side: .left, taps: 2)])
    }

    @Test func singleTapIsReportedAfterTheWindow() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        s.wait(0.1)
        #expect(s.gestures.isEmpty) // still waiting for a possible second tap
        s.wait(0.4)
        #expect(s.gestures == [.fixTap(resting: 2, side: .left, taps: 1)])
    }

    @Test func tickFlushesWhenFramesStop() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        let events = s.recognizer.tick(time: s.time + 0.5)
        #expect(events == [.gesture(.fixTap(resting: 2, side: .left, taps: 1))])
    }

    @Test func liftingRestingFingersFlushesTheSingleTap() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        s.up(1, 2)
        #expect(s.gestures == [.fixTap(resting: 2, side: .left, taps: 1)])
    }

    @Test func secondTapTooLateIsTwoSingles() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        s.wait(0.5)
        s.tap(4, 40, 38)
        s.wait(0.5)
        #expect(s.gestures == Array(repeating: .fixTap(resting: 2, side: .left, taps: 1), count: 2))
    }

    @Test func secondTapFarAwayIsNotADoubleTap() {
        let s = Sim(wantsDouble: ["2left"])
        restTwo(s)
        s.tap(3, 40, 38)
        s.wait(0.1)
        s.tap(4, 15, 40)
        s.wait(0.5)
        #expect(!s.gestures.contains(.fixTap(resting: 2, side: .left, taps: 2)))
    }

    @Test func tapBetweenRestingFingersIsIgnored() {
        let s = Sim()
        s.down(1, 50, 40)
        s.down(2, 80, 40)
        s.wait(0.2)
        s.tap(3, 65, 40)
        #expect(s.gestures.isEmpty)
    }

    @Test func singleTapFiresImmediatelyWithoutDoubleSetUp() {
        let s = Sim()
        restTwo(s)
        s.tap(3, 40, 38)
        #expect(s.gestures == [.fixTap(resting: 2, side: .left, taps: 1)])
    }

    @Test func threeFingersLandingTogetherIsNothing() {
        // Like a 3-finger click: all fingers land at about the same time.
        let s = Sim(wantsDouble: ["2left"])
        s.fingers = [1: (40, 38), 2: (60, 40), 3: (78, 43)]
        s.frame()
        s.wait(0.02)
        s.recognizer.noteMouseDown(time: s.time) // pressing down: a click
        s.wait(0.12)
        s.up(1, 2, 3)
        s.wait(0.5)
        #expect(s.gestures.isEmpty)
    }
}

@Suite("Accidental taps while typing")
struct AccidentalTapTests {
    func ignoredReasons(_ s: Sim) -> [IgnoreReason] {
        s.events.compactMap { event in
            if case let .tapIgnored(_, _, reason) = event { return reason }
            return nil
        }
    }

    @Test func palmOnTheEdgeIsIgnored() {
        // Left palm resting on the left edge, a right-hand finger touches the middle: nothing.
        let s = Sim()
        s.recognizer.trackpadWidth = 125
        s.recognizer.trackpadHeight = 77
        s.down(1, 8, 30)
        s.wait(0.4)
        s.tap(2, 30, 32)
        #expect(s.gestures.isEmpty)
        #expect(s.recognizer.touchCount == 0) // the palm doesn't count as a finger
        #expect(s.recognizer.ignoredIDs == [1])
    }

    @Test func gestureStillWorksWithAPalmOnTheEdge() {
        let s = Sim()
        s.recognizer.trackpadWidth = 125
        s.recognizer.trackpadHeight = 77
        s.down(9, 4, 40) // palm in the edge zone
        s.down(1, 60, 40)
        s.wait(0.2)
        s.tap(2, 80, 42)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func fingertipNearTheEdgeCountsForAClick() {
        // Three fingers press together, one of them low on the trackpad (in the edge zone).
        let s = Sim()
        s.recognizer.trackpadWidth = 125
        s.recognizer.trackpadHeight = 77
        s.fingers = [1: (50, 40), 2: (65, 40), 3: (80, 8)]
        s.frame()
        s.wait(0.05)
        #expect(s.recognizer.touchCount == 2) // taps and rests leave the edge finger out
        #expect(s.recognizer.fingerCountForClick(now: s.time) == 3) // a click counts it
    }

    @Test func restingPalmDoesNotCountForAClick() {
        let s = Sim()
        s.recognizer.trackpadWidth = 125
        s.recognizer.trackpadHeight = 77
        s.down(9, 4, 40) // palm on the edge for a while
        s.wait(1.0)
        s.fingers[1] = (50, 40)
        s.fingers[2] = (65, 40)
        s.fingers[3] = (80, 40)
        s.frame()
        s.wait(0.05)
        #expect(s.recognizer.fingerCountForClick(now: s.time) == 3)
    }

    @Test func fingerSlidingIntoTheEdgeKeepsCounting() {
        let s = Sim()
        s.recognizer.trackpadWidth = 125
        s.recognizer.trackpadHeight = 77
        s.down(1, 30, 40)
        s.fingers[1]!.x = 15 // moved into the edge zone after starting in the middle
        s.wait(0.2)
        s.tap(2, 34, 41)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func tapRightAfterTypingIsIgnored() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.3)
        s.recognizer.noteKeyPress(time: s.time)
        s.wait(0.2)
        s.tap(2, 80, 42)
        #expect(s.gestures.isEmpty)
        #expect(ignoredReasons(s) == [.typing])
    }

    @Test func tapAfterTypingPauseWorks() {
        let s = Sim()
        s.down(1, 60, 40)
        s.recognizer.noteKeyPress(time: s.time)
        s.wait(0.7)
        s.tap(2, 80, 42)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func keyPressDuringTheTapCancelsIt() {
        let s = Sim()
        s.down(1, 60, 40)
        s.wait(0.8)
        s.down(2, 80, 42)
        s.wait(0.04)
        s.recognizer.noteKeyPress(time: s.time)
        s.wait(0.04)
        s.up(2)
        #expect(s.gestures.isEmpty)
    }

    @Test func typingGuardCanBeTurnedOff() {
        var tuning = Tuning()
        tuning.typingGuard = 0
        let s = Sim(tuning: tuning)
        s.down(1, 60, 40)
        s.wait(0.3)
        s.recognizer.noteKeyPress(time: s.time)
        s.wait(0.1)
        s.tap(2, 80, 42)
        #expect(s.gestures == [.fixTap(resting: 1, side: .right, taps: 1)])
    }

    @Test func fingersFromTwoHandsAreTooFarApart() {
        // Left hand resting on the left, right hand touching far to the right.
        let s = Sim()
        s.down(1, 25, 40)
        s.wait(0.3)
        s.tap(2, 95, 42)
        #expect(s.gestures.isEmpty)
        #expect(ignoredReasons(s) == [.tooFar])
    }
}

@Suite("Multi-finger taps")
struct MultiFingerTapTests {
    let row: [(Int32, Double, Double)] = [(1, 40, 38), (2, 55, 42), (3, 70, 43), (4, 85, 40)]

    func land(_ s: Sim, _ count: Int, staggered: Bool = false) {
        for (id, x, y) in row.prefix(count) {
            s.fingers[id] = (x, y)
            if staggered { s.frame() }
        }
        if !staggered { s.frame() }
    }

    func liftAll(_ s: Sim) {
        s.fingers.removeAll()
        s.frame()
    }

    @Test func fourFingerTap() {
        let s = Sim()
        land(s, 4)
        s.wait(0.1)
        liftAll(s)
        #expect(s.gestures == [.fingerTap(fingers: 4)])
    }

    @Test func fingersLandingAFewMillisecondsApartStillCount() {
        let s = Sim()
        land(s, 4, staggered: true)
        s.wait(0.1)
        liftAll(s)
        #expect(s.gestures == [.fingerTap(fingers: 4)])
    }

    @Test func threeFingerTap() {
        let s = Sim()
        land(s, 3)
        s.wait(0.08)
        liftAll(s)
        #expect(s.gestures == [.fingerTap(fingers: 3)])
    }

    @Test func holdingIsNotATap() {
        let s = Sim()
        land(s, 4)
        s.wait(0.6)
        liftAll(s)
        #expect(s.gestures.isEmpty)
    }

    @Test func swipeIsNotATap() {
        let s = Sim()
        land(s, 4)
        for _ in 0..<8 {
            for id in s.fingers.keys { s.fingers[id]!.y += 1.5 }
            s.frame()
        }
        liftAll(s)
        #expect(s.gestures.isEmpty)
    }

    @Test func pressingDownIsAClickNotATap() {
        let s = Sim()
        land(s, 4)
        s.wait(0.03)
        s.recognizer.noteMouseDown(time: s.time)
        s.wait(0.12)
        liftAll(s)
        #expect(s.gestures.isEmpty)
    }

    @Test func lateFingerIsNotATap() {
        let s = Sim()
        land(s, 3)
        s.wait(0.2)
        s.fingers[4] = (85, 40)
        s.frame()
        s.wait(0.03)
        liftAll(s)
        #expect(s.gestures.isEmpty)
    }

    @Test func tapRightAfterTypingIsIgnored() {
        let s = Sim()
        s.recognizer.noteKeyPress(time: s.time)
        s.wait(0.2)
        land(s, 4)
        s.wait(0.1)
        liftAll(s)
        #expect(s.gestures.isEmpty)
    }
}
