import Foundation
import UsageMeterCore

struct BankedResetRowPresentation: Equatable, Identifiable {
  let account: SubscriptionAccount
  let availableCount: Int
  let applicableCount: Int?
  let grants: [BankedResetGrantPresentation]?

  var id: UUID { account.id }

  init(
    account: SubscriptionAccount, resets: BankedResets, now: Date,
    timeZone: TimeZone = .autoupdatingCurrent
  ) {
    self.account = account
    let unexpired = resets.grants?.filter { grant in
      grant.expiresAt.map { $0 > now } ?? true
    }
    availableCount = unexpired?.reduce(0) { $0 + $1.remainingCount } ?? resets.availableCount
    // After a known grant expires, the old applicability count is no longer
    // reliable. The next provider refresh will supply a new one.
    applicableCount = availableCount == resets.availableCount ? resets.applicableCount : nil
    grants = unexpired?.sorted { left, right in
      if left.expiresAt != right.expiresAt {
        return (left.expiresAt ?? .distantFuture) < (right.expiresAt ?? .distantFuture)
      }
      return left.id < right.id
    }.map { BankedResetGrantPresentation(grant: $0, timeZone: timeZone) }
  }
}

struct BankedResetGrantPresentation: Equatable, Identifiable {
  let id: String
  let title: String
  let remainingCount: Int
  let expiryText: String
  let scopeText: String
  let availabilityText: String

  init(grant: BankedReset, timeZone: TimeZone) {
    id = grant.id
    title = grant.title
    remainingCount = grant.remainingCount
    if let expiresAt = grant.expiresAt {
      let formatter = DateFormatter()
      formatter.locale = .autoupdatingCurrent
      formatter.timeZone = timeZone
      formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy jm z")
      expiryText = "Expires \(formatter.string(from: expiresAt))"
    } else {
      expiryText = "Expiry not reported"
    }
    scopeText = grant.scopes.map { scope in
      switch scope {
      case "five_hour": "Five-hour session"
      case "seven_day": "Weekly limits"
      case "seven_day_overage_included": "Weekly included extra usage"
      case "codex_rate_limits": "Codex limits"
      default: scope.replacingOccurrences(of: "_", with: " ")
      }
    }.joined(separator: " · ")
    availabilityText =
      switch grant.availability {
      case .ready: "Usable now"
      case .banked: "Banked"
      case .paused: "Paused"
      case .unsupportedPlan: "Not supported by this plan"
      case .cooldown: "Waiting for cooldown"
      case .scheduled: "Not yet available"
      }
  }
}
