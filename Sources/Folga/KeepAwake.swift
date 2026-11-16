import Foundation
import IOKit.pwr_mgt

/// Keeps the display (and so the screen lock) from kicking in for a while.
@MainActor
final class KeepAwake: ObservableObject {
    static let steps = [30] + Array(1...24).map { $0 * 60 }   // minutes
    static let maxMinutes = 24 * 60

    @Published private(set) var isOn = false
    @Published private(set) var endsAt: Date?
    /// What the menu bar shows while on: "2h15", "29m", "40s".
    @Published private(set) var compactRemaining = ""
    /// Chosen length in minutes. While on, the countdown runs from `startedAt`.
    @Published private(set) var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: "awakeMinutes") }
    }
    private var startedAt = Date.now

    private var displayAssertion: IOPMAssertionID = 0
    private var activityAssertion: IOPMAssertionID = 0
    private var ticker: Timer?
    private var endTimer: Timer?
    private var clock: Timer?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "awakeMinutes")
        minutes = saved == 0 ? 60 : min(max(saved, 30), Self.maxMinutes)
    }

    func setOn(_ on: Bool) {
        on ? start() : stop()
    }

    /// Slider: snaps to 30min, 1h, 2h … 24h. While on, the new length counts from now.
    func choose(_ value: Int) {
        let snapped = Self.steps.min { abs($0 - value) < abs($1 - value) } ?? 60
        guard snapped != minutes else { return }
        minutes = snapped
        if isOn { startedAt = .now; schedule() }
    }

    /// On: 30 more minutes. Off: stay awake for the next 30 minutes.
    func addHalfHour() {
        if isOn {
            minutes = min(minutes + 30, Self.maxMinutes)
            schedule()
        } else {
            minutes = 30
            start()
        }
    }

    /// Counter back to 30 min, starting over from now.
    func reset() {
        minutes = 30
        if isOn { startedAt = .now; schedule() }
    }

    // MARK: - Power management

    private func start() {
        startedAt = .now
        if displayAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Folga: manter a tela acordada" as CFString, &displayAssertion)
        }
        isOn = true
        schedule()
    }

    private func stop() {
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        if activityAssertion != 0 { IOPMAssertionRelease(activityAssertion); activityAssertion = 0 }
        ticker?.invalidate(); ticker = nil
        endTimer?.invalidate(); endTimer = nil
        clock?.invalidate(); clock = nil
        compactRemaining = ""
        isOn = false
        endsAt = nil
    }

    private func schedule() {
        endsAt = startedAt.addingTimeInterval(Double(minutes) * 60)
        ticker?.invalidate()
        pokeActivity()
        // Also tell the system the user is "active" so the screen saver and its lock stay away.
        ticker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        updateCompact()
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCompact() }
            }
        }
        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: max(endsAt!.timeIntervalSinceNow, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// Only publishes when the text changes, so the menu bar redraws once a minute.
    private func updateCompact() {
        guard let end = endsAt else { return }
        let text = Self.compact(Int(end.timeIntervalSinceNow.rounded(.up)))
        if text != compactRemaining { compactRemaining = text }
    }

    static func compact(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        if s < 60 { return "\(s)s" }
        let minutes = Int((Double(s) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h" + String(format: "%02d", m)
    }

    private func tick() {
        guard let end = endsAt, end > .now else { stop(); return }
        pokeActivity()
    }

    private func pokeActivity() {
        IOPMAssertionDeclareUserActivity("Folga: manter acordado (atividade)" as CFString,
                                         kIOPMUserActiveLocal, &activityAssertion)
    }
}
