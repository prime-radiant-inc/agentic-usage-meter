import Foundation
import UsageMeterCore

enum UsageTextReport {
  private static let missingMarker = "—"
  private static let columnGap = "  "
  private static let usedColumn = 3

  static func table(
    _ report: UsageReport,
    now: Date
  ) -> String {
    guard !report.accounts.isEmpty else {
      return ""
    }

    var rows: [[String]] = [
      ["PROVIDER", "ACCOUNT", "WINDOW", "USED", "RESETS"]
    ]
    for account in report.accounts {
      guard !account.windows.isEmpty else {
        rows.append([
          account.providerDisplayName,
          account.displayName,
          missingMarker,
          missingMarker,
          missingMarker,
        ])
        continue
      }
      for window in account.windows {
        rows.append([
          account.providerDisplayName,
          account.displayName,
          window.label ?? window.kind.rawValue,
          "\(window.consumedPercent)%",
          relativeDuration(from: now, to: window.resetAt),
        ])
      }
    }

    var lines = alignedLines(rows)

    // Balances are amounts, not percentages, so they get their own
    // lines rather than bending the window columns around them.
    let balanceLines = report.accounts.flatMap { account in
      account.balances.map { balance in
        "\(name(of: account))  \(balance.label): "
          + balanceValueText(balance)
      }
    }
    if !balanceLines.isEmpty {
      lines.append("")
      lines.append(contentsOf: balanceLines)
    }

    return lines.joined(separator: "\n")
  }

  static func tightestLine(
    _ report: UsageReport,
    now: Date
  ) -> String {
    guard let tightest = report.tightest else {
      return ""
    }
    // "used", not a bare number: the menu-bar label renders the *remaining*
    // fraction for this same window, so two unlabeled complements would sit
    // on one screen contradicting each other.
    let head =
      "\(name(of: tightest.account)) \(tightest.window.consumedPercent)% used"
    guard tightest.window.resetAt != nil else {
      return head
    }
    return head + " · resets in "
      + relativeDuration(from: now, to: tightest.window.resetAt)
  }

  static func relativeDuration(
    from now: Date,
    to date: Date?
  ) -> String {
    guard let date else {
      return missingMarker
    }
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else {
      return "now"
    }
    let minutes = Int(seconds / 60)
    let days = minutes / 1_440
    let hours = (minutes % 1_440) / 60
    if days > 0 {
      return "\(days)d \(hours)h"
    }
    if hours > 0 {
      return "\(hours)h \(minutes % 60)m"
    }
    return "\(minutes % 60)m"
  }

  static func balanceValueText(
    _ balance: UsageBalance
  ) -> String {
    switch balance.value {
    case let .available(amount, unit):
      "\(amount) \(unit)"
    case .unlimited:
      "unlimited"
    case .disabled:
      "disabled"
    }
  }

  private static func name(of account: UsageReportAccount) -> String {
    "\(account.providerDisplayName)/\(account.displayName)"
  }

  /// Pads every column but the last, so no line carries trailing
  /// whitespace. The used column reads better right-aligned.
  private static func alignedLines(
    _ rows: [[String]]
  ) -> [String] {
    guard let columnCount = rows.first?.count else {
      return []
    }
    let widths = (0..<columnCount).map { column in
      rows.map { $0[column].count }.max() ?? 0
    }

    return rows.map { row in
      (0..<columnCount)
        .map { column in
          guard column < columnCount - 1 else {
            return row[column]
          }
          let padding = String(
            repeating: " ",
            count: widths[column] - row[column].count
          )
          return column == usedColumn
            ? padding + row[column]
            : row[column] + padding
        }
        .joined(separator: columnGap)
    }
  }
}
