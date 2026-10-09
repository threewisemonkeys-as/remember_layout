import AppKit
import SwiftUI
import LayoutCore

@main
enum RememberApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--diagnose") {
            let setup = DisplayDetector.current()
            struct Diagnostics: Encodable {
                let accessibilityGranted: Bool
                let displays: [DisplayInfo]
                let configurationID: String
            }
            let diagnostic = Diagnostics(accessibilityGranted: WindowAccess.isTrusted, displays: setup.displays, configurationID: setup.signature)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(diagnostic), let output = String(data: data, encoding: .utf8) { print(output) }
            return
        }
        let smokeTest = CommandLine.arguments.contains("--ui-smoke-test")
        let dataDirectory: URL
        if let index = CommandLine.arguments.firstIndex(of: "--data-directory"), CommandLine.arguments.indices.contains(index + 1) {
            dataDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        } else if smokeTest {
            dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("RememberSmokeTest-\(UUID().uuidString)")
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Remember", isDirectory: true)
        }
        let delegate = AppDelegate(dataURL: dataDirectory.appendingPathComponent("layouts.json"), smokeTest: smokeTest)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let engine: LayoutEngine
    private let smokeTest: Bool
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?

    init(dataURL: URL, smokeTest: Bool) {
        engine = LayoutEngine(dataURL: dataURL, smokeTest: smokeTest)
        self.smokeTest = smokeTest
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        engine.start()
        if !engine.state.settings.hasOpenedDashboard || !engine.hasPermission || smokeTest { showDashboard() }
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.savePreviewIfRequested()
                print("Remember UI smoke test passed: window and menu bar created.")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func savePreviewIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "--preview-output"),
              CommandLine.arguments.indices.contains(index + 1), let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            do {
                try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                print("Saved app preview.")
            } catch { fputs("Preview failed: \(error.localizedDescription)\n", stderr) }
        }
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Remember window layouts")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Remember — window layouts"
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 460, height: 710)
        popover.contentViewController = NSHostingController(rootView: DashboardView(engine: engine))
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            window?.orderOut(nil)
            engine.markDashboardOpened()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let restore = NSMenuItem(title: "Restore layout", action: #selector(restoreLayout), keyEquivalent: "")
        restore.target = self; restore.isEnabled = engine.canRestore
        menu.addItem(restore)
        let save = NSMenuItem(title: "Save layout now", action: #selector(saveLayout), keyEquivalent: "")
        save.target = self; save.isEnabled = engine.canSave
        menu.addItem(save)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Automatic layouts", action: #selector(toggleAutomatic), keyEquivalent: "")
        toggle.target = self; toggle.state = engine.state.settings.automaticLayouts ? .on : .off
        menu.addItem(toggle)
        let dashboard = NSMenuItem(title: "Open Remember", action: #selector(showDashboard), keyEquivalent: "")
        dashboard.target = self; menu.addItem(dashboard)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Remember", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func restoreLayout() { engine.restoreNow() }
    @objc private func saveLayout() { engine.saveNow() }
    @objc private func toggleAutomatic() { engine.setAutomatic(!engine.state.settings.automaticLayouts) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showDashboard() {
        popover.performClose(nil)
        if window == nil {
            let hosting = NSHostingController(rootView: DashboardView(engine: engine))
            let dashboard = NSWindow(contentViewController: hosting)
            dashboard.title = "Remember"
            dashboard.styleMask = [.titled, .closable, .miniaturizable]
            dashboard.setContentSize(NSSize(width: 460, height: 710))
            dashboard.isReleasedWhenClosed = false
            dashboard.delegate = self
            dashboard.center()
            window = dashboard
        }
        engine.markDashboardOpened()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(); return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
}
