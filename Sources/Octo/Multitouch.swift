import AppKit
import IOKit

// Reads raw finger positions from the trackpad through Apple's private MultitouchSupport
// framework, the same one Jitouch, BetterTouchTool and MiddleClick use. It is loaded at
// runtime, so if a future macOS changes it, Octo fails quietly instead of crashing.

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTFrameCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

struct TrackpadInfo: Identifiable, Hashable {
    let id: Int
    let familyID: Int32
    let builtIn: Bool
    let widthMM: Double
    let heightMM: Double

    var name: String { builtIn ? "Built-in trackpad" : "Magic Trackpad" }
}

struct RawTouch {
    let id: Int32
    /// 3 = just touched, 4 = touching. Other states are hovering or lifting.
    let state: Int32
    /// 0...1 from the left edge.
    let x: Float
    /// 0...1 from the bottom edge.
    let y: Float
    let size: Float

    var isTouching: Bool { state == 3 || state == 4 }
}

/// Layout of one touch record in a frame (96 bytes on 64-bit macOS).
private let touchStride = 96

private func frameCallback(_ device: MTDeviceRef?, _ data: UnsafeMutableRawPointer?, _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    guard let device else { return 0 }
    var touches: [RawTouch] = []
    if let data, count > 0 {
        touches.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let p = data + i * touchStride
            touches.append(RawTouch(
                id: p.load(fromByteOffset: 16, as: Int32.self),
                state: p.load(fromByteOffset: 20, as: Int32.self),
                x: p.load(fromByteOffset: 32, as: Float.self),
                y: p.load(fromByteOffset: 36, as: Float.self),
                size: p.load(fromByteOffset: 48, as: Float.self)
            ))
        }
    }
    Engine.shared.handleFrame(device: device, touches: touches)
    return 0
}

final class MultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    typealias Register = @convention(c) (MTDeviceRef, MTFrameCallback) -> Void
    typealias Start = @convention(c) (MTDeviceRef, Int32) -> Void
    typealias Stop = @convention(c) (MTDeviceRef) -> Void
    typealias GetFamily = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>) -> Int32
    typealias GetDimensions = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    typealias IsBuiltIn = @convention(c) (MTDeviceRef) -> Bool

    static let shared = MultitouchAPI()

    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let familyID: GetFamily?
    let dimensions: GetDimensions?
    let isBuiltIn: IsBuiltIn?

    private init?() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let createList = load("MTDeviceCreateList", as: CreateList.self),
              let register = load("MTRegisterContactFrameCallback", as: Register.self),
              let unregister = load("MTUnregisterContactFrameCallback", as: Register.self),
              let start = load("MTDeviceStart", as: Start.self),
              let stop = load("MTDeviceStop", as: Stop.self) else { return nil }
        self.createList = createList
        self.register = register
        self.unregister = unregister
        self.start = start
        self.stop = stop
        familyID = load("MTDeviceGetFamilyID", as: GetFamily.self)
        dimensions = load("MTDeviceGetSensorSurfaceDimensions", as: GetDimensions.self)
        isBuiltIn = load("MTDeviceIsBuiltIn", as: IsBuiltIn.self)
    }
}

/// Finds trackpads, starts listening, and restarts after sleep or when a Magic Trackpad connects.
final class TrackpadManager {
    static let shared = TrackpadManager()

    /// Called on the main thread with the trackpads in use.
    var onChange: (([TrackpadInfo]) -> Void)?

    private var list: CFMutableArray?
    private var running: [MTDeviceRef] = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var restartItem: DispatchWorkItem?
    private static let magicMouseFamilies: Set<Int32> = [112, 113]

    var isAvailable: Bool { MultitouchAPI.shared != nil }

    func start() {
        observeSystemEvents()
        startDevices()
    }

    func restart(after delay: Double = 0.5) {
        restartItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.stopDevices()
            self?.startDevices()
        }
        restartItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func startDevices() {
        guard let api = MultitouchAPI.shared, let list = api.createList()?.takeRetainedValue() else {
            Engine.shared.setDevices([])
            onChange?([])
            return
        }
        self.list = list
        var found: [(MTDeviceRef, TrackpadInfo)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: raw)
            var family: Int32 = 0, width: Int32 = 0, height: Int32 = 0
            _ = api.familyID?(ref, &family)
            _ = api.dimensions?(ref, &width, &height)
            if Self.magicMouseFamilies.contains(family) { continue }
            // Dimensions come in hundredths of a millimetre.
            let info = TrackpadInfo(
                id: i,
                familyID: family,
                builtIn: api.isBuiltIn?(ref) ?? false,
                widthMM: width > 1000 ? Double(width) / 100 : 125,
                heightMM: height > 1000 ? Double(height) / 100 : 77
            )
            found.append((ref, info))
        }
        // Tell the engine first so the very first frame finds its trackpad.
        Engine.shared.setDevices(found)
        for (ref, _) in found {
            api.register(ref, frameCallback)
            api.start(ref, 0)
            running.append(ref)
        }
        onChange?(found.map(\.1))
    }

    private func stopDevices() {
        guard let api = MultitouchAPI.shared else { return }
        for ref in running {
            api.unregister(ref, frameCallback)
            api.stop(ref)
        }
        running.removeAll()
        Engine.shared.setDevices([])
        list = nil
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restart(after: 1.5)
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            TrackpadManager.drain(iterator)
            guard let refcon else { return }
            Unmanaged<TrackpadManager>.fromOpaque(refcon).takeUnretainedValue().restart(after: 0.8)
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, refcon, &iterator
            )
            if result == KERN_SUCCESS {
                TrackpadManager.drain(iterator) // arms the notification
                iterators.append(iterator)
            }
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }
}
