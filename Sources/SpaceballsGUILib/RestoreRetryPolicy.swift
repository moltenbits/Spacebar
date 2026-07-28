import Foundation

/// Backoff schedule for automatic Space-restore retries. A restore attempted
/// right after a display reconnect can fail wholesale — Mission Control's AX
/// hierarchy is still rebuilding — and without a retry the ejected Spaces sit
/// unrestored until the next display reconfiguration event.
public struct RestoreRetryPolicy: Sendable {
  public var maxRetries: Int
  public var baseDelay: TimeInterval

  public init(maxRetries: Int = 2, baseDelay: TimeInterval = 4.0) {
    self.maxRetries = maxRetries
    self.baseDelay = baseDelay
  }

  /// Delay before the next automatic attempt, given how many attempts have
  /// already failed since the triggering reconfiguration — or nil when no
  /// retry is warranted. Doubles per failure: 4s, 8s, … up to `maxRetries`.
  public func retryDelay(afterFailedAttempts failed: Int) -> TimeInterval? {
    guard failed >= 1, failed <= maxRetries else { return nil }
    return baseDelay * TimeInterval(1 << (failed - 1))
  }
}
