import AppKit

/// Fires once per day at the chosen time. If the Mac was asleep or Dustbunny wasn't running at that
/// time, it catches up the same day (on wake or launch). Missed days are not replayed.
@MainActor
final class Scheduler {
    private static let lastFiredDayKey = "lastScheduledDay"

    var onFire: () -> Void = {}

    private let defaults: UserDefaults
    private var enabled = false
    private var hour = 18
    private var minute = 0
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let events: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (local, .NSSystemClockDidChange),
            (local, .NSSystemTimeZoneDidChange),
            (local, .NSCalendarDayChanged),
        ]
        for (center, name) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            observers.append((center, token))
        }
        evaluate()
    }

    func configure(enabled: Bool, time: Date, skipMissedToday: Bool) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        self.enabled = enabled
        hour = parts.hour ?? 18
        minute = parts.minute ?? 0
        if skipMissedToday, let today = fireDate(on: Date()), Date() >= today {
            lastFiredDay = Self.dayKey(Date())
        }
        reschedule()
    }

    private var lastFiredDay: String? {
        get { defaults.string(forKey: Self.lastFiredDayKey) }
        set { defaults.set(newValue, forKey: Self.lastFiredDayKey) }
    }

    private func evaluate() {
        let now = Date()
        if enabled, let today = fireDate(on: now), now >= today, lastFiredDay != Self.dayKey(now) {
            lastFiredDay = Self.dayKey(now)
            onFire()
        }
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard enabled,
              let next = Calendar.current.nextDate(
                  after: Date(), matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime
              )
        else { return }

        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fireDate(on day: Date) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
