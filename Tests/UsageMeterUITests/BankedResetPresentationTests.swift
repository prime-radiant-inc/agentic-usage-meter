import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Suite
struct BankedResetPresentationTests {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  @Test
  func expiredGrantsDisappearAndRemainingGrantsSortByExpiry() throws {
    let account = SubscriptionAccount(provider: .claude, displayName: "Personal", displayOrder: 0)
    let resets = BankedResets(
      availableCount: 4, applicableCount: 2,
      grants: [
        grant("later", count: 2, expiry: now.addingTimeInterval(7200)),
        grant("expired", expiry: now),
        grant("sooner", expiry: now.addingTimeInterval(3600)),
      ])
    let row = BankedResetRowPresentation(
      account: account, resets: resets, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(row.availableCount == 3)
    #expect(row.grants?.map(\.id) == ["sooner", "later"])
    #expect(row.grants?.last?.remainingCount == 2)
    #expect(row.grants?.first?.scopeText == "Five-hour session")
    #expect(row.grants?.first?.expiryText.contains("2033") == true)
  }

  @Test
  func unavailableDetailsKeepTheKnownCountAndDifferFromAnEmptyBank() {
    let account = SubscriptionAccount(provider: .codex, displayName: "Work", displayOrder: 0)
    let row = BankedResetRowPresentation(
      account: account, resets: BankedResets(availableCount: 2, applicableCount: 0, grants: nil),
      now: now
    )
    #expect(row.availableCount == 2)
    #expect(row.grants == nil)
    #expect(row.applicableCount == 0)
    let empty = BankedResetRowPresentation(
      account: account, resets: BankedResets(availableCount: 0, applicableCount: 0, grants: []),
      now: now
    )
    #expect(empty.grants == [])
  }

  @Test
  func unknownExpiryIsExplicitAndDoesNotSortAheadOfExpiringResets() {
    let account = SubscriptionAccount(provider: .codex, displayName: "Work", displayOrder: 0)
    let row = BankedResetRowPresentation(
      account: account,
      resets: BankedResets(
        availableCount: 2, applicableCount: nil,
        grants: [
          grant("unknown", expiry: nil), grant("dated", expiry: now.addingTimeInterval(3600)),
        ]), now: now
    )
    #expect(row.grants?.map(\.id) == ["dated", "unknown"])
    #expect(row.grants?.last?.expiryText == "Expiry not reported")
  }

  private func grant(_ id: String, count: Int = 1, expiry: Date?) -> BankedReset {
    BankedReset(
      id: id, title: "Session reset", remainingCount: count, expiresAt: expiry,
      scopes: ["five_hour"], availability: .banked)
  }
}
