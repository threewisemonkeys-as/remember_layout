import Foundation
import LayoutCore

struct LayoutCoreTests {
    let laptop = DisplayInfo(id: "laptop", name: "Built-in", isBuiltIn: true,
                             frame: WindowRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: WindowRect(x: 0, y: 25, width: 1440, height: 825))
    let monitor = DisplayInfo(id: "work", name: "Work Display", isBuiltIn: false,
                              frame: WindowRect(x: -2560, y: -300, width: 2560, height: 1440),
                              visibleFrame: WindowRect(x: -2560, y: -275, width: 2560, height: 1360))

    func window(_ title: String = "Document", bundle: String = "com.test.editor", id: String = "",
                ordinal: Int = 0, frame: WindowRect? = nil) -> WindowDescriptor {
        WindowDescriptor(bundleID: bundle, appName: "Editor", title: title, accessibilityID: id,
                         ordinal: ordinal, frame: frame ?? WindowRect(x: -2560, y: -275, width: 1280, height: 1360))
    }

    func testScreenSignatureSurvivesEnumerationOrderAndResolutionChange() {
        let first = DisplaySetup(displays: [laptop, monitor])
        var resized = monitor; resized.frame.width = 1920
        let second = DisplaySetup(displays: [resized, laptop])
        expectEqual(first.signature, second.signature)
        expectNotEqual(first, second)
        expectNotEqual(first.signature, DisplaySetup(displays: [monitor]).signature)
    }

    func testTopLeftConversionForScreensAboveAndLeftOfPrimary() {
        expectEqual(WindowRect.fromAppKit(x: -1920, y: 900, width: 1920, height: 1080, primaryTop: 900),
                       WindowRect(x: -1920, y: -1080, width: 1920, height: 1080))
    }

    func testRestoresProportionsOnResizedMonitorAndClampsToUsableSpace() {
        let saved = SavedWindow(descriptor: window(), display: monitor)
        var smaller = monitor
        smaller.visibleFrame = WindowRect(x: 1440, y: 25, width: 1920, height: 1000)
        let target = LayoutPlanner.target(for: saved, setup: DisplaySetup(displays: [laptop, smaller]))
        expectEqual(target, WindowRect(x: 1440, y: 25, width: 960, height: 1000))
    }

    func testLaptopPolicyFillsUsableScreenForEveryAppWithoutSavedProfile() {
        let targets = LayoutPlanner.targets(current: [window(), window("Browser", bundle: "com.test.browser")],
                                             profile: nil, setup: DisplaySetup(displays: [laptop]), maximizeLaptop: true)
        expectEqual(targets.count, 2)
        expectEqual(targets[0], laptop.visibleFrame)
        expectEqual(targets[1], laptop.visibleFrame)
    }

    func testLaptopPolicyDoesNotMaximizeExternalOrCombinedSetup() {
        expectTrue(LayoutPlanner.targets(current: [window()], profile: nil,
                                            setup: DisplaySetup(displays: [monitor]), maximizeLaptop: true).isEmpty)
        expectTrue(LayoutPlanner.targets(current: [window()], profile: nil,
                                            setup: DisplaySetup(displays: [laptop, monitor]), maximizeLaptop: true).isEmpty)
    }

    func testDisablingLaptopMaximizeRestoresRememberedSize() {
        let small = window(frame: WindowRect(x: 100, y: 80, width: 600, height: 500))
        let setup = DisplaySetup(displays: [laptop])
        let profile = LayoutPlanner.capture([small], setup: setup, previous: nil)
        let targets = LayoutPlanner.targets(current: [small], profile: profile, setup: setup, maximizeLaptop: false)
        expectEqual(targets[0], small.frame)
    }

    func testExactTitleCannotBeStolenByFallbackWhenWindowOrderChanges() {
        let saved = [SavedWindow(descriptor: window("A", ordinal: 0), display: monitor),
                     SavedWindow(descriptor: window("B", ordinal: 1), display: monitor)]
        let matching = LayoutPlanner.matches(current: [window("New title", ordinal: 0), window("A", ordinal: 1)], saved: saved)
        expectEqual(matching[1], 0)
        expectEqual(matching[0], 1)
    }

    func testDuplicateAccessibilityIdentifiersUseWindowTitles() {
        let saved = [SavedWindow(descriptor: window("A", id: "window", ordinal: 0), display: monitor),
                     SavedWindow(descriptor: window("B", id: "window", ordinal: 1), display: monitor)]
        let matching = LayoutPlanner.matches(current: [window("B", id: "window", ordinal: 0), window("A", id: "window", ordinal: 1)], saved: saved)
        expectEqual(matching[0], 1)
        expectEqual(matching[1], 0)
    }

    func testUniqueIdentifierSurvivesChangedDocumentTitle() {
        let saved = [SavedWindow(descriptor: window("Old", id: "unique"), display: monitor)]
        expectEqual(LayoutPlanner.matches(current: [window("New", id: "unique")], saved: saved)[0], 0)
    }

