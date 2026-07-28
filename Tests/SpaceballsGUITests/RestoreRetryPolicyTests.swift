import Foundation
import Testing

@testable import SpaceballsGUILib

@Suite("Restore Retry Policy")
struct RestoreRetryPolicyTests {

  @Test("Backoff doubles per failed attempt up to the retry cap")
  func backoffDoublesUpToCap() {
    let policy = RestoreRetryPolicy(maxRetries: 2, baseDelay: 4.0)
    #expect(policy.retryDelay(afterFailedAttempts: 1) == 4.0)
    #expect(policy.retryDelay(afterFailedAttempts: 2) == 8.0)
    #expect(policy.retryDelay(afterFailedAttempts: 3) == nil)
  }

  @Test("No failed attempts means no retry")
  func zeroFailuresNoRetry() {
    let policy = RestoreRetryPolicy()
    #expect(policy.retryDelay(afterFailedAttempts: 0) == nil)
  }

  @Test("Defaults allow two retries at 4s and 8s")
  func defaultsAllowTwoRetries() {
    let policy = RestoreRetryPolicy()
    #expect(policy.retryDelay(afterFailedAttempts: 1) == 4.0)
    #expect(policy.retryDelay(afterFailedAttempts: 2) == 8.0)
    #expect(policy.retryDelay(afterFailedAttempts: 3) == nil)
  }

  @Test("A zero-retry policy never retries")
  func zeroRetryPolicyNeverRetries() {
    let policy = RestoreRetryPolicy(maxRetries: 0, baseDelay: 4.0)
    #expect(policy.retryDelay(afterFailedAttempts: 1) == nil)
  }
}
