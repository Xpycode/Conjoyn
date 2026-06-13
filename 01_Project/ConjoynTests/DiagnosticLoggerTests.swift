import XCTest
@testable import Conjoyn

/// Tests for `DiagnosticLogger` — the persistent, file-backed log that mirrors `QueueManager`'s
/// in-memory console to disk so bug reports survive a quit/relaunch.
///
/// Every test runs against a fresh, throwaway storage directory injected via
/// `DiagnosticLogger(storageDirectory:)`, so the suite never reads or mutates the user's real
/// `~/Library/Application Support/Conjoyn/diagnostic.log`.
@MainActor
final class DiagnosticLoggerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLoggerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        tmpDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private var logURL: URL { tmpDir.appendingPathComponent("diagnostic.log") }
    private var rotatedURL: URL { tmpDir.appendingPathComponent("diagnostic.log.1") }

    private func readLog() throws -> String {
        try String(contentsOf: logURL, encoding: .utf8)
    }

    // MARK: - Basic writing

    func testInitWritesSessionBannerWithVersion() throws {
        _ = DiagnosticLogger(storageDirectory: tmpDir)

        let contents = try readLog()
        XCTAssertTrue(contents.contains("session started"), "init should stamp a session marker")
        XCTAssertTrue(contents.contains("Conjoyn"), "banner should name the app + version")
        // Every line is ISO-stamped in brackets.
        XCTAssertTrue(contents.hasPrefix("["), "lines should begin with a [timestamp]")
    }

    func testLogAppendsTimestampedLineToFile() throws {
        let logger = DiagnosticLogger(storageDirectory: tmpDir)

        logger.log("hello world")

        let contents = try readLog()
        XCTAssertTrue(contents.contains("hello world"))
        // Banner + one logged line = at least two newline-terminated entries.
        let lines = contents.split(separator: "\n")
        XCTAssertGreaterThanOrEqual(lines.count, 2)
    }

    func testMultipleLogsAreAllAppendedInOrder() throws {
        let logger = DiagnosticLogger(storageDirectory: tmpDir)

        logger.log("first")
        logger.log("second")
        logger.log("third")

        let contents = try readLog()
        guard let i1 = contents.range(of: "first"),
              let i2 = contents.range(of: "second"),
              let i3 = contents.range(of: "third") else {
            return XCTFail("all three messages should be present")
        }
        XCTAssertTrue(i1.lowerBound < i2.lowerBound && i2.lowerBound < i3.lowerBound,
                      "appends must preserve order")
    }

    // MARK: - Injectable directory

    func testHonorsInjectedStorageDirectory() throws {
        _ = DiagnosticLogger(storageDirectory: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path),
                      "log must land in the injected directory, not real app-support")
    }

    // MARK: - Rotation

    func testRotatesWhenFileExceedsMaxBytes() throws {
        // Pre-seed an oversized log; the logger's first write (the init banner) should trip rotation.
        let oversized = Data(count: DiagnosticLogger.maxBytes + 1)
        try oversized.write(to: logURL)

        _ = DiagnosticLogger(storageDirectory: tmpDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedURL.path),
                      "oversized log should be rotated to diagnostic.log.1")
        // The rotated file holds the old (large) content…
        let rotatedSize = (try FileManager.default
            .attributesOfItem(atPath: rotatedURL.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(rotatedSize, DiagnosticLogger.maxBytes)
        // …and a fresh, small diagnostic.log now holds just the banner.
        let freshSize = (try FileManager.default
            .attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? Int.max
        XCTAssertLessThan(freshSize, DiagnosticLogger.maxBytes)
        XCTAssertTrue(try readLog().contains("session started"))
    }

    func testRotationReplacesPreviousGeneration() throws {
        // A stale .1 from an earlier rotation must be overwritten, not accumulated.
        try Data("stale generation".utf8).write(to: rotatedURL)
        try Data(count: DiagnosticLogger.maxBytes + 1).write(to: logURL)

        _ = DiagnosticLogger(storageDirectory: tmpDir)

        let rotatedContents = try String(contentsOf: rotatedURL, encoding: .utf8)
        XCTAssertFalse(rotatedContents.contains("stale generation"),
                       "previous .1 should be replaced by the newly rotated log")
        let rotatedSize = (try FileManager.default
            .attributesOfItem(atPath: rotatedURL.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(rotatedSize, DiagnosticLogger.maxBytes,
                             ".1 should now be the former oversized diagnostic.log")
    }

    func testDoesNotRotateBelowThreshold() throws {
        let logger = DiagnosticLogger(storageDirectory: tmpDir)
        logger.log("small")

        XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedURL.path),
                       "a small log must never rotate")
    }
}
