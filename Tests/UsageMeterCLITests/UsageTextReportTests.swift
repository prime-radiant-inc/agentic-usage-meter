import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterCLI

@Suite
struct UsageTextReportTests {
  private let now = StateFixture.referenceDate

  @Test
  func rendersAlignedColumnsWithABalanceBlock() {
    let table = UsageTextReport.table(
      UsageReport(state: StateFixture.populatedState()),
      now: now
    )

    #expect(
      table == """
        PROVIDER  ACCOUNT   WINDOW  USED  RESETS
        Claude    Work      short    61%  2h 14m
        Claude    Work      weekly   44%  3d 6h
        Claude    Personal  —          —  —
        Codex     Personal  weekly   78%  5d 1h
        Kimi      Kimi      weekly   26%  5d 18h

        Claude/Work  Extra usage: 38.42 USD
        Codex/Personal  Credits: unlimited
        Kimi/Kimi  Extra usage: disabled
        """
    )
  }

  @Test
  func widensColumnsToFitALongDisplayName() {
    let table = UsageTextReport.table(
      UsageReport(state: StateFixture.longDisplayNameState()),
      now: now
    )

    #expect(
      table == """
        PROVIDER  ACCOUNT                     WINDOW  USED  RESETS
        Claude    Anvil Platform Engineering  weekly    5%  3d 6h
        Codex     Me                          short   100%  42m
        """
    )
  }

  @Test
  func rendersNothingWithoutAccounts() {
    #expect(
      UsageTextReport.table(
        UsageReport(state: StateFixture.emptyState()),
        now: now
      ) == ""
    )
  }

  @Test
  func noLineHasTrailingWhitespace() {
    let table = UsageTextReport.table(
      UsageReport(state: StateFixture.populatedState()),
      now: now
    )

    for line in table.split(separator: "\n") {
      #expect(!line.hasSuffix(" "))
    }
  }

  @Test
  func tightestLineNamesTheAccountPercentAndReset() {
    #expect(
      UsageTextReport.tightestLine(
        UsageReport(state: StateFixture.populatedState()),
        now: now
      ) == "Codex/Personal 78% used · resets in 5d 1h"
    )
  }

  @Test
  func tightestLineIsEmptyWithoutData() {
    #expect(
      UsageTextReport.tightestLine(
        UsageReport(state: StateFixture.emptyState()),
        now: now
      ) == ""
    )
  }

  @Test
  func tightestLineOmitsTheResetClauseWhenTheWindowHasNoResetTime() {
    #expect(
      UsageTextReport.tightestLine(
        UsageReport(state: StateFixture.windowWithoutAResetState()),
        now: now
      ) == "Claude/Work 0% used"
    )
  }

  @Test
  func tightestLineOmitsAnIdentityTheAccountActuallyHas() {
    let line = UsageTextReport.tightestLine(
      UsageReport(state: StateFixture.identifiedAccountIsTightestState()),
      now: now
    )

    #expect(line == "Claude/Work 61% used · resets in 2h 14m")
    #expect(!line.contains("harper@example.com"))
  }

  @Test
  func formatsRelativeDurations() {
    #expect(UsageTextReport.relativeDuration(from: now, to: nil) == "—")
    #expect(
      UsageTextReport.relativeDuration(
        from: now,
        to: now.addingTimeInterval(-60)
      ) == "now"
    )
    #expect(
      UsageTextReport.relativeDuration(
        from: now,
        to: now.addingTimeInterval(2_520)
      ) == "42m"
    )
    #expect(
      UsageTextReport.relativeDuration(
        from: now,
        to: now.addingTimeInterval(8_040)
      ) == "2h 14m"
    )
    #expect(
      UsageTextReport.relativeDuration(
        from: now,
        to: now.addingTimeInterval(280_800)
      ) == "3d 6h"
    )
  }
}
