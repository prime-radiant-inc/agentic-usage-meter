import Foundation

// Reset metadata is optional. A changed contract must not discard valid quota
// windows, and an unreadable grant list must not become a reported zero balance.
enum BankedResetDecoder {
  static func codexSummary(_ data: Data) -> BankedResets? {
    guard let summary = try? decoder().decode(CodexUsage.self, from: data).rateLimitResetCredits,
      summary.availableCount >= 0,
      summary.applicableAvailableCount.map({ (0...summary.availableCount).contains($0) }) ?? true
    else { return nil }
    return BankedResets(
      availableCount: summary.availableCount,
      applicableCount: summary.applicableAvailableCount,
      grants: nil
    )
  }

  static func codexDetails(_ data: Data, summary: BankedResets?, now: Date) -> BankedResets? {
    guard let payload = try? decoder().decode(CodexDetails.self, from: data),
      payload.availableCount >= 0
    else { return nil }
    var grants: [BankedReset] = []
    var ids: Set<String> = []
    for credit in payload.credits where credit.status == "available" {
      guard !credit.id.isEmpty, ids.insert(credit.id).inserted else { return nil }
      let expiry: Date?
      if let raw = credit.expiresAt {
        guard let date = date(raw) else { return nil }
        expiry = date
      } else {
        expiry = nil
      }
      guard expiry.map({ $0 > now }) ?? true else { continue }
      grants.append(
        BankedReset(
          id: credit.id,
          title: credit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Limit reset" : credit.title,
          remainingCount: 1,
          expiresAt: expiry,
          scopes: [credit.resetType],
          availability: credit.isSupportedByPlan ? .banked : .unsupportedPlan
        ))
    }
    // Preserve the server's count if a new status or omitted entry prevents a
    // complete list; never imply the visible subset is the entire bank.
    guard grants.count == payload.availableCount else {
      return BankedResets(availableCount: payload.availableCount, applicableCount: nil, grants: nil)
    }
    return BankedResets(
      availableCount: payload.availableCount,
      applicableCount: summary?.availableCount == payload.availableCount
        ? summary?.applicableCount : nil,
      grants: grants
    )
  }

  static func claude(_ data: Data, now: Date) -> BankedResets? {
    guard let payload = try? decoder().decode(ClaudeUsage.self, from: data).cedarEmber else {
      return nil
    }
    let cooldown: Date?
    if let raw = payload.cooldownUntil {
      guard let parsed = date(raw) else { return nil }
      cooldown = parsed
    } else {
      cooldown = nil
    }
    var grants: [BankedReset] = []
    var ids: Set<String> = []
    var total = 0
    var applicable = 0
    for grant in payload.grants {
      guard !grant.id.isEmpty, ids.insert(grant.id).inserted, grant.resetsLeft >= 0,
        let expiry = date(grant.endsAt), let start = date(grant.startsAt), expiry > start
      else { return nil }
      guard grant.resetsLeft > 0, expiry > now else { continue }
      let availability: BankedReset.Availability
      if grant.paused {
        availability = .paused
      } else if start > now {
        availability = .scheduled
      } else if cooldown.map({ $0 > now }) ?? false {
        availability = .cooldown
      } else if payload.eligible && grant.usableNow && grant.blocking.isEmpty {
        availability = .ready
      } else {
        availability = .banked
      }
      let (sum, overflow) = total.addingReportingOverflow(grant.resetsLeft)
      guard !overflow else { return nil }
      total = sum
      if availability == .ready { applicable += grant.resetsLeft }
      grants.append(
        BankedReset(
          id: grant.id,
          title: grant.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Limit reset" : grant.label,
          remainingCount: grant.resetsLeft,
          expiresAt: expiry,
          scopes: grant.clears,
          availability: availability
        ))
    }
    return BankedResets(availableCount: total, applicableCount: applicable, grants: grants)
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  private static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private struct CodexUsage: Decodable {
    let rateLimitResetCredits: CodexSummary?
  }

  private struct CodexSummary: Decodable {
    let availableCount: Int
    let applicableAvailableCount: Int?
  }

  private struct CodexDetails: Decodable {
    let availableCount: Int
    let credits: [CodexCredit]
  }

  private struct CodexCredit: Decodable {
    let id: String
    let title: String
    let resetType: String
    let status: String
    let isSupportedByPlan: Bool
    let expiresAt: String?
  }

  private struct ClaudeUsage: Decodable {
    let cedarEmber: ClaudeResets?
  }

  private struct ClaudeResets: Decodable {
    let eligible: Bool
    let grants: [ClaudeGrant]
    let cooldownUntil: String?
  }

  private struct ClaudeGrant: Decodable {
    let id: String
    let label: String
    let resetsLeft: Int
    let startsAt: String
    let endsAt: String
    let clears: [String]
    let paused: Bool
    let usableNow: Bool
    let blocking: [String]
  }
}
