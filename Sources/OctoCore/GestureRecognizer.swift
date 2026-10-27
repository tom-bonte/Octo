import Foundation

/// One finger on the trackpad in a single frame. Positions are in millimetres,
/// measured from the trackpad's left and bottom edges.
public struct TouchPoint: Equatable, Sendable {
    public var id: Int32
    public var x: Double
    public var y: Double

    public init(id: Int32, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum IgnoreReason: Equatable, Sendable {
    /// A key was pressed just before or during the tap.
    case typing
    /// The fingers were too far apart to be one hand.
    case tooFar
}

public enum RecognizerEvent: Equatable, Sendable {
    /// A tap beside resting fingers was accepted. It may still turn into a double-tap.
    case tapAccepted(resting: Int, side: Side)
    case gesture(GestureKind)
    /// A tap that would have counted, dropped as probably accidental.
    case tapIgnored(resting: Int, side: Side, reason: IgnoreReason)
}

/// Turns a stream of trackpad frames into "fix-tap" gestures: one or two fingers rest
/// while another finger taps (or double-taps) to their left or right.
///
/// It is a plain state machine with no clocks or threads of its own: feed it frames with
/// `process`, call `tick` now and then while a single tap waits to see if a second one
/// follows, and call `noteMouseDown` when a physical click happens. That keeps it testable.
public final class GestureRecognizer {
    public var tuning: Tuning
    /// Asked when a single tap arrives: should we wait to see if a second tap follows?
    /// Only wait when a double-tap is actually set up, so single taps stay instant.
    public var wantsDoubleTap: (Int, Side) -> Bool = { _, _ in false }

    /// "Tap to click" fires its click as the finger lifts. A finger that is still down
    /// this long after a click pressed the trackpad, so it was a click, not a tap.
    public static let clickGrace = 0.035
    public static let maxResting = 2

    private struct Point {
        var x: Double
        var y: Double
        func distance(to other: Point) -> Double { hypot(x - other.x, y - other.y) }
    }

    private struct Contact {
        let start: Double
        let startPos: Point
        var pos: Point
        var travel: Double
    }

    private struct Candidate {
        let start: Double
        /// Resting fingers and where they were when this tap began.
        let anchors: [Int32: Point]
        var clickedAt: Double?
        var valid = true
    }

    private struct Tap {
        let resting: Set<Int32>
        let side: Side
        let pos: Point
        let start: Double
        let end: Double
    }

    private enum Outcome {
        case tap(Tap)
        case ignored(resting: Int, side: Side, reason: IgnoreReason)
    }

    /// Fingers that touched down together, for multi-finger taps.
    private struct TapGroup {
        let start: Double
        var ids: Set<Int32>
        var maxCount: Int
        var valid = true
        var clickedAt: Double?
    }

    /// All fingers of a multi-finger tap must land within this time of the first one.
    public static let groupLandWindow = 0.15
    private var group: TapGroup?

    /// A finger that lifts and touches down again this quickly, in the same spot, is one
    /// bouncy tap, not two. Nobody taps twice that fast on purpose.
    public static let bounceWindow = 0.06
    private var lastTap: (end: Double, pos: Point)?

    /// Trackpad size in millimetres, for the edge zones. 0 = unknown (no edge zones).
    public var trackpadWidth = 0.0
    public var trackpadHeight = 0.0

    private var contacts: [Int32: Contact] = [:]
    private var candidates: [Int32: Candidate] = [:]
    private var pending: Tap?
    /// Touches that started in an edge zone; left out until they lift.
    private var ignored: Set<Int32> = []
    /// When each of those landed, so fingers pressing together still count for a click.
    private var ignoredSince: [Int32: Double] = [:]
    private var lastKeyPress = -1000.0

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    // MARK: State for other parts of the app

    public var touchCount: Int { contacts.count }

    /// Fingers taking part in a click: every finger gestures use, plus edge-zone fingers that
    /// landed just now (a fingertip near the edge in a 3-finger press). A palm or thumb that has
    /// rested on the edge for a while doesn't count.
    public func fingerCountForClick(now: Double) -> Int {
        contacts.count + ignoredSince.values.filter { now - $0 < 0.5 }.count
    }
    public var hasPendingTap: Bool { pending != nil }
    /// Touches being ignored because they started near an edge.
    public var ignoredIDs: Set<Int32> { ignored }

    public var restingIDs: Set<Int32> {
        var ids = Set(candidates.values.filter(\.valid).flatMap { $0.anchors.keys })
        if let pending { ids.formUnion(pending.resting) }
        return ids
    }

    public var tappingIDs: Set<Int32> {
        Set(candidates.filter { $0.value.valid }.map(\.key))
    }

    /// For each tap in progress, how many fingers are resting beside it.
    public var activeCandidateRestingCounts: [Int] {
        candidates.values.filter(\.valid).map { $0.anchors.count }
    }

    public func reset() {
        contacts.removeAll()
        candidates.removeAll()
        pending = nil
        ignored.removeAll()
        ignoredSince.removeAll()
        group = nil
    }

    // MARK: Input

    public func noteKeyPress(time: Double) {
        lastKeyPress = time
    }

    public func noteMouseDown(time: Double) {
        for (id, var candidate) in candidates where candidate.valid && candidate.clickedAt == nil {
            candidate.clickedAt = time
            candidates[id] = candidate
        }
        if group != nil && group?.clickedAt == nil {
            group?.clickedAt = time
        }
    }

    public func process(time: Double, touches allTouches: [TouchPoint]) -> [RecognizerEvent] {
        var events: [RecognizerEvent] = []

        // Touches that start near an edge (palms, thumbs) are left out until they lift.
        ignored.formIntersection(allTouches.map(\.id))
        ignoredSince = ignoredSince.filter { ignored.contains($0.key) }
        var touches: [TouchPoint] = []
        for t in allTouches {
            if ignored.contains(t.id) { continue }
            if contacts[t.id] == nil && startsInEdgeZone(t) {
                ignored.insert(t.id)
                ignoredSince[t.id] = time
                continue
            }
            touches.append(t)
        }
        let ids = Set(touches.map(\.id))

        // Track movement of fingers we already know.
        for t in touches {
            guard var contact = contacts[t.id] else { continue }
            contact.pos = Point(x: t.x, y: t.y)
            contact.travel = max(contact.travel, contact.pos.distance(to: contact.startPos))
            contacts[t.id] = contact
        }

        // Register fingers that just landed.
        let landed = touches.filter { contacts[$0.id] == nil }
        for t in landed {
            let p = Point(x: t.x, y: t.y)
            contacts[t.id] = Contact(start: time, startPos: p, pos: p, travel: 0)
        }
        updateGroup(time: time, ids: ids, landed: landed.map(\.id))

        // Drop taps in progress that broke a rule this frame.
        for (id, candidate) in candidates where candidate.valid && ids.contains(id) {
            if !stillValid(candidate, id: id, time: time, ids: ids) {
                candidates[id]?.valid = false
            }
        }

        // Fingers that lifted: a lifted candidate may be a finished tap.
        let lifted = contacts.keys.filter { !ids.contains($0) }.sorted()
        for id in lifted {
            if let candidate = candidates.removeValue(forKey: id), let contact = contacts[id],
               let outcome = finishTap(candidate, contact: contact, time: time, ids: ids) {
                switch outcome {
                case let .tap(tap):
                    events += handle(tap)
                case let .ignored(resting, side, reason):
                    events.append(.tapIgnored(resting: resting, side: side, reason: reason))
                }
            }
            contacts.removeValue(forKey: id)
        }

        // A single new finger beside still fingers may be the start of a tap.
        if landed.count == 1, let t = landed.first {
            startCandidateIfResting(id: t.id, time: time)
        }

        // All fingers up: was it a multi-finger tap?
        if ids.isEmpty, let finished = group {
            group = nil
            if let gesture = finishGroup(finished, time: time) {
                events.append(.gesture(gesture))
            }
        }

        events += flushPending(time: time, ids: ids)
        return events
    }

    /// Call while `hasPendingTap` is true and no frames are arriving.
    public func tick(time: Double) -> [RecognizerEvent] {
        flushPending(time: time, ids: Set(contacts.keys))
    }

    // MARK: Rules

    private func updateGroup(time: Double, ids: Set<Int32>, landed: [Int32]) {
        guard !ids.isEmpty else { return }
        guard var g = group else {
            group = TapGroup(start: time, ids: ids, maxCount: ids.count)
            return
        }
        if !landed.isEmpty {
            // A finger arriving late means this isn't fingers tapping together.
            if time - g.start > Self.groupLandWindow { g.valid = false }
            g.ids.formUnion(landed)
        }
        g.maxCount = max(g.maxCount, ids.count)
        if time - g.start > tuning.tapMaxDuration + 0.1 { g.valid = false }
        if let clicked = g.clickedAt, time - clicked > Self.clickGrace { g.valid = false }
        for id in ids where (contacts[id]?.travel ?? 0) > tuning.tapMaxMovement * 1.5 {
            g.valid = false // a swipe, not a tap
        }
        group = g
    }

    private func finishGroup(_ g: TapGroup, time: Double) -> GestureKind? {
        guard g.valid, (3...4).contains(g.maxCount), g.ids.count == g.maxCount else { return nil }
        guard time - g.start <= tuning.tapMaxDuration + 0.12 else { return nil }
        if let clicked = g.clickedAt, time - clicked > Self.clickGrace { return nil }
        if tuning.typingGuard > 0 && lastKeyPress >= g.start - tuning.typingGuard { return nil }
        return .fingerTap(fingers: g.maxCount)
    }

    private func startsInEdgeZone(_ t: TouchPoint) -> Bool {
        let margin = tuning.edgeMargin
        guard margin > 0, trackpadWidth > 0, trackpadHeight > 0 else { return false }
        return t.x < trackpadWidth * margin || t.x > trackpadWidth * (1 - margin)
            || t.y < trackpadHeight * margin || t.y > trackpadHeight * (1 - margin)
    }

    private func startCandidateIfResting(id: Int32, time: Double) {
        let others = contacts.filter { $0.key != id }
        guard (1...Self.maxResting).contains(others.count) else { return }
        for (otherID, contact) in others {
            // Fingers that landed together (two-finger tap, scroll, 3-finger click) aren't resting.
            if time - contact.start < tuning.restMinDuration { return }
            // Two taps at once don't count.
            if candidates[otherID]?.valid == true { return }
        }
        candidates[id] = Candidate(start: time, anchors: others.mapValues(\.pos))
    }

    private func stillValid(_ candidate: Candidate, id: Int32, time: Double, ids: Set<Int32>) -> Bool {
        guard let contact = contacts[id] else { return false }
        if time - candidate.start > tuning.tapMaxDuration { return false }
        if contact.travel > tuning.tapMaxMovement { return false }
        if let clicked = candidate.clickedAt, time - clicked > Self.clickGrace { return false }
        if ids.count > candidate.anchors.count + 1 { return false }
        for (restID, anchor) in candidate.anchors {
            guard ids.contains(restID), let rest = contacts[restID] else { return false }
            if rest.pos.distance(to: anchor) > tuning.restMaxMovement { return false }
        }
        return true
    }

    private func finishTap(_ candidate: Candidate, contact: Contact, time: Double, ids: Set<Int32>) -> Outcome? {
        guard candidate.valid else { return nil }
        // Small allowance: the lift is only seen on the next frame.
        guard time - candidate.start <= tuning.tapMaxDuration + 0.02 else { return nil }
        if let clicked = candidate.clickedAt, time - clicked > Self.clickGrace { return nil }
        guard contact.travel <= tuning.tapMaxMovement else { return nil }

        var restPoints: [Point] = []
        for (restID, anchor) in candidate.anchors {
            // Resting fingers must stay down, or it was a multi-finger tap.
            guard ids.contains(restID), let rest = contacts[restID] else { return nil }
            guard rest.pos.distance(to: anchor) <= tuning.restMaxMovement else { return nil }
            restPoints.append(rest.pos)
        }
        guard let leftmost = restPoints.min(by: { $0.x < $1.x }),
              let rightmost = restPoints.max(by: { $0.x < $1.x }) else { return nil }

        let tapPos = contact.pos
        let side: Side
        let reference: Point
        if tapPos.x < leftmost.x {
            side = .left
            reference = leftmost
        } else if tapPos.x > rightmost.x {
            side = .right
            reference = rightmost
        } else {
            return nil // between resting fingers
        }

        let dx = abs(tapPos.x - reference.x)
        let dy = abs(tapPos.y - reference.y)
        guard dx >= 2 else { return nil }
        let angle = atan2(dy, dx) * 180 / .pi
        guard angle <= tuning.maxTapAngle else { return nil }

        // A bounce of the previous tap's finger, not a new tap.
        if let last = lastTap, candidate.start - last.end < Self.bounceWindow, tapPos.distance(to: last.pos) < 10 {
            return nil
        }

        // It looks like a real tap. Last checks against accidents while typing.
        let resting = candidate.anchors.count
        if tuning.typingGuard > 0 && lastKeyPress >= candidate.start - tuning.typingGuard {
            return .ignored(resting: resting, side: side, reason: .typing)
        }
        if tapPos.distance(to: reference) > tuning.maxTapDistance {
            return .ignored(resting: resting, side: side, reason: .tooFar)
        }

        return .tap(Tap(resting: Set(candidate.anchors.keys), side: side, pos: tapPos, start: candidate.start, end: time))
    }

    private func handle(_ tap: Tap) -> [RecognizerEvent] {
        var events: [RecognizerEvent] = []
        let resting = tap.resting.count
        lastTap = (end: tap.end, pos: tap.pos)

        if let first = pending, first.resting == tap.resting, first.side == tap.side,
           tap.start - first.end <= tuning.doubleTapInterval,
           first.pos.distance(to: tap.pos) <= tuning.doubleTapMaxDistance {
            pending = nil
            events.append(.tapAccepted(resting: resting, side: tap.side))
            events.append(.gesture(.fixTap(resting: resting, side: tap.side, taps: 2)))
            return events
        }

        if let earlier = pending {
            pending = nil
            events.append(.gesture(.fixTap(resting: earlier.resting.count, side: earlier.side, taps: 1)))
        }

        events.append(.tapAccepted(resting: resting, side: tap.side))
        if wantsDoubleTap(resting, tap.side) {
            pending = tap
        } else {
            events.append(.gesture(.fixTap(resting: resting, side: tap.side, taps: 1)))
        }
        return events
    }

    private func flushPending(time: Double, ids: Set<Int32>) -> [RecognizerEvent] {
        guard let first = pending else { return [] }
        let restingStillDown = first.resting.isSubset(of: ids)
        let secondTapUnderway = candidates.values.contains { $0.valid && Set($0.anchors.keys) == first.resting }
        if !restingStillDown || (time - first.end > tuning.doubleTapInterval && !secondTapUnderway) {
            pending = nil
            return [.gesture(.fixTap(resting: first.resting.count, side: first.side, taps: 1))]
        }
        return []
    }
}
