import Foundation
import UsageMeterCore

enum StateFixture {
  static let referenceDate = Date(
    timeIntervalSince1970: 2_000_000_000
  )

  static let claudeWorkID = UUID(
    uuidString: "11111111-1111-1111-1111-111111111111"
  )!
  static let claudePersonalID = UUID(
    uuidString: "22222222-2222-2222-2222-222222222222"
  )!
  static let codexPersonalID = UUID(
    uuidString: "33333333-3333-3333-3333-333333333333"
  )!
  static let kimiID = UUID(
    uuidString: "44444444-4444-4444-4444-444444444444"
  )!

  /// Claude/Work has two windows and an available balance,
  /// Claude/Personal has no snapshot at all, Codex/Personal has an
  /// unlimited balance, and Kimi has a disabled one.
  static func populatedState() -> PersistedAppState {
    let accounts = [
      SubscriptionAccount(
        id: claudeWorkID,
        provider: .claude,
        displayName: "Work",
        authenticatedIdentity: "harper@example.com",
        displayOrder: 0
      ),
      SubscriptionAccount(
        id: claudePersonalID,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 1
      ),
      SubscriptionAccount(
        id: codexPersonalID,
        provider: .codex,
        displayName: "Personal",
        displayOrder: 0
      ),
      SubscriptionAccount(
        id: kimiID,
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0
      ),
    ]

    let snapshots: [UUID: UsageSnapshot] = [
      claudeWorkID: UsageSnapshot(
        accountID: claudeWorkID,
        fetchedAt: referenceDate,
        windows: [
          // Listed weekly-first on purpose, so the projection has
          // something to reorder.
          UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: referenceDate.addingTimeInterval(280_800),
            consumedFraction: 0.44
          )!,
          UsageWindow(
            id: "short",
            kind: .short,
            duration: 18_000,
            resetAt: referenceDate.addingTimeInterval(8_040),
            consumedFraction: 0.61
          )!,
        ],
        balances: [
          UsageBalance(
            id: "extra-credits",
            label: "Extra usage",
            value: .available(
              amount: Decimal(string: "38.42")!,
              unit: "USD"
            )
          )!
        ]
      ),
      codexPersonalID: UsageSnapshot(
        accountID: codexPersonalID,
        fetchedAt: referenceDate,
        windows: [
          UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: referenceDate.addingTimeInterval(435_600),
            consumedFraction: 0.78
          )!
        ],
        balances: [
          UsageBalance(
            id: "credits",
            label: "Credits",
            value: .unlimited
          )!
        ]
      ),
      kimiID: UsageSnapshot(
        accountID: kimiID,
        fetchedAt: referenceDate,
        windows: [
          UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: referenceDate.addingTimeInterval(500_000),
            consumedFraction: 0.26
          )!
        ],
        balances: [
          UsageBalance(
            id: "extra-credits",
            label: "Extra usage",
            value: .disabled
          )!
        ]
      ),
    ]

    return PersistedAppState(
      accounts: accounts,
      snapshots: snapshots
    )
  }

  static func emptyState() -> PersistedAppState {
    PersistedAppState(accounts: [], snapshots: [:])
  }

  /// Two windows on different accounts consuming exactly the same
  /// fraction, so only the reset time can break the tie. Claude resets
  /// later, so Codex must win.
  static func tiedState() -> PersistedAppState {
    let accounts = [
      SubscriptionAccount(
        id: claudeWorkID,
        provider: .claude,
        displayName: "Work",
        displayOrder: 0
      ),
      SubscriptionAccount(
        id: codexPersonalID,
        provider: .codex,
        displayName: "Personal",
        displayOrder: 0
      ),
    ]

    let snapshots: [UUID: UsageSnapshot] = [
      claudeWorkID: UsageSnapshot(
        accountID: claudeWorkID,
        fetchedAt: referenceDate,
        windows: [
          UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: referenceDate.addingTimeInterval(200_000),
            consumedFraction: 0.5
          )!
        ]
      ),
      codexPersonalID: UsageSnapshot(
        accountID: codexPersonalID,
        fetchedAt: referenceDate,
        windows: [
          UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: referenceDate.addingTimeInterval(100_000),
            consumedFraction: 0.5
          )!
        ]
      ),
    ]

    return PersistedAppState(
      accounts: accounts,
      snapshots: snapshots
    )
  }

  /// A display name far wider than its column header, so the table
  /// test can prove the columns widen to fit rather than truncating.
  /// Consumed by Task 6.
  static func longDisplayNameState() -> PersistedAppState {
    PersistedAppState(
      accounts: [
        SubscriptionAccount(
          id: claudeWorkID,
          provider: .claude,
          displayName: "Anvil Platform Engineering",
          displayOrder: 0
        ),
        SubscriptionAccount(
          id: codexPersonalID,
          provider: .codex,
          displayName: "Me",
          displayOrder: 0
        ),
      ],
      snapshots: [
        claudeWorkID: UsageSnapshot(
          accountID: claudeWorkID,
          fetchedAt: referenceDate,
          windows: [
            UsageWindow(
              id: "weekly",
              kind: .weekly,
              duration: 604_800,
              resetAt: referenceDate.addingTimeInterval(280_800),
              consumedFraction: 0.05
            )!
          ]
        ),
        codexPersonalID: UsageSnapshot(
          accountID: codexPersonalID,
          fetchedAt: referenceDate,
          windows: [
            UsageWindow(
              id: "short",
              kind: .short,
              duration: 18_000,
              resetAt: referenceDate.addingTimeInterval(2_520),
              consumedFraction: 1.0
            )!
          ]
        ),
      ]
    )
  }

  /// Encodes `state` to a uniquely named file under the temporary
  /// directory and returns its URL. Real JSON, real layout.
  static func write(
    _ state: PersistedAppState
  ) throws -> URL {
    let url = URL.temporaryDirectory
      .appending(path: "usage-meter-tests-\(UUID().uuidString)")
      .appending(path: "state.json")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(state).write(to: url)
    return url
  }
}
