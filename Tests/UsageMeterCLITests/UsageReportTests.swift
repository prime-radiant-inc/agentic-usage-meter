import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterCLI

@Suite
struct UsageReportTests {
  @Test
  func ordersAccountsByCatalogThenDisplayOrder() {
    let report = UsageReport(state: StateFixture.populatedState())

    #expect(
      report.accounts.map(\.providerDisplayName) == [
        "Claude", "Claude", "Codex", "Kimi",
      ]
    )
    #expect(
      report.accounts.map(\.displayName) == [
        "Work", "Personal", "Personal", "Kimi",
      ]
    )
  }

  @Test
  func ordersWindowsByAscendingDuration() {
    let report = UsageReport(state: StateFixture.populatedState())

    #expect(report.accounts[0].windows.map(\.id) == ["short", "weekly"])
  }

  @Test
  func carriesTheAuthenticatedIdentityWhenPresent() {
    let report = UsageReport(state: StateFixture.populatedState())

    #expect(report.accounts[0].identity == "harper@example.com")
    #expect(report.accounts[1].identity == nil)
  }

  @Test
  func representsAnAccountWithNoSnapshotAsEmpty() {
    let personal = UsageReport(
      state: StateFixture.populatedState()
    ).accounts[1]

    #expect(personal.displayName == "Personal")
    #expect(personal.snapshot == nil)
    #expect(personal.fetchedAt == nil)
    #expect(personal.windows.isEmpty)
    #expect(personal.balances.isEmpty)
  }

  @Test
  func tightestPicksTheLeastRemainingWindow() throws {
    let report = UsageReport(state: StateFixture.populatedState())
    let tightest = try #require(report.tightest)

    #expect(tightest.account.providerDisplayName == "Codex")
    #expect(tightest.window.id == "weekly")
    #expect(tightest.window.consumedFraction == 0.78)
  }

  @Test
  func tightestBreaksATieBySoonestReset() throws {
    let tightest = try #require(
      UsageReport(state: StateFixture.tiedState()).tightest
    )

    #expect(tightest.account.providerDisplayName == "Codex")
  }

  @Test
  func tightestIsNilWithoutAnyWindows() {
    #expect(UsageReport(state: StateFixture.emptyState()).tightest == nil)
  }

  @Test
  func emptyStateProducesNoAccounts() {
    #expect(UsageReport(state: StateFixture.emptyState()).accounts.isEmpty)
  }
}
