import Foundation

public struct BankedResets: Codable, Equatable, Sendable {
  public let availableCount: Int
  public let applicableCount: Int?
  // Nil means the provider's count is known but the grant list is unavailable.
  public let grants: [BankedReset]?

  public init(availableCount: Int, applicableCount: Int?, grants: [BankedReset]?) {
    self.availableCount = availableCount
    self.applicableCount = applicableCount
    self.grants = grants
  }
}

public struct BankedReset: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let remainingCount: Int
  public let expiresAt: Date?
  public let scopes: [String]
  public let availability: Availability

  public enum Availability: String, Codable, Sendable {
    case ready
    case banked
    case paused
    case unsupportedPlan
    case cooldown
    case scheduled
  }

  public init(
    id: String, title: String, remainingCount: Int, expiresAt: Date?,
    scopes: [String], availability: Availability
  ) {
    self.id = id
    self.title = title
    self.remainingCount = remainingCount
    self.expiresAt = expiresAt
    self.scopes = scopes
    self.availability = availability
  }
}
