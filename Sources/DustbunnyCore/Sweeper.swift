import Darwin
import Foundation

/// One file that was moved. Stored as bare names (never paths) so an undo record can only ever
/// describe `<folder>/<originalName>` ↔ `<folder>/Screenshots/<day>/<sweptName>`.
public struct Move: Codable, Equatable, Sendable {
    public let originalName: String
    public let day: String
    public let sweptName: String

    public init(originalName: String, day: String, sweptName: String) {
        self.originalName = originalName
        self.day = day
        self.sweptName = sweptName
    }
}

public struct SweepReport: Sendable {
    public var moves: [Move] = []
    public var failures: [String] = []
    /// Undo only: moves that couldn't be reversed and should stay undoable.
    public var remaining: [Move] = []

    public init() {}
}

public enum SweepError: LocalizedError {
    case notADirectory(String)
    case tooManyDuplicates(String)
    case posix(Int32)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let name): return "“\(name)” exists but is not a normal folder"
        case .tooManyDuplicates(let name): return "too many files already named “\(name)”"
        case .posix(let code): return String(cString: strerror(code))
        }
    }
}

/// Moves screenshots from a folder into `<folder>/Screenshots/<YYYY-MM-DD>/`.
///
/// Safety properties:
/// - Only directory entries and file names are inspected. Files themselves are never opened.
/// - Only regular files directly inside the folder are considered. Symlinks, folders and hidden files are skipped.
/// - All work happens relative to directory handles opened with `O_NOFOLLOW`, so swapping a folder for a
///   symlink mid-sweep can't redirect a move anywhere else.
/// - Moves use `renameatx_np(RENAME_EXCL)`: atomic, same-volume only, and never overwrite an existing file.
/// - Nothing is ever deleted. Undo only removes day folders that are empty.
/// - Folders Dustbunny creates are private to the user (0700).
public struct Sweeper {
    public static let destinationFolderName = "Screenshots"

    public init() {}

