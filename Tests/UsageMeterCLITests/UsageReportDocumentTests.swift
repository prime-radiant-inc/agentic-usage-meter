import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterCLI

@Suite
struct UsageReportDocumentTests {
  @Test
  func matchesTheGoldenSchemaOneFixture() throws {
    let document = UsageReportDocument(
      report: UsageReport(state: StateFixture.populatedState()),
      generatedAt: StateFixture.referenceDate
    )
    let url = try #require(
      Bundle.module.url(
        forResource: "usage-report-v1",
        withExtension: "json",
        subdirectory: "Fixtures"
      )
    )

    #expect(
      try UsageReportDocument.encoder().encode(document)
        == Data(contentsOf: url)
    )
  }

  @Test
  func statesTheSchemaVersion() {
    let document = UsageReportDocument(
      report: UsageReport(state: StateFixture.emptyState()),
      generatedAt: StateFixture.referenceDate
    )

    #expect(document.schemaVersion == 1)
    #expect(document.accounts.isEmpty)
  }

  @Test
  func distinguishesBalanceStates() throws {
    let document = UsageReportDocument(
      report: UsageReport(state: StateFixture.populatedState()),
      generatedAt: StateFixture.referenceDate
    )

    #expect(
      document.accounts.flatMap { $0.balances.map(\.state) }
        == ["available", "unlimited", "disabled"]
    )

    let available = try #require(document.accounts.first?.balances.first)
    #expect(available.remainingAmount == 38.42)
    #expect(available.unit == "USD")

    let unlimited = try #require(
      document.accounts
        .first(where: { $0.provider == "codex" })?
        .balances.first
    )
    #expect(unlimited.remainingAmount == nil)
    #expect(unlimited.unit == nil)
  }

  @Test
  func encodesNonNilLabelAndCycleEndsAt() throws {
    let document = UsageReportDocument(
      report: UsageReport(
        state: StateFixture.namedWindowWithRenewingBalanceState()
      ),
      generatedAt: StateFixture.referenceDate
    )
    let data = try UsageReportDocument.encoder().encode(document)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(UsageReportDocument.self, from: data)

    let window = try #require(decoded.accounts.first?.windows.first)
    #expect(window.label == "Grace period")

    let balance = try #require(decoded.accounts.first?.balances.first)
    #expect(
      balance.cycleEndsAt
        == StateFixture.referenceDate.addingTimeInterval(604_800)
    )
  }

  @Test
  func roundTripsThroughDecoding() throws {
    let document = UsageReportDocument(
      report: UsageReport(state: StateFixture.populatedState()),
      generatedAt: StateFixture.referenceDate
    )
    let data = try UsageReportDocument.encoder().encode(document)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    #expect(
      try decoder.decode(UsageReportDocument.self, from: data)
        == document
    )
  }
}
