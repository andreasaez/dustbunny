import XCTest
@testable import DustbunnyCore

final class ScreenshotMatcherTests: XCTestCase {
    func day(_ name: String) -> String? {
        ScreenshotMatcher.captureDay(forFileName: name)
    }

    func testMatchesMacOSScreenshotNames() {
        XCTAssertEqual(day("Screenshot 2026-10-11 at 18.04.12.png"), "2026-10-11")
        XCTAssertEqual(day("Screenshot 2026-10-11 at 9.41.03\u{202F}PM.png"), "2026-10-11")
        XCTAssertEqual(day("Screen Shot 2020-01-02 at 9.41.03 PM.png"), "2020-01-02")
        XCTAssertEqual(day("Screenshot 2026-10-11 at 18.04.12 (2).PNG"), "2026-10-11")
        XCTAssertEqual(day("Screenshot 2026-10-11 at 18.04.12.jpg"), "2026-10-11")
    }

    func testRejectsEverythingElse() {
        XCTAssertNil(day("Screenshot.png"))
        XCTAssertNil(day("Screenshot 2026-10-11.png"))
        XCTAssertNil(day("Screenshot 2026-13-11 at 18.04.12.png"))
        XCTAssertNil(day("Screenshot 2026-10-00 at 18.04.12.png"))
        XCTAssertNil(day("Screenshot 2026-10-11 at 18.04.12.txt"))
        XCTAssertNil(day("Screenshot 2026-10-11 at 18.04.12"))
        XCTAssertNil(day("My Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertNil(day("screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertNil(day(".Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertNil(day("Screenshot 2026-10-11 at .png"))
        XCTAssertNil(day("Screenshot ２０２６-10-11 at 18.04.12.png"))
    }

    func testIgnoresScreenRecordingsAndVideos() {
        XCTAssertNil(day("Screen Recording 2026-10-11 at 18.04.12.mov"))
        XCTAssertNil(day("Screenshot 2026-10-11 at 18.04.12.mov"))
        XCTAssertNil(day("Screenshot 2026-10-11 at 18.04.12.mp4"))
    }
}

final class SweeperTests: XCTestCase {
    var folder: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("dustbunny-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: folder)
    }

    @discardableResult
    func touch(_ path: String, _ contents: String = "x") throws -> URL {
        let url = folder.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exists(_ path: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(path).path) }

    func testSweepsIntoDatedFolders() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        try touch("Screenshot 2026-10-10 at 08.00.00.png")
        try touch("notes.txt")
        try touch("Screen Recording 2026-10-11 at 18.05.00.mov")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertEqual(report.moves.count, 2)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(exists("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(exists("Screenshots/2026-10-10/Screenshot 2026-10-10 at 08.00.00.png"))
        XCTAssertTrue(exists("notes.txt"))
        XCTAssertTrue(exists("Screen Recording 2026-10-11 at 18.05.00.mov"))
    }

    func testNeverOverwrites() throws {
        let name = "Screenshot 2026-10-11 at 18.04.12.png"
        try touch("Screenshots/2026-10-11/\(name)", "original")
        try touch(name, "new")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertEqual(report.moves.count, 1)
        let original = try String(contentsOf: folder.appendingPathComponent("Screenshots/2026-10-11/\(name)"), encoding: .utf8)
        XCTAssertEqual(original, "original")
        XCTAssertTrue(exists("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12 (2).png"))
    }

    func testSkipsSymlinksAndFolders() throws {
        let outside = fm.temporaryDirectory.appendingPathComponent("dustbunny-outside-\(UUID().uuidString).png")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: outside) }
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Screenshot 2026-10-11 at 1.00.00.png"), withDestinationURL: outside)
        try fm.createDirectory(at: folder.appendingPathComponent("Screenshot 2026-10-11 at 2.00.00.png"), withIntermediateDirectories: false)

        let report = Sweeper().sweep(folder: folder)

        XCTAssertTrue(report.moves.isEmpty)
        XCTAssertFalse(exists("Screenshots"))
    }

    func testRefusesSymlinkedDestination() throws {
        let elsewhere = fm.temporaryDirectory.appendingPathComponent("dustbunny-elsewhere-\(UUID().uuidString)")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: elsewhere) }
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Screenshots"), withDestinationURL: elsewhere)
        try touch("Screenshot 2026-10-11 at 18.04.12.png")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertTrue(report.moves.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(exists("Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    func testUndoRestoresAndCleansUpEmptyFolders() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        let sweeper = Sweeper()
        let report = sweeper.sweep(folder: folder)

        let undo = sweeper.undo(report.moves, in: folder)

        XCTAssertEqual(undo.moves.count, 1)
        XCTAssertTrue(exists("Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertFalse(exists("Screenshots"))
    }

    func testUndoKeepsFoldersThatStillHaveFiles() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        let sweeper = Sweeper()
        let report = sweeper.sweep(folder: folder)
        try touch("Screenshots/2026-10-11/mine.txt")

        _ = sweeper.undo(report.moves, in: folder)

        XCTAssertTrue(exists("Screenshots/2026-10-11/mine.txt"))
    }

    func testUndoRejectsTamperedRecords() throws {
        try touch("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png")
        try touch("Screenshots/Documents/Screenshot 2026-10-11 at 18.04.12.png")
        try touch("Screenshots/2026-10-11/passwords.txt")
        let tampered = [
            Move(originalName: "Screenshot 2026-10-11 at 18.04.12.png", day: "../Documents", sweptName: "x.png"),
            Move(originalName: "Screenshot 2026-10-11 at 18.04.12.png", day: "Documents", sweptName: "Screenshot 2026-10-11 at 18.04.12.png"),
            Move(originalName: "Screenshot 2026-10-11 at 18.04.12.png", day: "2026-10-11", sweptName: "../../passwords.txt"),
            Move(originalName: "Screenshot 2026-10-11 at 18.04.12.png", day: "2026-10-11", sweptName: "passwords.txt"),
            Move(originalName: "../../evil.png", day: "2026-10-11", sweptName: "Screenshot 2026-10-11 at 18.04.12.png"),
            Move(originalName: "Screenshot 2026-10-10 at 18.04.12.png", day: "2026-10-11", sweptName: "Screenshot 2026-10-11 at 18.04.12.png"),
        ]

        let undo = Sweeper().undo(tampered, in: folder)

        XCTAssertTrue(undo.moves.isEmpty)
        XCTAssertEqual(undo.failures.count, tampered.count)
        XCTAssertTrue(exists("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(exists("Screenshots/Documents/Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(exists("Screenshots/2026-10-11/passwords.txt"))
    }

    func testUndoRefusesFolderSwappedForSymlink() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        let sweeper = Sweeper()
        let report = sweeper.sweep(folder: folder)

        let elsewhere = fm.temporaryDirectory.appendingPathComponent("dustbunny-swap-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: elsewhere) }
        try fm.moveItem(at: folder.appendingPathComponent("Screenshots"), to: elsewhere)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Screenshots"), withDestinationURL: elsewhere)

        let undo = sweeper.undo(report.moves, in: folder)

        XCTAssertTrue(undo.moves.isEmpty)
        XCTAssertEqual(undo.remaining, report.moves)
        XCTAssertFalse(exists("Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.appendingPathComponent("2026-10-11/Screenshot 2026-10-11 at 18.04.12.png").path))
    }

    func testUndoKeepsFailedMovesUndoable() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        let sweeper = Sweeper()
        let report = sweeper.sweep(folder: folder)
        try touch("Screenshot 2026-10-11 at 18.04.12.png", "a new file with the same name")

        let undo = sweeper.undo(report.moves, in: folder)

        XCTAssertTrue(undo.moves.isEmpty)
        XCTAssertEqual(undo.remaining, report.moves)
        XCTAssertTrue(exists("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png"))
    }

    func testRefusesSymlinkedDayFolder() throws {
        let elsewhere = fm.temporaryDirectory.appendingPathComponent("dustbunny-day-\(UUID().uuidString)")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: elsewhere) }
        try fm.createDirectory(at: folder.appendingPathComponent("Screenshots"), withIntermediateDirectories: false)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Screenshots/2026-10-11"), withDestinationURL: elsewhere)
        try touch("Screenshot 2026-10-11 at 18.04.12.png")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertTrue(report.moves.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(exists("Screenshot 2026-10-11 at 18.04.12.png"))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    func testRefusesFileWhereFolderShouldBe() throws {
        try touch("Screenshots", "not a folder")
        try touch("Screenshot 2026-10-11 at 18.04.12.png")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertTrue(report.moves.isEmpty)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Screenshots"), encoding: .utf8), "not a folder")
    }

    func testCreatedFoldersArePrivate() throws {
        try touch("Screenshot 2026-10-11 at 18.04.12.png")
        _ = Sweeper().sweep(folder: folder)

        for path in ["Screenshots", "Screenshots/2026-10-11"] {
            let attributes = try fm.attributesOfItem(atPath: folder.appendingPathComponent(path).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700, path)
        }
    }

    /// The sweep only needs the *folder* to be writable. A file nobody can read still moves,
    /// which shows its contents are never opened.
    func testMovesFilesItCannotRead() throws {
        let file = try touch("Screenshot 2026-10-11 at 18.04.12.png")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

        let report = Sweeper().sweep(folder: folder)

        XCTAssertEqual(report.moves.count, 1)
        XCTAssertTrue(exists("Screenshots/2026-10-11/Screenshot 2026-10-11 at 18.04.12.png"))
    }

    func testLeavesInProgressHiddenScreenshotsAlone() throws {
        try touch(".Screenshot 2026-10-11 at 18.04.12.png")

        let report = Sweeper().sweep(folder: folder)

        XCTAssertTrue(report.moves.isEmpty)
        XCTAssertTrue(exists(".Screenshot 2026-10-11 at 18.04.12.png"))
    }
}

final class MatcherFuzzTests: XCTestCase {
    func testRandomNamesNeverCrashAndOnlyWellFormedOnesMatch() {
        var rng = SystemRandomNumberGenerator()
        let alphabet = Array("Screnshot SRcdig0123456789-.:/ atpngmovPNG\u{202F}\u{0}\u{FFFD}é😀()")
        let seeds = ["Screenshot 2026-10-11 at 18.04.12.png", "Screenshot 2026-10-11 at 1.jpg", "Screen Shot 2020-01-02 at 9.png"]

        for i in 0..<20_000 {
            var chars = Array(seeds[i % seeds.count])
            for _ in 0..<Int.random(in: 0...4, using: &rng) where !chars.isEmpty {
                let at = Int.random(in: 0..<chars.count, using: &rng)
                switch Int.random(in: 0...2, using: &rng) {
                case 0: chars[at] = alphabet.randomElement(using: &rng)!
                case 1: chars.remove(at: at)
                default: chars.insert(alphabet.randomElement(using: &rng)!, at: at)
                }
            }
            let name = String(chars)
            guard let day = ScreenshotMatcher.captureDay(forFileName: name) else { continue }
            XCTAssertFalse(name.contains("/"), name)
            XCTAssertFalse(name.hasPrefix("."), name)
            XCTAssertTrue(day.range(of: #"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$"#, options: .regularExpression) != nil, day)
            XCTAssertTrue(name.contains(" \(day) at "), name)
        }
    }
}
