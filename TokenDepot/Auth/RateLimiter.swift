import Foundation

/// Exponential backoff rate limiter for password attempts.
/// - Attempts 1-2: instant
/// - Attempt 3: 30s
/// - Attempt 4: 2min
/// - Attempt 5: 8min
/// - Attempt 6+: 30min (cap)
final class RateLimiter {

    private var failedAttempts: Int = 0
    private var lockedUntil: Date?

    private let freeAttempts = 2
    private let maxLockDuration: TimeInterval = 1800  // 30 minutes cap

    // MARK: — State

    var isLocked: Bool {
        guard let until = lockedUntil else { return false }
        return Date() < until
    }

    var remainingLockSeconds: Int {
        guard let until = lockedUntil else { return 0 }
        return max(0, Int(until.timeIntervalSinceNow))
    }

    var attemptCount: Int { failedAttempts }

    // MARK: — Actions

    /// Call before allowing a password attempt.
    /// Returns true if attempt is allowed, false if locked.
    func canAttempt() -> Bool {
        if isLocked { return false }
        return true
    }

    /// Call after a failed attempt. Sets the lockout timer if needed.
    func recordFailure() {
        failedAttempts += 1

        let lockDuration = backoffDuration(for: failedAttempts)
        if lockDuration > 0 {
            lockedUntil = Date().addingTimeInterval(lockDuration)
        }
    }

    /// Call after a successful attempt. Resets everything.
    func recordSuccess() {
        failedAttempts = 0
        lockedUntil = nil
    }

    // MARK: — Private

    private func backoffDuration(for attempt: Int) -> TimeInterval {
        guard attempt > freeAttempts else { return 0 }

        let extra = attempt - freeAttempts  // 1-based extra attempts
        switch extra {
        case 1: return 30          // 30 seconds
        case 2: return 120         // 2 minutes
        case 3: return 480         // 8 minutes
        default: return maxLockDuration   // 30 minutes, capped
        }
    }
}
