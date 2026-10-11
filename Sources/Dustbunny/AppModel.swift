import AppKit
import DustbunnyCore
import ServiceManagement

/// App state. Everything is stored locally in the app's sandboxed UserDefaults; nothing leaves the Mac.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private enum Key {
        static let folderBookmark = "folderBookmark"
        static let scheduleEnabled = "scheduleEnabled"
        static let scheduleHour = "scheduleHour"
        static let scheduleMinute = "scheduleMinute"
        static let showAnimation = "showAnimation"
        static let lastMoves = "lastMoves"
        static let lastRunDate = "lastRunDate"
        static let lastRunCount = "lastRunCount"
        static let lastRunFailures = "lastRunFailures"
    }

    private enum Trigger { case manual, scheduled }

    private let defaults = UserDefaults.standard
    private let scheduler: Scheduler

    @Published private(set) var folderURL: URL?
    @Published private(set) var isRunning = false
    @Published private(set) var canUndo = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var statusLine = ""
    @Published var errorMessage: String?

    @Published var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: Key.scheduleEnabled); applySchedule() }
    }
    @Published var scheduleTime: Date {
        didSet {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
            defaults.set(parts.hour ?? 18, forKey: Key.scheduleHour)
            defaults.set(parts.minute ?? 0, forKey: Key.scheduleMinute)
            applySchedule()
        }
    }
    @Published var showAnimation: Bool {
        didSet { defaults.set(showAnimation, forKey: Key.showAnimation) }
    }

    private init() {
        defaults.register(defaults: [
            Key.scheduleEnabled: true,
            Key.scheduleHour: 18,
            Key.scheduleMinute: 0,
            Key.showAnimation: true,
        ])
        scheduler = Scheduler(defaults: defaults)
        scheduleEnabled = defaults.bool(forKey: Key.scheduleEnabled)
        scheduleTime = Calendar.current.date(
            bySettingHour: defaults.integer(forKey: Key.scheduleHour),
            minute: defaults.integer(forKey: Key.scheduleMinute), second: 0, of: Date()
        ) ?? Date()
        showAnimation = defaults.bool(forKey: Key.showAnimation)
        canUndo = !loadLastMoves().isEmpty
        folderURL = resolveBookmark()
        refreshStatusLine()
    }

    func start() {
        scheduler.onFire = { [weak self] in self?.sweep(.scheduled) }
        scheduler.configure(enabled: scheduleEnabled && folderURL != nil, time: scheduleTime, skipMissedToday: false)
        scheduler.start()
        if folderURL == nil { SettingsWindow.show(self) }
    }

    var scheduleLine: String {
        guard scheduleEnabled else { return "Automatic sweeping is off" }
        return "Sweeps every day at \(scheduleTime.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Sweeping

    func runNow() { sweep(.manual) }

    private func sweep(_ trigger: Trigger) {
        guard !isRunning, let folder = folderURL else { return }
        isRunning = true

        Task {
            let report = await Task.detached(priority: .utility) {
                Self.withAccess(to: folder) {
                    Sweeper().sweep(folder: folder)
                }
            }.value

            if !report.moves.isEmpty {
                saveLastMoves(report.moves)
            }
            defaults.set(Date(), forKey: Key.lastRunDate)
            defaults.set(report.moves.count, forKey: Key.lastRunCount)
            defaults.set(report.failures.count, forKey: Key.lastRunFailures)
            refreshStatusLine()
            isRunning = false

            if showAnimation, trigger == .manual || !report.moves.isEmpty {
                VacuumOverlay.show(count: report.moves.count)
            }
            if !report.failures.isEmpty, trigger == .manual {
                errorMessage = report.failures.prefix(5).joined(separator: "\n")
                SettingsWindow.show(self)
            }
        }
    }

    func undoLastSweep() {
        guard !isRunning, let folder = folderURL else { return }
        let moves = loadLastMoves()
        guard !moves.isEmpty else { return }

        let report = Self.withAccess(to: folder) { Sweeper().undo(moves, in: folder) }
        saveLastMoves(report.remaining) // anything that couldn't go back stays undoable
        statusLine = "Put back \(Self.count(report.moves.count))"
        if !report.failures.isEmpty {
            errorMessage = "Some files couldn't be put back:\n" + report.failures.prefix(5).joined(separator: "\n")
            SettingsWindow.show(self)
        }
    }

    private nonisolated static func withAccess<T>(to folder: URL, _ body: () -> T) -> T {
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        return body()
    }

    private func loadLastMoves() -> [Move] {
        guard let data = defaults.data(forKey: Key.lastMoves) else { return [] }
        return (try? JSONDecoder().decode([Move].self, from: data)) ?? []
    }

    private func saveLastMoves(_ moves: [Move]) {
        if moves.isEmpty {
            defaults.removeObject(forKey: Key.lastMoves)
        } else if let data = try? JSONEncoder().encode(moves) {
            defaults.set(data, forKey: Key.lastMoves)
        }
        canUndo = !moves.isEmpty
    }

    private func refreshStatusLine() {
        guard let date = defaults.object(forKey: Key.lastRunDate) as? Date else {
            statusLine = "Hasn't swept yet"
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        var line = "Last sweep: \(Self.count(defaults.integer(forKey: Key.lastRunCount))), \(formatter.string(from: date))"
        let failures = defaults.integer(forKey: Key.lastRunFailures)
        if failures > 0 { line += " (\(failures) skipped)" }
        statusLine = line
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 screenshot" : "\(n) screenshots"
    }

    // MARK: Folder access

    /// The sandbox only lets Dustbunny touch a folder the user picks here.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = folderURL ?? Self.realDesktopURL
        panel.prompt = "Allow Access"
        panel.message = "Choose the folder Dustbunny should tidy (usually your Desktop). Dustbunny only reads file names here, never file contents."

        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: Key.folderBookmark)
            folderURL = url
            saveLastMoves([]) // undo records belong to the previous folder
            errorMessage = nil
            applySchedule()
        } catch {
            errorMessage = "Couldn't save access to that folder: \(error.localizedDescription)"
        }
    }

    private func resolveBookmark() -> URL? {
        guard let data = defaults.data(forKey: Key.folderBookmark) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = Self.withAccess(to: url, { try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }) {
            defaults.set(fresh, forKey: Key.folderBookmark)
        }
        return url
    }

    /// Inside the sandbox, FileManager's home directory points at the app container, so look up the real one.
    private static var realDesktopURL: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Desktop", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: Schedule & login

    private func applySchedule() {
        // Changing settings never triggers an immediate catch-up sweep for a time that already passed today.
        scheduler.configure(enabled: scheduleEnabled && folderURL != nil, time: scheduleTime, skipMissedToday: true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't change the login setting: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