    func testMatchingNeverCrossesApplicationsOrUsesSavedSlotTwice() {
        let saved = [SavedWindow(descriptor: window("Same"), display: monitor)]
        let matching = LayoutPlanner.matches(current: [window("Same", bundle: "other.app"), window("Same"), window("Same", ordinal: 1)], saved: saved)
        expectNil(matching[0]); expectEqual(matching[1], 0); expectNil(matching[2])
    }

    func testClosedAppsAreRetainedByAutomaticCaptureAndRemovedByExplicitReplacement() {
        let setup = DisplaySetup(displays: [monitor])
        let initial = LayoutPlanner.capture([window("Editor"), window("Browser", bundle: "com.test.browser")], setup: setup, previous: nil)
        let automatic = LayoutPlanner.capture([window("Editor")], setup: setup, previous: initial)
        expectEqual(automatic.windows.count, 2)
        expectEqual(automatic.windows[0].id, initial.windows[0].id)
        let explicit = LayoutPlanner.capture([window("Editor")], setup: setup, previous: initial, keepMissing: false)
        expectEqual(explicit.windows.count, 1)
    }

    func testOffScreenWindowChoosesNearestMonitorAndBecomesVisible() {
        let setup = DisplaySetup(displays: [laptop])
        let profile = LayoutPlanner.capture([window()], setup: setup, previous: nil)
        let target = LayoutPlanner.target(for: profile.windows[0], setup: setup)!
        expectEqual(target.x, laptop.visibleFrame.x)
        expectEqual(target.y, laptop.visibleFrame.y)
        expectLessThanOrEqual(target.height, laptop.visibleFrame.height)
    }

    func testCannotRestoreProfileForAnotherConfiguration() {
        let profile = LayoutPlanner.capture([window()], setup: DisplaySetup(displays: [monitor]), previous: nil)
        expectTrue(LayoutPlanner.targets(current: [window()], profile: profile,
                                            setup: DisplaySetup(displays: [laptop]), maximizeLaptop: false).isEmpty)
        expectNil(LayoutPlanner.target(for: profile.windows[0], setup: DisplaySetup(displays: [laptop])))
    }

    func testTransitionRejectsInFlightOldCaptureAndHonorsGracePeriod() {
        var gate = LearningGate()
        let oldToken = gate.generation
        let now = Date(timeIntervalSince1970: 100)
        gate.beginTransition()
        expectFalse(gate.accepts(generation: oldToken))
        expectFalse(gate.shouldLearn([window()], generation: gate.generation, now: now))
        gate.settle(now: now, grace: 5)
        expectFalse(gate.shouldLearn([window()], generation: oldToken, now: now.addingTimeInterval(10)))
        expectFalse(gate.shouldLearn([window()], generation: gate.generation, now: now.addingTimeInterval(4)))
        expectFalse(gate.shouldLearn([window()], generation: gate.generation, now: now.addingTimeInterval(5)))
        expectTrue(gate.shouldLearn([window()], generation: gate.generation, now: now.addingTimeInterval(7)))
    }

    func testLearningWaitsUntilDraggingStops() {
        var gate = LearningGate()
        let now = Date(timeIntervalSince1970: 100)
        let first = window()
        var moved = first; moved.frame.x += 200
        expectFalse(gate.shouldLearn([first], generation: 0, now: now))
        expectFalse(gate.shouldLearn([moved], generation: 0, now: now.addingTimeInterval(1)))
        expectFalse(gate.shouldLearn([moved], generation: 0, now: now.addingTimeInterval(2)))
        expectTrue(gate.shouldLearn([moved], generation: 0, now: now.addingTimeInterval(3)))
    }

    func testPersistenceRoundTripAndAtomicReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("layouts.json"))
        expectEqual(try store.load(), AppState())
        var state = AppState()
        state.profiles = [LayoutPlanner.capture([window()], setup: DisplaySetup(displays: [monitor]), previous: nil)]
        try store.save(state)
        expectEqual(try store.load(), state)
        state.settings.automaticLayouts = false
        try store.save(state)
        expectEqual(try store.load(), state)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        expectEqual(permissions?.intValue, 0o600)
    }

    func testUnknownSchemaIsRejectedWithoutOverwritingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("layouts.json"))
        var state = AppState(); state.schemaVersion = 2
        try store.save(state)
        let original = try Data(contentsOf: store.url)
        expectThrows(try store.load())
        expectEqual(try Data(contentsOf: store.url), original)
    }

    func testInvalidGeometryCannotBeLoaded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("layouts.json"))
        var state = AppState()
        var profile = LayoutPlanner.capture([window()], setup: DisplaySetup(displays: [monitor]), previous: nil)
        profile.windows[0].normalizedFrame.width = -1
        state.profiles = [profile]
        try store.save(state)
        expectThrows(try store.load())
    }
}
