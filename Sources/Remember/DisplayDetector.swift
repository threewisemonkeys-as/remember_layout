import AppKit
import CoreGraphics
import LayoutCore

enum DisplayDetector {
    static func current() -> DisplaySetup {
        let screens = NSScreen.screens
        let primaryTop = Double(screens.first?.frame.maxY ?? 0)
        let displays = screens.compactMap { screen -> DisplayInfo? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let id: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                id = CFUUIDCreateString(nil, uuid) as String
            } else {
                // UUIDs can be unavailable briefly during display reconfiguration.
                id = "display-\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))-\(displayID)"
            }
            func convert(_ rect: NSRect) -> WindowRect {
                .fromAppKit(x: Double(rect.minX), y: Double(rect.minY),
                            width: Double(rect.width), height: Double(rect.height), primaryTop: primaryTop)
            }
            return DisplayInfo(id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                               frame: convert(screen.frame), visibleFrame: convert(screen.visibleFrame))
        }
        return DisplaySetup(displays: displays)
    }
}

private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                 _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(context).takeUnretainedValue()
    watcher.deliverChange()
}

final class DisplayWatcher {
    private let onChange: () -> Void
    private var notification: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        notification = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onChange() }
    }

    func deliverChange() {
        DispatchQueue.main.async { [weak self] in self?.onChange() }
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        if let notification { NotificationCenter.default.removeObserver(notification) }
    }
}