    public func sweep(folder: URL) -> SweepReport {
        var report = SweepReport()

        // The folder itself was chosen by the user, so following a symlink to it is fine.
        let folderFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folderFD >= 0 else {
            report.failures.append("Couldn't open “\(folder.lastPathComponent)”: \(SweepError.posix(errno).localizedDescription)")
            return report
        }
        defer { close(folderFD) }

        let names: [String]
        do {
            names = try listNames(folderFD)
        } catch {
            report.failures.append("Couldn't list “\(folder.lastPathComponent)”: \(error.localizedDescription)")
            return report
        }

        var rootFD: Int32 = -1
        var dayFDs: [String: Int32] = [:]
        defer {
            dayFDs.values.forEach { close($0) }
            if rootFD >= 0 { close(rootFD) }
        }

        for name in names.sorted() {
            guard let day = ScreenshotMatcher.captureDay(forFileName: name),
                  isRegularFile(name, in: folderFD)
            else { continue }

            do {
                if rootFD < 0 { rootFD = try openOrCreateSubfolder(Self.destinationFolderName, in: folderFD) }
                let dayFD: Int32
                if let existing = dayFDs[day] {
                    dayFD = existing
                } else {
                    dayFD = try openOrCreateSubfolder(day, in: rootFD)
                    dayFDs[day] = dayFD
                }
                let sweptName = try moveWithoutOverwriting(name, from: folderFD, into: dayFD)
                report.moves.append(Move(originalName: name, day: day, sweptName: sweptName))
            } catch {
                report.failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Puts files back where they came from. Every record is re-validated, so a tampered undo record
    /// can't be used to move anything that isn't a screenshot sitting in a Dustbunny day folder.
    public func undo(_ moves: [Move], in folder: URL) -> SweepReport {
        var report = SweepReport()

        let folderFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folderFD >= 0 else {
            report.failures.append("Couldn't open “\(folder.lastPathComponent)”: \(SweepError.posix(errno).localizedDescription)")
            report.remaining = moves
            return report
        }
        defer { close(folderFD) }

        let rootFD = openat(folderFD, Self.destinationFolderName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else {
            report.failures.append("“\(Self.destinationFolderName)” folder is missing or not a normal folder")
            report.remaining = moves
            return report
        }
        defer { close(rootFD) }

        var touchedDays = Set<String>()
        for move in moves.reversed() {
            guard Self.isValid(move) else {
                report.failures.append("\(move.originalName): not a valid Dustbunny undo record")
                continue
            }
            let dayFD = openat(rootFD, move.day, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dayFD >= 0 else {
                report.failures.append("\(move.originalName): its day folder is missing or not a normal folder")
                report.remaining.append(move)
                continue
            }
            defer { close(dayFD) }

            guard isRegularFile(move.sweptName, in: dayFD) else {
                report.failures.append("\(move.originalName): no longer in \(Self.destinationFolderName)/\(move.day)")
                continue
            }
            if renameatx_np(dayFD, move.sweptName, folderFD, move.originalName, UInt32(RENAME_EXCL)) == 0 {
                report.moves.append(move)
                touchedDays.insert(move.day)
            } else {
                let code = errno
                let reason = code == EEXIST ? "a file with that name is already back in place" : SweepError.posix(code).localizedDescription
                report.failures.append("\(move.originalName): \(reason)")
                report.remaining.append(move)
            }
        }

        // AT_REMOVEDIR only succeeds on empty folders, so this can never remove anything the user put there.
        for day in touchedDays { unlinkat(rootFD, day, AT_REMOVEDIR) }
        if !touchedDays.isEmpty { unlinkat(folderFD, Self.destinationFolderName, AT_REMOVEDIR) }
        report.remaining.reverse() // back to sweep order
        return report
    }

    /// Both names must be screenshot names from the same day as the folder they're filed under.
    static func isValid(_ move: Move) -> Bool {
        ScreenshotMatcher.captureDay(forFileName: move.originalName) == move.day
            && ScreenshotMatcher.captureDay(forFileName: move.sweptName) == move.day
    }

    // MARK: Low-level helpers

    private func listNames(_ folderFD: Int32) throws -> [String] {
        let dupFD = dup(folderFD)
        guard dupFD >= 0, let dir = fdopendir(dupFD) else {
            let code = errno
            if dupFD >= 0 { close(dupFD) }
            throw SweepError.posix(code)
        }
        defer { closedir(dir) }

        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(validatingCString: $0) }
            }
            // Names that aren't valid UTF-8 can't be screenshots; skip them rather than mangle them.
            if let name { names.append(name) }
        }
        return names
    }

    /// Reads the directory entry's metadata (not the file) without following symlinks.
    private func isRegularFile(_ name: String, in folderFD: Int32) -> Bool {
        var info = stat()
        guard fstatat(folderFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return false }
        return info.st_mode & S_IFMT == S_IFREG
    }

    /// Creates `name` if needed and opens it, refusing symlinks and anything that isn't a folder.
    private func openOrCreateSubfolder(_ name: String, in parentFD: Int32) throws -> Int32 {
        if mkdirat(parentFD, name, 0o700) != 0, errno != EEXIST {
            throw SweepError.posix(errno)
        }
        let fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            let code = errno
            throw code == ELOOP || code == ENOTDIR ? SweepError.notADirectory(name) : SweepError.posix(code)
        }
        return fd
    }

    private func moveWithoutOverwriting(_ name: String, from sourceFD: Int32, into folderFD: Int32) throws -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        for attempt in 1...999 {
            let candidate = attempt == 1 ? name : "\(base) (\(attempt))" + (ext.isEmpty ? "" : ".\(ext)")
            if renameatx_np(sourceFD, name, folderFD, candidate, UInt32(RENAME_EXCL)) == 0 {
                return candidate
            }
            let code = errno
            if code != EEXIST { throw SweepError.posix(code) }
        }
        throw SweepError.tooManyDuplicates(name)
    }
}
