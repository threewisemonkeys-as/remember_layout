import Foundation
import Darwin

/// Runnable with Command Line Tools alone; requires no Xcode test frameworks.
@main
enum CheckRunner {
    static func main() {
        let suite = LayoutCoreTests()
        let checks: [(String, () throws -> Void)] = [
            ("Display signatures", suite.testScreenSignatureSurvivesEnumerationOrderAndResolutionChange),
            ("Desktop coordinates", suite.testTopLeftConversionForScreensAboveAndLeftOfPrimary),
            ("Resolution changes", suite.testRestoresProportionsOnResizedMonitorAndClampsToUsableSpace),
            ("Laptop maximization", suite.testLaptopPolicyFillsUsableScreenForEveryAppWithoutSavedProfile),
            ("External layout policy", suite.testLaptopPolicyDoesNotMaximizeExternalOrCombinedSetup),
            ("Remember laptop sizes", suite.testDisablingLaptopMaximizeRestoresRememberedSize),
            ("Exact matching priority", suite.testExactTitleCannotBeStolenByFallbackWhenWindowOrderChanges),
            ("Duplicate identifiers", suite.testDuplicateAccessibilityIdentifiersUseWindowTitles),
            ("Changed window titles", suite.testUniqueIdentifierSurvivesChangedDocumentTitle),
            ("App and slot isolation", suite.testMatchingNeverCrossesApplicationsOrUsesSavedSlotTwice),
            ("Closed app retention", suite.testClosedAppsAreRetainedByAutomaticCaptureAndRemovedByExplicitReplacement),
            ("Off-screen recovery", suite.testOffScreenWindowChoosesNearestMonitorAndBecomesVisible),
            ("Configuration isolation", suite.testCannotRestoreProfileForAnotherConfiguration),
            ("Display transition safety", suite.testTransitionRejectsInFlightOldCaptureAndHonorsGracePeriod),
            ("Dragging debounce", suite.testLearningWaitsUntilDraggingStops),
            ("Persistence and permissions", suite.testPersistenceRoundTripAndAtomicReplacement),
            ("Future schema preservation", suite.testUnknownSchemaIsRejectedWithoutOverwritingFile),
            ("Invalid geometry rejection", suite.testInvalidGeometryCannotBeLoaded)
        ]
        for (name, check) in checks {
            let before = CheckResults.failures
            do { try check() }
            catch { CheckResults.fail("\(name): \(error)", file: #filePath, line: #line) }
            if CheckResults.failures == before { print("PASS \(name)") }
        }
        print("\(checks.count) checks, \(CheckResults.failures) failures")
        if CheckResults.failures > 0 { exit(1) }
    }
}
