import AppKit
import Combine
import LayoutCore
import ServiceManagement

final class LayoutEngine: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var setup: DisplaySetup
    @Published private(set) var hasPermission = WindowAccess.isTrusted
    @Published private(set) var isWorking = false
    @Published private(set) var liveWindowCount = 0
    @Published private(set) var liveWindows: [SavedWindow] = []
    @Published private(set) var status = "Ready to remember"
    @Published private(set) var detail = "Arrange your windows once. Come back to them every time."
    @Published private(set) var issue: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false

    let store: StateStore
    private let access = WindowAccess()
    private var learning = LearningGate()
    private var watcher: DisplayWatcher?
    private var timer: Timer?
    private var transitionTask: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var busy = false
    private var operation = 0
    private var observedWindows = Set<String>()
    private var pendingWindows = Set<String>()
    private var hasBaseline = false
    private enum PendingAction { case save, restore }
    private var pendingAction: PendingAction?
    private var storageBlocked = false
    private let smokeTest: Bool

    var currentProfile: LayoutProfile? { state.profiles.first { $0.id == setup.signature } }
    var isLaptopMaximized: Bool { setup.isLaptopOnly && state.settings.maximizeLaptop }
    var canRestore: Bool { hasPermission && !isWorking && (isLaptopMaximized || currentProfile != nil) }
    var canSave: Bool { hasPermission && !isWorking && !storageBlocked && !setup.displays.isEmpty }

    init(dataURL: URL, smokeTest: Bool = false) {
        store = StateStore(url: dataURL)
        self.smokeTest = smokeTest
        setup = DisplayDetector.current()
        do { state = try store.load() }
        catch {
            var fresh = AppState()
            fresh.settings.automaticLayouts = false
            state = fresh
            storageBlocked = true
            issue = "Could not read your layouts: \(error.localizedDescription) Your existing file has been preserved."
        }
        refreshLoginStatus()
    }

    func start() {
        guard !smokeTest else { return }
        watcher = DisplayWatcher { [weak self] in self?.displayChanged() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.displayChanged() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        if hasPermission && state.settings.automaticLayouts { displayChanged() }
        else { updateIdleStatus() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        transitionTask?.cancel(); transitionTask = nil
        watcher = nil
        access.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    func markDashboardOpened() {
        guard !state.settings.hasOpenedDashboard else { return }
        state.settings.hasOpenedDashboard = true
        persist()
    }

    func enableAccessibility() {
        WindowAccess.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setAutomatic(_ enabled: Bool) {
        state.settings.automaticLayouts = enabled
        persist()
        cancelOperations()
        learning.beginTransition()
        learning.settle(now: Date(), grace: 2)
        hasBaseline = false
        pendingWindows = []
        updateIdleStatus()
        poll()
    }

    func setMaximizeLaptop(_ enabled: Bool) {
        state.settings.maximizeLaptop = enabled
        persist()
        if enabled && setup.isLaptopOnly { restoreNow() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if loginNeedsApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            issue = "Could not change launch at login: \(error.localizedDescription)"
            refreshLoginStatus()
        }
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func renameProfile(id: String, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[index].name = String(cleaned.prefix(80))
        persist()
    }

    func forgetProfile(id: String) {
        state.profiles.removeAll { $0.id == id }
        persist()
        if id == setup.signature {
            // Give the user time to rearrange before automatic learning creates a new profile.
            learning.suppress(now: Date(), duration: 10)
            updateIdleStatus()
        }
    }

    func revealData() {
        let url = FileManager.default.fileExists(atPath: store.url.path) ? store.url : store.url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismissIssue() { if !storageBlocked { issue = nil } }

    func saveNow() {
        guard canSave else { return }
        if busy { pendingAction = .save; return }
        let token = beginOperation()
        let generation = learning.generation
        access.scan { [weak self] scan in
            guard let self, self.finishOperation(token), self.acceptScan(generation: generation) else { return }
            self.updateLive(scan)
            guard !scan.windows.isEmpty else {
                self.status = "No movable windows found"
                self.detail = "Open a regular app window, then save again."
                return
            }
            self.record(scan, keepMissing: !scan.unavailableApps.isEmpty, force: true)
            self.observedWindows = Set(scan.windows.map(\.runtimeID)); self.hasBaseline = true
            self.pendingWindows = []
            self.learning.suppress(now: Date(), duration: 2)
            if !scan.unavailableApps.isEmpty {
                self.issue = "Some apps did not respond: \(scan.unavailableApps.joined(separator: ", ")). Their remembered windows were kept."
            }
        }
    }

    func restoreNow() {
        guard canRestore else { return }
        if busy { pendingAction = .restore; return }
        restoreCurrent(automatic: false)
    }

    private func displayChanged() {
        cancelOperations()
        learning.beginTransition()
        isWorking = true
        hasBaseline = false
        pendingWindows = []
        status = "Displays are settling"
        detail = "Your previous layout is safely remembered."
        let task = DispatchWorkItem { [weak self] in self?.settleDisplays() }
        transitionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }

    private func settleDisplays() {
        let detected = DisplayDetector.current()
        guard !detected.displays.isEmpty else {
            let task = DispatchWorkItem { [weak self] in self?.settleDisplays() }
            transitionTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
            return
        }
        setup = detected
        liveWindows = []; liveWindowCount = 0
        learning.settle(now: Date(), grace: 5)
        isWorking = false
        if hasPermission && state.settings.automaticLayouts { restoreCurrent(automatic: true) }
        else { updateIdleStatus() }
    }

    private func cancelOperations() {
        transitionTask?.cancel(); transitionTask = nil
        access.invalidate()
        operation += 1; busy = false; isWorking = false
        pendingAction = nil
    }

    private func beginOperation(showBusy: Bool = true) -> Int {
        operation += 1; busy = true
        if showBusy { isWorking = true }
        return operation
    }

    private func acceptScan(generation: Int) -> Bool {
        guard learning.accepts(generation: generation) else { return false }
        // Notifications may arrive just after a worker completes. Recheck the
        // actual screens before either saving or moving a captured window.
        guard DisplayDetector.current() == setup else { displayChanged(); return false }
        return true
    }

    @discardableResult
    private func finishOperation(_ token: Int) -> Bool {
        guard operation == token else { return false }
        busy = false; isWorking = false
        if let pending = pendingAction {
            pendingAction = nil
            DispatchQueue.main.async { [weak self] in
                switch pending {
                case .save: self?.saveNow()
                case .restore: self?.restoreNow()
                }
            }
        }
        return true
    }

    private func poll() {
        let trusted = WindowAccess.isTrusted
        if trusted != hasPermission {
            hasPermission = trusted
            if trusted && state.settings.automaticLayouts { displayChanged(); return }
            if !trusted {
                cancelOperations()
                learning.beginTransition(); learning.settle(now: Date(), grace: 0)
                updateIdleStatus(); return
            }
        }
        guard !smokeTest, !learning.isTransitioning else { return }
        let detected = DisplayDetector.current()
        if detected != setup { displayChanged(); return }
        guard hasPermission, !busy else { return }
        let token = beginOperation(showBusy: false)
        let generation = learning.generation
        access.scan { [weak self] scan in
            guard let self, self.finishOperation(token), self.acceptScan(generation: generation) else { return }
            self.updateLive(scan)
            let runtimeIDs = Set(scan.windows.map(\.runtimeID))
            if self.hasBaseline { self.pendingWindows.formUnion(runtimeIDs.subtracting(self.observedWindows)) }
            self.pendingWindows.formIntersection(runtimeIDs)
            let newIndices = scan.windows.indices.filter { self.pendingWindows.contains(scan.windows[$0].runtimeID) }
            let shouldPlaceNew = self.hasBaseline && self.state.settings.automaticLayouts && self.learning.canLearn(now: Date())
            self.observedWindows = runtimeIDs; self.hasBaseline = true
            if shouldPlaceNew && !newIndices.isEmpty {
                let allTargets = LayoutPlanner.targets(current: scan.windows.map(\.descriptor), profile: self.currentProfile,
                                                       setup: self.setup, maximizeLaptop: self.state.settings.maximizeLaptop)
                let targets = allTargets.filter { newIndices.contains($0.key) }
                self.pendingWindows = []
                if !targets.isEmpty { self.apply(scan, targets: targets, automatic: true); return }
            }
            guard self.state.settings.automaticLayouts, !scan.windows.isEmpty else { return }
            if self.learning.shouldLearn(scan.windows.map(\.descriptor), generation: generation, now: Date()) {
                self.record(scan, keepMissing: true, force: false)
            }
        }
    }

    private func restoreCurrent(automatic: Bool) {
        guard hasPermission, !busy else { return }
        let token = beginOperation()
        let generation = learning.generation
        status = "Restoring your layout"
        detail = isLaptopMaximized ? "Filling the built-in screen with your windows." : "Putting each window back in its place."
        access.scan { [weak self] scan in
            guard let self, self.finishOperation(token), self.acceptScan(generation: generation) else { return }
            self.updateLive(scan)
            self.observedWindows = Set(scan.windows.map(\.runtimeID)); self.hasBaseline = true
            self.pendingWindows = []
            let targets = LayoutPlanner.targets(current: scan.windows.map(\.descriptor), profile: self.currentProfile,
                                                setup: self.setup, maximizeLaptop: self.state.settings.maximizeLaptop)
            guard !targets.isEmpty else {
                self.updateIdleStatus()
                if self.currentProfile != nil && scan.windows.isEmpty {
                    self.detail = "Open your apps. Their windows will return to the remembered positions."
                }
                return
            }
            self.apply(scan, targets: targets, automatic: automatic)
        }
    }

    private func apply(_ scan: WindowScan, targets: [Int: WindowRect], automatic: Bool) {
        let token = beginOperation()
        learning.suppress(now: Date(), duration: 5)
        access.restore(windows: scan.windows, targets: targets) { [weak self] report in
            guard let self, self.finishOperation(token), !report.cancelled else { return }
            self.learning.suppress(now: Date(), duration: 3)
            if report.failed > 0 {
                self.status = "Restored \(report.moved + report.alreadyPlaced) of \(report.total) windows"
                self.issue = "\(report.failedApps.joined(separator: ", ")) could not use the saved size or position. Some apps enforce a minimum window size."
            } else {
                self.status = self.isLaptopMaximized ? "Windows maximized" : "Layout restored"
            }
            self.detail = "\(report.moved + report.alreadyPlaced) windows placed. \(automatic ? "Changes will be remembered automatically." : "You can keep arranging your windows.")"
        }
    }

    private func updateLive(_ scan: WindowScan) {
        liveWindowCount = scan.windows.count
        liveWindows = LayoutPlanner.capture(scan.windows.map(\.descriptor), setup: setup, previous: nil, keepMissing: false).windows
    }

    private func record(_ scan: WindowScan, keepMissing: Bool, force: Bool) {
        guard !storageBlocked else { return }
        let previous = currentProfile
        let profile = LayoutPlanner.capture(scan.windows.map(\.descriptor), setup: setup,
                                            previous: previous, keepMissing: keepMissing)
        guard force || previous?.windows != profile.windows || previous?.displays != profile.displays else { return }
        if let index = state.profiles.firstIndex(where: { $0.id == profile.id }) { state.profiles[index] = profile }
        else { state.profiles.append(profile) }
        if persist() {
            status = force ? "Layout saved" : "Watching your layout"
            detail = "\(scan.windows.count) windows remembered for \(profile.name)."
        }
    }

    private func updateIdleStatus() {
        if !hasPermission {
            status = "Accessibility access needed"
            detail = "Give Remember permission to save and move your windows."
        } else if !state.settings.automaticLayouts {
            status = "Automatic layouts paused"
            detail = "You can still save and restore layouts using the buttons."
        } else if currentProfile == nil {
            status = "A new place to work"
            detail = "Arrange your windows. This setup will be remembered automatically."
        } else {
            status = "Watching your layout"
            detail = "Changes are saved after your windows stop moving."
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !storageBlocked, !smokeTest else { return false }
        do { try store.save(state); return true }
        catch { issue = "Could not save your layouts: \(error.localizedDescription)"; return false }
    }
}
