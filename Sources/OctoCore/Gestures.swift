import Foundation

public enum Side: String, Codable, CaseIterable, Hashable, Sendable {
    case left, right
}

/// Every gesture Octo knows. To add a new kind of gesture later: add a case here,
/// add it to `catalog`, teach `GestureRecognizer` (or `ClickGuard`) to detect it,
/// and draw it in `GestureDiagram`.
public enum GestureKind: Hashable, Codable, Sendable {
    /// Some fingers rest on the trackpad while another finger taps beside them.
    case fixTap(resting: Int, side: Side, taps: Int)
    /// Several fingers tap the trackpad together, without pressing it down.
    case fingerTap(fingers: Int)
    /// A physical click with several fingers on the trackpad.
    case fingerClick(fingers: Int)

    public static let catalog: [GestureKind] = {
        var all: [GestureKind] = []
        for resting in 1...2 {
            for taps in 1...2 {
                for side in Side.allCases {
                    all.append(.fixTap(resting: resting, side: side, taps: taps))
                }
            }
        }
        all.append(.fingerTap(fingers: 3))
        all.append(.fingerTap(fingers: 4))
        all.append(.fingerClick(fingers: 3))
        all.append(.fingerClick(fingers: 4))
        return all
    }()

    public var sortIndex: Int { Self.catalog.firstIndex(of: self) ?? Int.max }

    public var title: String {
        switch self {
        case let .fixTap(resting, side, taps):
            let rest = resting == 1 ? "1 resting finger" : "\(resting) resting fingers"
            return "\(rest), \(taps == 2 ? "double-tap" : "tap") \(side.rawValue)"
        case let .fingerTap(fingers):
            return "\(fingers)-finger tap"
        case let .fingerClick(fingers):
            return "\(fingers)-finger click"
        }
    }

    /// Compact name for picker tiles.
    public var shortTitle: String {
        switch self {
        case let .fixTap(resting, side, taps):
            return "Rest \(resting) · \(taps == 2 ? "double-tap" : "tap") \(side.rawValue)"
        case let .fingerTap(fingers):
            return "\(fingers)-finger tap"
        case let .fingerClick(fingers):
            return "\(fingers)-finger click"
        }
    }

    public var detail: String {
        switch self {
        case let .fixTap(resting, side, taps):
            let fingers = resting == 1 ? "one finger" : "two fingers"
            let them = resting == 1 ? "it" : "them"
            let tap = taps == 2 ? "double-tap" : "tap"
            return "Keep \(fingers) still on the trackpad, then \(tap) with another finger to the \(side.rawValue) of \(them)."
        case let .fingerTap(fingers):
            return "Tap lightly with \(fingers) fingers at the same time, without pressing the trackpad down."
        case let .fingerClick(fingers):
            return "Press the trackpad down until it clicks, with \(fingers) fingers on it. A light tap doesn't count."
        }
    }
}
