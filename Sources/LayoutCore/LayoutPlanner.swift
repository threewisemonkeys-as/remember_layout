import Foundation

public enum LayoutPlanner {
    /// Matches all exact identities first so fallback slots cannot steal an exact match.
    /// AX identifiers are used only when unique: many apps give every window the same ID.
    public static func matches(current: [WindowDescriptor], saved: [SavedWindow]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var used = Set<Int>()
        func assign(_ currentIndex: Int, _ savedIndex: Int) {
            result[currentIndex] = savedIndex; used.insert(savedIndex)
        }
        for bundle in Set(current.map(\.bundleID)).sorted() {
            let live = current.indices.filter { current[$0].bundleID == bundle }
            let stored = saved.indices.filter { saved[$0].bundleID == bundle }
            for i in live {
                let identifier = current[i].accessibilityID
                guard !identifier.isEmpty,
                      live.filter({ current[$0].accessibilityID == identifier }).count == 1 else { continue }
                let candidates = stored.filter { saved[$0].accessibilityID == identifier }
                if candidates.count == 1, let j = candidates.first, !used.contains(j) { assign(i, j) }
            }
            for i in live where result[i] == nil && !current[i].title.isEmpty {
                if let j = stored.first(where: { !used.contains($0) && saved[$0].title == current[i].title }) {
                    assign(i, j)
                }
            }
            for i in live where result[i] == nil {
                if let j = stored.first(where: { !used.contains($0) && saved[$0].ordinal == current[i].ordinal }) {
                    assign(i, j)
                }
            }
            for i in live where result[i] == nil {
                if let j = stored.first(where: { !used.contains($0) }) { assign(i, j) }
            }
        }
        return result
    }

    /// Keep slots for temporarily closed apps so they can be restored when reopened.
    /// Explicit capture can instead replace the profile with exactly the open windows.
    public static func capture(_ windows: [WindowDescriptor], setup: DisplaySetup,
                               previous: LayoutProfile?, keepMissing: Bool = true,
                               now: Date = Date()) -> LayoutProfile {
        var profile = previous ?? LayoutProfile(setup: setup)
        let previousWindows = profile.windows
        let matching = matches(current: windows, saved: previousWindows)
        var captured: [SavedWindow] = []
        var updatedIDs = Set<UUID>()
        for (i, descriptor) in windows.enumerated() where descriptor.frame.isValid {
            guard let display = setup.display(for: descriptor.frame) else { continue }
            let id = matching[i].map { previousWindows[$0].id } ?? UUID()
            captured.append(SavedWindow(id: id, descriptor: descriptor, display: display))
            updatedIDs.insert(id)
        }
        let retained = keepMissing ? previousWindows.filter { !updatedIDs.contains($0.id) } : []
        profile.windows = Array((captured + retained).prefix(200))
        profile.displays = setup.displays
        profile.updatedAt = now
        return profile
    }

    public static func target(for window: SavedWindow, setup: DisplaySetup) -> WindowRect? {
        guard window.normalizedFrame.isValid,
              let display = setup.displays.first(where: { $0.id == window.displayID }) else { return nil }
        return window.normalizedFrame.expanded(in: display.visibleFrame).clamped(to: display.visibleFrame)
    }

    public static func targets(current: [WindowDescriptor], profile: LayoutProfile?,
                               setup: DisplaySetup, maximizeLaptop: Bool) -> [Int: WindowRect] {
        if setup.isLaptopOnly && maximizeLaptop {
            return Dictionary(uniqueKeysWithValues: current.indices.map { ($0, setup.displays[0].visibleFrame) })
        }
        guard let profile, profile.id == setup.signature else { return [:] }
        return matches(current: current, saved: profile.windows).reduce(into: [:]) { result, match in
            result[match.key] = target(for: profile.windows[match.value], setup: setup)
        }
    }
}

/// A capture started on one configuration must never be saved into another.
/// Learning waits through monitor reflow and until window movements have settled.
public struct LearningGate: Sendable {
    public private(set) var generation = 0
    public private(set) var isTransitioning = false
    private var suppressedUntil: Date = .distantPast
    private var candidate: [WindowDescriptor] = []
    private var candidateSince: Date = .distantPast

    public init() {}

    public mutating func beginTransition() {
        generation += 1; isTransitioning = true
        candidate = []; candidateSince = .distantPast
    }

    public mutating func settle(now: Date, grace: TimeInterval = 4) {
        isTransitioning = false; suppressedUntil = now.addingTimeInterval(grace)
        candidate = []; candidateSince = .distantPast
    }

    public func accepts(generation token: Int) -> Bool {
        token == generation && !isTransitioning
    }

    public mutating func suppress(now: Date, duration: TimeInterval) {
        suppressedUntil = now.addingTimeInterval(duration)
        candidate = []; candidateSince = .distantPast
    }

    public func canLearn(now: Date) -> Bool { !isTransitioning && now >= suppressedUntil }

    public mutating func shouldLearn(_ windows: [WindowDescriptor], generation token: Int,
                                    now: Date, quietPeriod: TimeInterval = 1.5) -> Bool {
        guard accepts(generation: token), canLearn(now: now) else { return false }
        let unchanged = windows.count == candidate.count && zip(windows, candidate).allSatisfy {
            $0.bundleID == $1.bundleID && $0.title == $1.title &&
            $0.accessibilityID == $1.accessibilityID && $0.ordinal == $1.ordinal && $0.frame.isClose(to: $1.frame)
        }
        if !unchanged || candidateSince == .distantPast {
            candidate = windows; candidateSince = now; return false
        }
        return now.timeIntervalSince(candidateSince) >= quietPeriod
    }
}
