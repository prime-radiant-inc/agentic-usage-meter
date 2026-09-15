import Foundation
import UsageMeterCore

struct UsageReportAccount: Equatable {
  let accountID: UUID
  let provider: Provider
  let providerDisplayName: String
  let displayName: String
  let identity: String?
  let snapshot: UsageSnapshot?

  var fetchedAt: Date? {
    snapshot?.fetchedAt
  }

  /// Shortest window first, so a five-hour window precedes the weekly
  /// one that contains it. The identifier breaks ties so the order is
  /// stable across runs.
  var windows: [UsageWindow] {
    (snapshot?.windows ?? []).sorted { lhs, rhs in
      lhs.duration == rhs.duration
        ? lhs.id < rhs.id
        : lhs.duration < rhs.duration
    }
  }

  var balances: [UsageBalance] {
    snapshot?.balances ?? []
  }
}

struct UsageReportTightest: Equatable {
  let account: UsageReportAccount
  let window: UsageWindow
}

struct UsageReport: Equatable {
  let accounts: [UsageReportAccount]

  init(
    state: PersistedAppState,
    catalog: ProviderCatalog = .live
  ) {
    accounts =
      state.accounts
      .sorted { lhs, rhs in
        let lhsProvider = catalog.sortIndex(for: lhs.provider)
        let rhsProvider = catalog.sortIndex(for: rhs.provider)
        if lhsProvider != rhsProvider {
          return lhsProvider < rhsProvider
        }
        if lhs.displayOrder != rhs.displayOrder {
          return lhs.displayOrder < rhs.displayOrder
        }
        if lhs.displayName != rhs.displayName {
          return lhs.displayName < rhs.displayName
        }
        // Final tiebreak so the comparator is total: `sorted(by:)` is
        // not documented as stable, and two accounts can otherwise
        // share provider, displayOrder, and displayName.
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .map { account in
        UsageReportAccount(
          accountID: account.id,
          provider: account.provider,
          providerDisplayName: catalog
            .definition(for: account.provider)?
            .displayName ?? account.provider.rawValue,
          displayName: account.displayName,
          identity: account.authenticatedIdentity,
          snapshot: state.snapshots[account.id]
        )
      }
  }

  /// The window with the least headroom, ranked the way the menu bar
  /// label ranks it. Balances carry no fraction, so they do not
  /// compete.
  var tightest: UsageReportTightest? {
    guard
      let tightest = UsageSummary.tightestWindow(
        in: accounts.compactMap(\.snapshot)
      ),
      let account = accounts.first(where: {
        $0.accountID == tightest.accountID
      })
    else {
      return nil
    }
    return UsageReportTightest(
      account: account,
      window: tightest.window
    )
  }
}

extension UsageWindow {
  /// The one rounding rule for a consumed percentage, so the table, the
  /// tightest line, and the JSON document can never round the same window
  /// to different integers.
  var consumedPercent: Int {
    Int((consumedFraction * 100).rounded())
  }
}
