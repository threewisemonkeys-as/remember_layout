import Foundation

enum CheckResults {
    static var failures = 0

    static func fail(_ message: String, file: StaticString, line: UInt) {
        failures += 1
        fputs("FAIL \(file):\(line): \(message)\n", stderr)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { CheckResults.fail("\(actual) != \(expected)", file: file, line: line) }
}

func expectNotEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual == expected { CheckResults.fail("Values should differ", file: file, line: line) }
}

func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { CheckResults.fail("Expected true", file: file, line: line) }
}

func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { CheckResults.fail("Expected false", file: file, line: line) }
}

func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { CheckResults.fail("Expected nil", file: file, line: line) }
}

func expectLessThanOrEqual<T: Comparable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual > expected { CheckResults.fail("\(actual) > \(expected)", file: file, line: line) }
}

func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        CheckResults.fail("Expected an error", file: file, line: line)
    } catch {}
}
