import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct BankedResetTests {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  @Test
  func codexRetainsBankedCountWhenNoneAreApplicable() throws {
    let data = try codexUsage(resets: [
      "available_count": 2, "applicable_available_count": 0,
    ])
    let snapshot = try CodexUsageDecoder().decode(data, accountID: UUID(), fetchedAt: now)
    let resets = try #require(try encodedResets(snapshot))
    #expect(resets["availableCount"] as? Int == 2)
    #expect(resets["applicableCount"] as? Int == 0)
    #expect(resets["grants"] == nil)
  }

  @Test
  func codexFetchesIndividualExpiriesWithAccountCredentials() async throws {
    let transport = ResetTransport(
      usage: try codexUsage(resets: ["available_count": 1, "applicable_available_count": 0]),
      details: Data(
        """
        {"available_count":1,"credits":[
          {"id":"unused","title":"Full reset","reset_type":"codex_rate_limits",
           "status":"available","is_supported_by_plan":true,
           "expires_at":"2033-06-01T12:00:00.123456Z"},
          {"id":"spent","title":"Full reset","reset_type":"codex_rate_limits",
           "status":"redeemed","is_supported_by_plan":true,
           "expires_at":"2033-06-01T12:00:00Z"}
        ]}
        """.utf8)
    )
    let snapshot = try await fetchCodex(transport)
    let resets = try #require(try encodedResets(snapshot))
    let grants = try #require(resets["grants"] as? [[String: Any]])
    #expect(grants.count == 1)
    #expect(grants.first?["id"] as? String == "unused")
    #expect(grants.first?["expiresAt"] != nil)
    let request = try #require(await transport.detailRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
    #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "synthetic-account")
  }

  @Test(arguments: [403, 429, 500])
  func failedCodexDetailsPreserveQuotaAndResetCount(status: Int) async throws {
    let transport = ResetTransport(
      usage: try codexUsage(resets: ["available_count": 2, "applicable_available_count": 0]),
      details: Data(), detailStatus: status
    )
    let snapshot = try await fetchCodex(transport)
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.balances.count == 1)
    let resets = try #require(try encodedResets(snapshot))
    #expect(resets["availableCount"] as? Int == 2)
    #expect(resets["grants"] == nil)
  }

  @Test
  func claudeIncludesUnusedGrantScopeAndExpiryWithoutCountingSpentGrants() throws {
    let data = Data(
      """
      {"five_hour":{"utilization":0,"resets_at":null},
       "seven_day":{"utilization":0,"resets_at":null},
       "cedar_ember":{"eligible":true,"cooldown_until":null,"grants":[
         {"id":"unused","label":"Session reset","resets_left":2,
          "starts_at":"2030-01-01T00:00:00Z","ends_at":"2033-06-01T12:00:00Z",
          "clears":["five_hour"],"paused":false,"usable_now":true,"blocking":[]},
         {"id":"spent","label":"Full reset","resets_left":0,
          "starts_at":"2030-01-01T00:00:00Z","ends_at":"2033-06-01T12:00:00Z",
          "clears":["five_hour","seven_day"],"paused":false,"usable_now":false,"blocking":[]}
       ]}}
      """.utf8)
    let snapshot = try ClaudeUsageDecoder().decode(data, accountID: UUID(), fetchedAt: now)
    let resets = try #require(try encodedResets(snapshot))
    #expect(resets["availableCount"] as? Int == 2)
    let grants = try #require(resets["grants"] as? [[String: Any]])
    #expect(grants.count == 1)
    #expect(grants[0]["remainingCount"] as? Int == 2)
    #expect(grants[0]["scopes"] as? [String] == ["five_hour"])
    #expect(grants[0]["expiresAt"] != nil)
  }

  @Test(arguments: ["null", "{}", "\"bad\"", "{\"available_count\":-1}"])
  func malformedOptionalCodexResetsDoNotDiscardUsage(value: String) throws {
    let resets = try JSONSerialization.jsonObject(
      with: Data(value.utf8), options: .fragmentsAllowed)
    let snapshot = try CodexUsageDecoder().decode(
      codexUsage(resets: resets), accountID: UUID(), fetchedAt: now
    )
    #expect(snapshot.windows.count == 2)
    #expect(try encodedResets(snapshot) == nil)
  }

  private func fetchCodex(_ transport: ResetTransport) async throws -> UsageSnapshot {
    try await CodexUsageClient(transport: transport).fetchUsage(
      accountID: UUID(),
      credential: .codex(
        OAuthCredential(accessToken: "synthetic-token", accountID: "synthetic-account")),
      now: now
    )
  }

  @Test(arguments: ["{\"credits\":null}", "{\"available_count\":1,\"credits\":[]}", "not JSON"])
  func unreadableCodexGrantListsNeverBecomeAnEmptyBank(details: String) async throws {
    let snapshot = try await fetchCodex(
      ResetTransport(
        usage: codexUsage(resets: ["available_count": 1, "applicable_available_count": 0]),
        details: Data(details.utf8)
      ))
    #expect(snapshot.bankedResets?.availableCount == 1)
    #expect(snapshot.bankedResets?.applicableCount == 0)
    #expect(snapshot.bankedResets?.grants == nil)
    #expect(snapshot.windows.count == 2)
  }

  @Test
  func codexPreservesPlanRestrictionsAndMicrosecondExpiry() throws {
    let data = Data(
      """
      {"available_count":1,"credits":[
        {"id":"reset","title":"Full reset","reset_type":"codex_rate_limits",
         "status":"available","is_supported_by_plan":false,
         "expires_at":"2033-06-01T12:00:00.123456Z"}
      ]}
      """.utf8)
    let resets = try #require(BankedResetDecoder.codexDetails(data, summary: nil, now: now))
    let grant = try #require(resets.grants?.first)
    #expect(grant.availability == .unsupportedPlan)
    let expiry = try #require(grant.expiresAt)
    #expect(abs(expiry.timeIntervalSince1970 - 2_001_240_000.123456) < 0.001)
  }

  @Test
  func claudeExcludesExpiredGrantsAndPreservesPausedGrants() throws {
    let paused = claudeGrant(id: "paused", paused: true)
    var expired = claudeGrant(id: "expired")
    expired["ends_at"] = "2031-01-01T00:00:00Z"
    let resets = try #require(
      BankedResetDecoder.claude(claudeUsage(grants: [expired, paused]), now: now))
    #expect(resets.availableCount == 1)
    #expect(resets.applicableCount == 0)
    #expect(resets.grants?.map(\.id) == ["paused"])
    #expect(resets.grants?.first?.availability == .paused)
  }

  @Test
  func claudeCooldownBlocksUsabilityWithoutRemovingTheBank() throws {
    let resets = try #require(
      BankedResetDecoder.claude(
        claudeUsage(grants: [claudeGrant(id: "reset")], cooldown: "2033-06-01T00:00:00Z"), now: now
      ))
    #expect(resets.availableCount == 1)
    #expect(resets.applicableCount == 0)
    #expect(resets.grants?.first?.availability == .cooldown)
  }

  @Test(arguments: ["resets_left", "ends_at", "blocking"])
  func malformedClaudeGrantKeepsUsageWithoutInventingAResetBalance(field: String) throws {
    var malformed = claudeGrant(id: "broken")
    malformed[field] = "invalid"
    let snapshot = try ClaudeUsageDecoder().decode(
      claudeUsage(grants: [malformed]), accountID: UUID(), fetchedAt: now
    )
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.bankedResets == nil)
  }

  @Test
  func resetGrantsSurviveSnapshotPersistence() throws {
    let snapshot = try ClaudeUsageDecoder().decode(
      claudeUsage(grants: [claudeGrant(id: "reset")]), accountID: UUID(), fetchedAt: now
    )
    let saved = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(UsageSnapshot.self, from: saved) == snapshot)
    #expect(snapshot.bankedResets?.grants?.count == 1)
  }

  private func claudeGrant(id: String, paused: Bool = false) -> [String: Any] {
    [
      "id": id, "label": "Full reset", "resets_left": 1,
      "starts_at": "2030-01-01T00:00:00Z", "ends_at": "2033-06-01T12:00:00Z",
      "clears": ["five_hour", "seven_day"], "paused": paused, "usable_now": true, "blocking": [],
    ]
  }

  private func claudeUsage(grants: [[String: Any]], cooldown: String? = nil) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "five_hour": ["utilization": 0, "resets_at": NSNull()],
      "seven_day": ["utilization": 0, "resets_at": NSNull()],
      "cedar_ember": [
        "eligible": true, "cooldown_until": cooldown as Any? ?? NSNull(), "grants": grants,
      ],
    ])
  }

  private func codexUsage(resets: Any) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: "codex-usage", withExtension: "json", subdirectory: "Fixtures")
    )
    var data = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    data["rate_limit_reset_credits"] = resets
    return try JSONSerialization.data(withJSONObject: data)
  }

  private func encodedResets(_ snapshot: UsageSnapshot) throws -> [String: Any]? {
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    return object["bankedResets"] as? [String: Any]
  }
}

private actor ResetTransport: HTTPTransport {
  let usage: Data
  let details: Data
  let detailStatus: Int
  private(set) var detailRequest: URLRequest?

  init(usage: Data, details: Data, detailStatus: Int = 200) {
    self.usage = usage
    self.details = details
    self.detailStatus = detailStatus
  }

  func send(_ request: URLRequest) -> HTTPResponse {
    if request.url?.path == "/backend-api/wham/rate-limit-reset-credits" {
      detailRequest = request
      return HTTPResponse(data: details, statusCode: detailStatus, headers: [:])
    }
    return HTTPResponse(data: usage, statusCode: 200, headers: [:])
  }
}
