/// Exponential back-off for failed unlock attempts. Pure logic so it is
/// unit-testable; persistence is handled by the caller.
class LockoutPolicy {
  const LockoutPolicy({
    this.freeAttempts = 3,
    this.maxDelay = const Duration(hours: 1),
  });

  final int freeAttempts;
  final Duration maxDelay;

  /// Delay to impose after [failedAttempts] consecutive failures.
  Duration delayFor(int failedAttempts) {
    if (failedAttempts < freeAttempts) return Duration.zero;
    final exp = failedAttempts - freeAttempts; // 0,1,2...
    if (exp > 10) return maxDelay;
    final d = Duration(seconds: 30 * (1 << exp));
    return d > maxDelay ? maxDelay : d;
  }

  /// Time left until the next attempt is allowed, or null if allowed now.
  Duration? remaining(DateTime? lockedUntil, DateTime now) {
    if (lockedUntil == null) return null;
    final left = lockedUntil.difference(now);
    return left.isNegative || left == Duration.zero ? null : left;
  }
}
