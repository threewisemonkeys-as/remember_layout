import AppKit
import ApplicationServices
import LayoutCore

struct AccessibleWindow {
    let element: AXUIElement
    let runtimeID: String
    let descriptor: WindowDescriptor
}

struct WindowScan {
    var windows: [AccessibleWindow] = []
    var unavailableApps: [String] = []
}

struct RestoreReport {
    var moved = 0
    var alreadyPlaced = 0
    var failed = 0
    var skipped = 0
    var cancelled = false
    var failedApps: [String] = []
    var total: Int { moved + alreadyPlaced + failed }
}

/// Serial worker keeps slow/unresponsive Accessibility clients away from the UI.
final class WindowAccess {
    private let queue = DispatchQueue(label: "com.rememberlayout.accessibility", qos: .utility)
    private let cancellationLock = NSLock()
    private var operationGeneration = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Display changes revoke pending restores, including retries already on the worker.
    func invalidate() {
        cancellationLock.lock(); operationGeneration += 1; cancellationLock.unlock()
    }

    private func generation() -> Int {
        cancellationLock.lock(); defer { cancellationLock.unlock() }
        return operationGeneration
    }

    func scan(completion: @escaping (WindowScan) -> Void) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleIdentifier != nil
        }.map { ($0.processIdentifier, $0.bundleIdentifier!, $0.localizedName ?? "Application") }
        queue.async {
            var scan = WindowScan()
            for (pid, bundle, name) in apps.sorted(by: { $0.1 < $1.1 }) {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.25)
                var raw: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
                guard error == .success, let elements = raw as? [AXUIElement] else {
                    if error != .attributeUnsupported { scan.unavailableApps.append(name) }
                    continue
                }
                var ordinal = 0
                for element in elements {
                    let role = Self.string(element, kAXRoleAttribute)
                    let subrole = Self.string(element, kAXSubroleAttribute)
                    guard role == kAXWindowRole,
                          subrole.isEmpty || subrole == kAXStandardWindowSubrole,
                          !Self.bool(element, kAXMinimizedAttribute), !Self.bool(element, "AXFullScreen"),
                          let frame = Self.frame(element), frame.width >= 160, frame.height >= 80,
                          Self.isSettable(element, kAXPositionAttribute), Self.isSettable(element, kAXSizeAttribute) else { continue }
                    let descriptor = WindowDescriptor(bundleID: bundle, appName: name,
                                                      title: Self.string(element, kAXTitleAttribute),
                                                      accessibilityID: Self.string(element, kAXIdentifierAttribute),
                                                      ordinal: ordinal, frame: frame)
                    scan.windows.append(AccessibleWindow(element: element,
                                                          runtimeID: "\(pid):\(CFHash(element))", descriptor: descriptor))
                    ordinal += 1
                }
            }
            DispatchQueue.main.async { completion(scan) }
        }
    }

    func restore(windows: [AccessibleWindow], targets: [Int: WindowRect],
                 completion: @escaping (RestoreReport) -> Void) {
        let token = generation()
        queue.async {
            var report = RestoreReport()
            report.skipped = windows.count - targets.count
            var retry: [(AccessibleWindow, WindowRect)] = []
            for (index, target) in targets.sorted(by: { $0.key < $1.key }) {
                guard token == self.generation() else { report.cancelled = true; break }
                guard windows.indices.contains(index) else { continue }
                let window = windows[index]
                if Self.frame(window.element)?.isClose(to: target, tolerance: 4) == true {
                    report.alreadyPlaced += 1
                } else {
                    Self.place(window.element, at: target)
                    retry.append((window, target))
                }
            }
            // Some apps process a resize asynchronously. Verify after one short settling period.
            if !retry.isEmpty && !report.cancelled { Thread.sleep(forTimeInterval: 0.2) }
            for (window, target) in retry {
                guard token == self.generation() else { report.cancelled = true; break }
                if Self.frame(window.element)?.isClose(to: target, tolerance: 6) != true {
                    Self.place(window.element, at: target)
                }
                if Self.frame(window.element)?.isClose(to: target, tolerance: 6) == true {
                    report.moved += 1
                } else {
                    report.failed += 1
                    if !report.failedApps.contains(window.descriptor.appName) { report.failedApps.append(window.descriptor.appName) }
                }
            }
            DispatchQueue.main.async { completion(report) }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool {
        (attribute(element, name) as? NSNumber)?.boolValue ?? false
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func frame(_ element: AXUIElement) -> WindowRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        let result = WindowRect(x: Double(point.x), y: Double(point.y),
                                width: Double(dimensions.width), height: Double(dimensions.height))
        return result.isValid ? result : nil
    }

    private static func place(_ element: AXUIElement, at rect: WindowRect) {
        // Moving first lets apps adopt the target display's size constraints.
        var point = CGPoint(x: rect.x.rounded(), y: rect.y.rounded())
        var size = CGSize(width: rect.width.rounded(), height: rect.height.rounded())
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    }
}
