import Foundation

public struct WindowRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }

    public func intersectionArea(with other: Self) -> Double {
        max(0, min(x + width, other.x + other.width) - max(x, other.x)) *
        max(0, min(y + height, other.y + other.height) - max(y, other.y))
    }

    public func normalized(in bounds: Self) -> Self {
        Self(x: (x - bounds.x) / bounds.width, y: (y - bounds.y) / bounds.height,
             width: width / bounds.width, height: height / bounds.height)
    }

    public func expanded(in bounds: Self) -> Self {
        Self(x: bounds.x + x * bounds.width, y: bounds.y + y * bounds.height,
             width: width * bounds.width, height: height * bounds.height)
    }

    public func clamped(to bounds: Self) -> Self {
        let w = min(width, bounds.width), h = min(height, bounds.height)
        return Self(x: max(bounds.x, min(x, bounds.x + bounds.width - w)),
                    y: max(bounds.y, min(y, bounds.y + bounds.height - h)),
                    width: w, height: h)
    }

    public func isClose(to other: Self, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance &&
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// AppKit's desktop origin is bottom-left; Accessibility uses top-left.
    public static func fromAppKit(x: Double, y: Double, width: Double, height: Double,
                                  primaryTop: Double) -> Self {
        Self(x: x, y: primaryTop - y - height, width: width, height: height)
    }
}

public struct DisplayInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var frame: WindowRect
    public var visibleFrame: WindowRect

    public init(id: String, name: String, isBuiltIn: Bool, frame: WindowRect, visibleFrame: WindowRect) {
        self.id = id; self.name = name; self.isBuiltIn = isBuiltIn
        self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public struct DisplaySetup: Equatable, Sendable {
    public var displays: [DisplayInfo]
    public init(displays: [DisplayInfo]) { self.displays = displays }
    public var signature: String { displays.map(\.id).sorted().joined(separator: "|") }
    public var isLaptopOnly: Bool { displays.count == 1 && displays[0].isBuiltIn }
    public var suggestedName: String {
        if isLaptopOnly { return "MacBook" }
        return displays.sorted { !$0.isBuiltIn && $1.isBuiltIn }
            .map { $0.isBuiltIn ? "MacBook" : $0.name }.joined(separator: " + ")
    }

    public func display(for frame: WindowRect) -> DisplayInfo? {
        let byArea = displays.max { frame.intersectionArea(with: $0.frame) < frame.intersectionArea(with: $1.frame) }
        if let best = byArea, frame.intersectionArea(with: best.frame) > 0 { return best }
        // Disconnected screens can leave windows off-screen. Use the nearest screen.
        let cx = frame.x + frame.width / 2, cy = frame.y + frame.height / 2
        return displays.min {
            hypot(cx - ($0.frame.x + $0.frame.width / 2), cy - ($0.frame.y + $0.frame.height / 2)) <
            hypot(cx - ($1.frame.x + $1.frame.width / 2), cy - ($1.frame.y + $1.frame.height / 2))
        }
    }
}

public struct WindowDescriptor: Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var accessibilityID: String
    public var ordinal: Int
    public var frame: WindowRect

    public init(bundleID: String, appName: String, title: String, accessibilityID: String = "",
                ordinal: Int = 0, frame: WindowRect) {
        self.bundleID = bundleID; self.appName = appName; self.title = title
        self.accessibilityID = accessibilityID; self.ordinal = ordinal; self.frame = frame
    }
}

public struct SavedWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var title: String
    public var accessibilityID: String
    public var ordinal: Int
    public var displayID: String
    public var normalizedFrame: WindowRect

    public init(id: UUID = UUID(), descriptor: WindowDescriptor, display: DisplayInfo) {
        self.id = id; bundleID = descriptor.bundleID; appName = descriptor.appName
        title = descriptor.title; accessibilityID = descriptor.accessibilityID
        ordinal = descriptor.ordinal; displayID = display.id
        normalizedFrame = descriptor.frame.clamped(to: display.visibleFrame).normalized(in: display.visibleFrame)
    }
}

public struct LayoutProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var displays: [DisplayInfo]
    public var windows: [SavedWindow]
    public var updatedAt: Date

    public init(setup: DisplaySetup, name: String? = nil, windows: [SavedWindow] = [], updatedAt: Date = Date()) {
        id = setup.signature; self.name = name ?? setup.suggestedName
        displays = setup.displays; self.windows = windows; self.updatedAt = updatedAt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var automaticLayouts = true
    public var maximizeLaptop = true
    public var hasOpenedDashboard = false
    public init() {}
}

public struct AppState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var settings = AppSettings()
    public var profiles: [LayoutProfile] = []
    public init() {}
}
