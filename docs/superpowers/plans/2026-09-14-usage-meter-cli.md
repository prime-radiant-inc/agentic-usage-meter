# Usage Meter CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `usage-meter` command that prints the application's
current quota picture as a table, as versioned JSON, or as a single
line for a shell prompt.

**Architecture:** A new executable target reads the application's own
`state.json` through `AppStateStore`, projects `PersistedAppState` into
a sorted report, and renders it three ways. No daemon, no socket, no
new file on disk, and no change to `AppModel`. The command ships inside
the application bundle and compiles from the same source tree, so it
moves with the format it decodes.

**Tech Stack:** Swift 6.2, SwiftPM, swift-testing. No new package
dependency.

**Spec:** `docs/superpowers/specs/2026-09-14-usage-meter-cli-design.md`

## Global Constraints

- Swift tools version 6.2, `swiftLanguageModes: [.v6]`, platform floor
  `.macOS(.v26)`. All new code compiles under Swift 6 strict
  concurrency.
- **Add no package dependency.** Sparkle exact 2.9.4 is the only one
  and stays the only one. Parse arguments by hand.
- **Indentation is per-file in this repository.** Use **2 spaces** in
  `Sources/UsageMeterCLI/` and `Tests/UsageMeterCLITests/`, matching
  their sibling `Sources/UsageMeterProbe/`. Use **4 spaces** when
  editing `AppStateStore.swift`, `AgenticUsageMeterApp.swift`,
  `Package.swift`, and `Tests/UsageMeterCoreTests/AppStateStoreTests.swift`,
  matching those files.
- **Test style is per-file too.** New CLI test files use `@Suite struct`
  with 2-space indent, matching
  `Tests/UsageMeterProbeTests/UsageMeterProbeCommandTests.swift`.
  `Tests/UsageMeterCoreTests/AppStateStoreTests.swift` uses **top-level
  `@Test` functions with no enclosing suite** — the Task 1 test must
  follow that file, not the CLI convention.
- Tests use **swift-testing**, never XCTest: `import Testing`, `@Test`,
  `#expect`, `try #require`.
- **This repository does not use `ABOUTME:` file-header comments.** Do
  not add them. House convention wins.
- **Commit messages here are plain imperative sentences with no
  conventional-commit prefix.** Real examples from this history:
  "Harden Claude scoped usage decoding", "Constrain menu dropdown
  height so long account lists scroll". Never write `feat:` or `fix:`.
- Provider display names come from `ProviderCatalog.live`, never from
  `Provider.rawValue`, except as a fallback when the catalog has no
  definition.
- JSON output uses `dateEncodingStrategy = .iso8601` and
  `outputFormatting = [.prettyPrinted, .sortedKeys]`, matching
  `UsageMeterProbe`.
- No test substitutes a fake store. Tests build real
  `PersistedAppState` values, encode them to real files, and read them
  back through real code.

## Verified Signatures

Everything below was read from the source. Use these exactly; do not
improvise a parameter name.

```swift
// UsageMeterCore/Domain/UsageModels.swift
public init(                                  // SubscriptionAccount
  id: UUID = UUID(),
  provider: Provider,
  displayName: String,
  authenticatedIdentity: String? = nil,
  displayOrder: Int,
  claudeProfileID: UUID? = nil,
  claudeOrganizationID: UUID? = nil,
)

public init?(                                 // UsageWindow — FAILABLE
  id: String,
  kind: UsageWindowKind,
  duration: TimeInterval,
  resetAt: Date?,
  consumedFraction: Double,
  label: String? = nil,
  reportedStartAt: Date? = nil
)
// Returns nil unless: id non-empty, duration finite and > 0,
// consumedFraction finite and in 0...1, and
// (resetAt != nil || (consumedFraction == 0 && reportedStartAt == nil)).

public init?(                                 // UsageBalance — FAILABLE
  id: String,
  label: String,
  value: UsageBalanceValue,
  cycleEndsAt: Date? = nil
)
// Returns nil if id or label is empty after trimming.
// Computed: remainingAmount: Double? and unit: String?, both nil
// unless value is .available.

public init(                                   // UsageSnapshot
  accountID: UUID,
  fetchedAt: Date,
  windows: [UsageWindow],
  balances: [UsageBalance] = []
)

public enum UsageWindowKind: String { case short, daily, weekly, monthly, custom }
public enum UsageBalanceValue { case available(amount: Decimal, unit: String), unlimited, disabled }

// UsageMeterCore/Persistence/PersistedAppState.swift
public init(
  accounts: [SubscriptionAccount],
  snapshots: [UUID: UsageSnapshot],
  refreshStates: [UUID: AccountRefreshState] = [:],
  isFloatingWidgetVisible: Bool = false,
  floatingWidgetPlacement: FloatingWidgetPlacement? = nil,
  collapsedUsageSections: Set<UsageSectionID> = [],
)

// UsageMeterCore/Persistence/AppStateStore.swift
public enum AppStateStoreError: Error, Equatable { case corruptData }
public actor AppStateStore {
  public init(fileURL: URL, fileManager: FileManager = .default)
  public func load() throws -> PersistedAppState   // actor: call as `try await`
}
// load() returns .empty when the file is absent, and throws
// .corruptData only for a DecodingError. A read failure surfaces as
// the underlying CocoaError instead.

// UsageMeterCore/Presentation/UsageSummary.swift
public struct TightestUsage: Equatable, Sendable {
  public let accountID: UUID
  public let window: UsageWindow
}
public enum UsageSummary {
  public static func tightestWindow(in snapshots: [UsageSnapshot]) -> TightestUsage?
}

// UsageMeterCore/Providers/ProviderCatalog.swift
public let all: [ProviderDefinition]
public func definition(for provider: Provider) -> ProviderDefinition?
public func sortIndex(for provider: Provider) -> Int
// ProviderDefinition.displayName: String
```

## Critical Gotcha: UUID-keyed dictionaries are JSON arrays

`PersistedAppState.snapshots` is `[UUID: UsageSnapshot]` and
`refreshStates` is `[UUID: AccountRefreshState]`. `UUID` does not
conform to `CodingKeyRepresentable`, so `JSONEncoder` writes these as
**flat arrays of alternating key and value**, not as objects. Verified
against the real file on disk:

```
$ jq -r '.snapshots | type' ~/Library/Application\ Support/AgenticUsageMeter/state.json
array
```

**Consequence: never hand-author a `state.json` test fixture.** Build a
`PersistedAppState` in Swift, encode it with `JSONEncoder`, and write
that to a temporary file. Task 3 provides the helper that does this.

The only hand-checked fixture in this plan is the *golden JSON output*
of Task 5, which is the command's own schema and therefore ours to
define — and even that one is generated by the code, then read and
approved, never typed.

## File Structure

**Create:**

| Path | Responsibility |
|---|---|
| `Sources/UsageMeterCLI/UsageMeterCLICommand.swift` | Parse `[String]` into a command. No I/O. |
| `Sources/UsageMeterCLI/UsageReport.swift` | Project `PersistedAppState` into sorted accounts and windows. No I/O. |
| `Sources/UsageMeterCLI/UsageReportDocument.swift` | The `schemaVersion: 1` wire types. |
| `Sources/UsageMeterCLI/UsageTextReport.swift` | Render a report as a table or a one-line summary. |
| `Sources/UsageMeterCLI/UsageStateLoader.swift` | Read the state file; classify failures into exit codes. |
| `Sources/UsageMeterCLI/UsageMeterCLI.swift` | `@main`: wire parsing, loading, rendering, exit. |
| `Tests/UsageMeterCLITests/StateFixture.swift` | Build and write real `state.json` files for tests. |
| `Tests/UsageMeterCLITests/UsageMeterCLICommandTests.swift` | Parsing. |
| `Tests/UsageMeterCLITests/UsageReportTests.swift` | Projection and sorting. |
| `Tests/UsageMeterCLITests/UsageReportDocumentTests.swift` | Schema, against a golden fixture. |
| `Tests/UsageMeterCLITests/UsageTextReportTests.swift` | Table and one-line rendering. |
| `Tests/UsageMeterCLITests/UsageStateLoaderTests.swift` | Missing and undecodable state files. |
| `Tests/UsageMeterCLITests/Fixtures/usage-report-v1.json` | Golden schema-1 output. |

**Modify:**

| Path | Change |
|---|---|
| `Sources/UsageMeterCore/Persistence/AppStateStore.swift` | Add `defaultFileURL(fileManager:)`. |
| `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift:100,193` | Call it; delete the private `stateFileURL()`. |
| `Tests/UsageMeterCoreTests/AppStateStoreTests.swift` | Cover `defaultFileURL`. |
| `Package.swift` | Add product `usage-meter`, target `UsageMeterCLI`, test target. |
| `Scripts/assemble-app.sh` | Build and copy the second binary. |
| `Scripts/sign-app.sh` | Sign the second binary before the bundle. |
| `README.md` | Document the command. |

---

### Task 1: One source of truth for the state file path

`AgenticUsageMeterApp` computes the state file path in a `private
static` function, so the command cannot reuse it. Move it to Core
before anything depends on it.

**Files:**
- Modify: `Sources/UsageMeterCore/Persistence/AppStateStore.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift:100,193`
- Test: `Tests/UsageMeterCoreTests/AppStateStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppStateStore.defaultFileURL(fileManager: FileManager = .default) -> URL`

- [ ] **Step 1: Write the failing test**

Append to `Tests/UsageMeterCoreTests/AppStateStoreTests.swift`. That
file uses **top-level `@Test` functions with no enclosing suite** and
**4-space indentation**, and names tests with a `stateStore` prefix —
follow all three.

```swift
@Test
func stateStoreDefaultFileURLNamesApplicationSupportStateFile() {
    let url = AppStateStore.defaultFileURL()

    #expect(url.lastPathComponent == "state.json")
    #expect(
        url.deletingLastPathComponent().lastPathComponent
            == "AgenticUsageMeter"
    )
    #expect(url.path.contains("Application Support"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter stateStoreDefaultFileURLNamesApplicationSupportStateFile`
Expected: compile failure — `defaultFileURL` is not a member of `AppStateStore`.

- [ ] **Step 3: Add the accessor**

In `Sources/UsageMeterCore/Persistence/AppStateStore.swift`, inside the
`AppStateStore` actor, using **4-space indentation**:

```swift
    public static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(
            path: "AgenticUsageMeter/state.json"
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter stateStoreDefaultFileURLNamesApplicationSupportStateFile`
Expected: PASS

- [ ] **Step 5: Point the application at the shared accessor**

In `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift` line 100,
change:

```swift
                : AppStateStore(fileURL: stateFileURL())
```

to:

```swift
                : AppStateStore(fileURL: AppStateStore.defaultFileURL())
```

Then delete the now-unused private function at line 193 entirely:

```swift
    private static func stateFileURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        )[0]
            .appending(
                path: "AgenticUsageMeter/state.json",
            )
    }
```

- [ ] **Step 6: Verify the whole suite still builds and passes**

Run: `swift build && swift test`
Expected: build succeeds, no new failures. A leftover reference to
`stateFileURL()` fails to compile here, and an unused private function
would warn.

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageMeterCore/Persistence/AppStateStore.swift \
        Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift \
        Tests/UsageMeterCoreTests/AppStateStoreTests.swift
git commit -m "Share the state file location between app and library"
```

---

### Task 2: Command target and argument parsing

**Files:**
- Modify: `Package.swift`
- Create: `Sources/UsageMeterCLI/UsageMeterCLICommand.swift`
- Create: `Sources/UsageMeterCLI/UsageMeterCLI.swift`
- Test: `Tests/UsageMeterCLITests/UsageMeterCLICommandTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum UsageMeterCLIOutput: Equatable { case table, json, tightest }`
  - `enum UsageMeterCLICommand: Equatable { case report(output: UsageMeterCLIOutput, stateFileURL: URL?), help }`
  - `static func UsageMeterCLICommand.parse(arguments: [String]) throws -> UsageMeterCLICommand`
  - `enum UsageMeterCLICommandError: Error, Equatable { case invalidArguments }`
  - `UsageMeterCLI.usage: String`

- [ ] **Step 1: Declare the target so tests can import it**

`Package.swift` uses **4-space indentation**, with 8 spaces for entries
inside `products:` and `targets:`.

The current last entry in `products:` is
`.executable(name: "UsageMeterProbe", targets: ["UsageMeterProbe"])`
and it has **no trailing comma** — add one, then append:

```swift
        .executable(name: "usage-meter", targets: ["UsageMeterCLI"])
```

The product name is deliberately `usage-meter` while the target is
`UsageMeterCLI`: the target keeps the package's CamelCase convention
and the binary gets the name a person types.

In `targets:`, after the `UsageMeterProbe` executable target, add:

```swift
        .executableTarget(
            name: "UsageMeterCLI",
            dependencies: ["UsageMeterCore"]
        ),
```

The current last entry in `targets:` is
`.testTarget(name: "UsageMeterWebTests", dependencies: ["UsageMeterWeb"])`
with no trailing comma — add one, then append:

```swift
        .testTarget(
            name: "UsageMeterCLITests",
            dependencies: ["UsageMeterCLI", "UsageMeterCore"]
        )
```

Do **not** declare `resources:` here. Task 5 adds that line along with
the fixture file it points at; SwiftPM fails on a declared resource
path that does not exist.

- [ ] **Step 2: Write the failing test**

Create `Tests/UsageMeterCLITests/UsageMeterCLICommandTests.swift`
(2-space indent, `@Suite struct`):

```swift
import Foundation
import Testing

@testable import UsageMeterCLI

@Suite
struct UsageMeterCLICommandTests {
  @Test
  func noArgumentsSelectsTheTable() throws {
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter"]
      ) == .report(output: .table, stateFileURL: nil)
    )
  }

  @Test
  func flagsSelectTheOtherOutputs() throws {
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--json"]
      ) == .report(output: .json, stateFileURL: nil)
    )
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--tightest"]
      ) == .report(output: .tightest, stateFileURL: nil)
    )
  }

  @Test
  func helpWinsOverEverythingElse() throws {
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--json", "--help"]
      ) == .help
    )
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "-h"]
      ) == .help
    )
  }

  @Test
  func stateFileOverrideCombinesWithAnOutputFlag() throws {
    #expect(
      try UsageMeterCLICommand.parse(
        arguments: [
          "usage-meter",
          "--json",
          "--state-file",
          "/tmp/state.json",
        ]
      )
        == .report(
          output: .json,
          stateFileURL: URL(filePath: "/tmp/state.json")
        )
    )
  }

  @Test
  func rejectsTwoOutputFlags() {
    #expect(throws: UsageMeterCLICommandError.invalidArguments) {
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--json", "--tightest"]
      )
    }
  }

  @Test
  func rejectsAStateFileFlagWithNoValue() {
    #expect(throws: UsageMeterCLICommandError.invalidArguments) {
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--state-file"]
      )
    }
  }

  @Test
  func rejectsUnknownFlagsAndStrayArguments() {
    #expect(throws: UsageMeterCLICommandError.invalidArguments) {
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--colour"]
      )
    }
    #expect(throws: UsageMeterCLICommandError.invalidArguments) {
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "accounts"]
      )
    }
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter UsageMeterCLICommandTests`
Expected: FAIL — no such module `UsageMeterCLI`.

- [ ] **Step 4: Write the parser**

Create `Sources/UsageMeterCLI/UsageMeterCLICommand.swift`:

```swift
import Foundation

enum UsageMeterCLIOutput: Equatable {
  case table
  case json
  case tightest
}

enum UsageMeterCLICommand: Equatable {
  case report(output: UsageMeterCLIOutput, stateFileURL: URL?)
  case help

  static func parse(arguments: [String]) throws -> Self {
    var output: UsageMeterCLIOutput?
    var stateFilePath: String?
    var index = 1

    while index < arguments.count {
      switch arguments[index] {
      case "--help", "-h":
        return .help
      case "--json":
        guard output == nil else {
          throw UsageMeterCLICommandError.invalidArguments
        }
        output = .json
      case "--tightest":
        guard output == nil else {
          throw UsageMeterCLICommandError.invalidArguments
        }
        output = .tightest
      case "--state-file":
        guard
          stateFilePath == nil,
          index + 1 < arguments.count
        else {
          throw UsageMeterCLICommandError.invalidArguments
        }
        index += 1
        stateFilePath = arguments[index]
      default:
        throw UsageMeterCLICommandError.invalidArguments
      }
      index += 1
    }

    return .report(
      output: output ?? .table,
      stateFileURL: stateFilePath.map { URL(filePath: $0) }
    )
  }
}

enum UsageMeterCLICommandError: Error, Equatable {
  case invalidArguments
}
```

- [ ] **Step 5: Add a placeholder entry point so the target links**

Create `Sources/UsageMeterCLI/UsageMeterCLI.swift`. Task 7 fills in
`main`; it has to exist now for the executable target to compile.

```swift
import Foundation

@main
enum UsageMeterCLI {
  static let usage = """
    usage:
      usage-meter                  usage table
      usage-meter --json           machine-readable report
      usage-meter --tightest       the window with the least headroom
      usage-meter --help           this message

    options:
      --state-file <path>          read state from <path> instead of
                                   the application's own state file
    """

  static func main() async {
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter UsageMeterCLICommandTests`
Expected: PASS, all seven tests.

- [ ] **Step 7: Confirm the binary name**

Run: `swift build --product usage-meter && swift run usage-meter --help`
Expected: the usage text prints.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/UsageMeterCLI \
        Tests/UsageMeterCLITests
git commit -m "Add a usage-meter command that parses its arguments"
```

---

### Task 3: Projection from persisted state

Turns `PersistedAppState` into an ordered report. Pure: no I/O, no
formatting. This task also lands the fixture helper every later task
uses, because a wrong fixture is worse than no fixture.

**Files:**
- Create: `Sources/UsageMeterCLI/UsageReport.swift`
- Create: `Tests/UsageMeterCLITests/StateFixture.swift`
- Test: `Tests/UsageMeterCLITests/UsageReportTests.swift`

**Interfaces:**
- Consumes: `PersistedAppState`, `SubscriptionAccount`, `UsageSnapshot`,
  `UsageWindow`, `UsageBalance`, `Provider`, `ProviderCatalog.live`,
  `ProviderCatalog.sortIndex(for:)`, `ProviderCatalog.definition(for:)`,
  `UsageSummary.tightestWindow(in:)` — all from `UsageMeterCore`.
- Produces:
  - `struct UsageReportAccount: Equatable` — `accountID: UUID`,
    `provider: Provider`, `providerDisplayName: String`,
    `displayName: String`, `identity: String?`,
    `snapshot: UsageSnapshot?`; computed `fetchedAt: Date?`,
    `windows: [UsageWindow]`, `balances: [UsageBalance]`
  - `struct UsageReport: Equatable` — `accounts: [UsageReportAccount]`,
    `init(state: PersistedAppState, catalog: ProviderCatalog = .live)`,
    `var tightest: UsageReportTightest?`
  - `struct UsageReportTightest: Equatable` —
    `account: UsageReportAccount`, `window: UsageWindow`
  - `StateFixture.populatedState()`, `StateFixture.emptyState()`,
    `StateFixture.tiedState()`, `StateFixture.longDisplayNameState()`,
    `StateFixture.write(_:) throws -> URL`,
    `StateFixture.referenceDate`, and four account-ID constants

- [ ] **Step 1: Write the fixture helper**

Create `Tests/UsageMeterCLITests/StateFixture.swift`. This encodes real
`PersistedAppState` values, which is the only safe way to produce a
`state.json` — see the UUID-keyed-dictionary gotcha above.

Every `UsageWindow` below passes a non-nil `resetAt`, because the
failable initializer rejects a nil `resetAt` whenever
`consumedFraction` is not zero.

```swift
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
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/UsageMeterCLITests/UsageReportTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter UsageReportTests`
Expected: FAIL — `UsageReport` is undefined.

- [ ] **Step 4: Write the projection**

Create `Sources/UsageMeterCLI/UsageReport.swift`:

```swift
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
        return lhs.displayName < rhs.displayName
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter UsageReportTests`
Expected: PASS, all eight tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeterCLI/UsageReport.swift \
        Tests/UsageMeterCLITests/StateFixture.swift \
        Tests/UsageMeterCLITests/UsageReportTests.swift
git commit -m "Project persisted state into an ordered usage report"
```

---

### Task 4: Reading the state file, and exit codes

**Files:**
- Create: `Sources/UsageMeterCLI/UsageStateLoader.swift`
- Test: `Tests/UsageMeterCLITests/UsageStateLoaderTests.swift`

**Interfaces:**
- Consumes: `AppStateStore`, `AppStateStore.defaultFileURL` (Task 1),
  `AppStateStoreError.corruptData`, `PersistedAppState`,
  `UsageMeterCLICommandError` (Task 2), `StateFixture` (Task 3).
- Produces:
  - `enum UsageMeterCLIError: Error, Equatable { case stateFileMissing(URL), stateFileUnreadable }`
  - `enum UsageStateLoader { static func load(from url: URL) async throws -> PersistedAppState }`
  - `func exitCode(for error: any Error) -> Int32`

`AppStateStore.load()` returns `.empty` for a missing file rather than
throwing, so the loader checks for the file itself. That check is what
separates "the application has never run" from "the file is broken".

- [ ] **Step 1: Write the failing tests**

Create `Tests/UsageMeterCLITests/UsageStateLoaderTests.swift`:

```swift
import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterCLI

@Suite
struct UsageStateLoaderTests {
  @Test
  func loadsAStateFileWrittenByTheApplication() async throws {
    let url = try StateFixture.write(StateFixture.populatedState())

    let state = try await UsageStateLoader.load(from: url)

    #expect(state.accounts.count == 4)
    #expect(state.snapshots.count == 3)
  }

  @Test
  func reportsAMissingStateFile() async throws {
    let url = URL.temporaryDirectory
      .appending(path: "absent-\(UUID().uuidString)/state.json")

    await #expect(
      throws: UsageMeterCLIError.stateFileMissing(url)
    ) {
      try await UsageStateLoader.load(from: url)
    }
  }

  @Test
  func reportsAnUndecodableStateFile() async throws {
    let url = try StateFixture.write(StateFixture.emptyState())
    try Data("{\"accounts\":\"not an array\"}".utf8).write(to: url)

    await #expect(
      throws: UsageMeterCLIError.stateFileUnreadable
    ) {
      try await UsageStateLoader.load(from: url)
    }
  }

  @Test
  func mapsEachFailureToItsExitCode() {
    #expect(
      exitCode(for: UsageMeterCLICommandError.invalidArguments)
        == EX_USAGE
    )
    #expect(
      exitCode(
        for: UsageMeterCLIError.stateFileMissing(
          URL(filePath: "/tmp/state.json")
        )
      ) == EX_NOINPUT
    )
    #expect(
      exitCode(for: UsageMeterCLIError.stateFileUnreadable)
        == EX_DATAERR
    )
    #expect(
      exitCode(for: CocoaError(.fileReadNoPermission))
        == EX_UNAVAILABLE
    )
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageStateLoaderTests`
Expected: FAIL — `UsageStateLoader` is undefined.

- [ ] **Step 3: Write the loader**

Create `Sources/UsageMeterCLI/UsageStateLoader.swift`:

```swift
import Darwin
import Foundation
import UsageMeterCore

enum UsageMeterCLIError: Error, Equatable {
  case stateFileMissing(URL)
  case stateFileUnreadable
}

enum UsageStateLoader {
  static func load(
    from url: URL
  ) async throws -> PersistedAppState {
    // AppStateStore treats an absent file as empty state, which would
    // be indistinguishable from an application that has no accounts.
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw UsageMeterCLIError.stateFileMissing(url)
    }

    do {
      return try await AppStateStore(fileURL: url).load()
    } catch AppStateStoreError.corruptData {
      throw UsageMeterCLIError.stateFileUnreadable
    }
  }
}

func exitCode(for error: any Error) -> Int32 {
  switch error {
  case UsageMeterCLICommandError.invalidArguments:
    EX_USAGE
  case UsageMeterCLIError.stateFileMissing:
    EX_NOINPUT
  case UsageMeterCLIError.stateFileUnreadable:
    EX_DATAERR
  default:
    EX_UNAVAILABLE
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageStateLoaderTests`
Expected: PASS, all four tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCLI/UsageStateLoader.swift \
        Tests/UsageMeterCLITests/UsageStateLoaderTests.swift
git commit -m "Read the state file and classify its failures"
```

---

### Task 5: Versioned JSON output

**Files:**
- Modify: `Package.swift`
- Create: `Sources/UsageMeterCLI/UsageReportDocument.swift`
- Create: `Tests/UsageMeterCLITests/Fixtures/usage-report-v1.json`
- Test: `Tests/UsageMeterCLITests/UsageReportDocumentTests.swift`

**Interfaces:**
- Consumes: `UsageReport`, `UsageReportAccount` (Task 3).
- Produces:
  - `struct UsageReportDocument: Codable, Equatable` with nested
    `Account`, `Window`, `Balance`, and
    `init(report: UsageReport, generatedAt: Date)`
  - `static let UsageReportDocument.currentSchemaVersion = 1`
  - `static func UsageReportDocument.encoder() -> JSONEncoder`

Window field names mirror the existing `ProbeWindow`
(`durationSeconds`, `consumedPercent`, `remainingFraction`, `resetAt`,
`label`, `kind`) so the two machine-readable outputs agree, with `id`
added. Balance field names mirror `UsageBalance`'s own encoding
(`state`, `remainingAmount`, `unit`), except that `remainingAmount` is
a `Double` here rather than a `Decimal`, which keeps the published
schema free of Foundation's decimal encoding.

- [ ] **Step 1: Declare the fixtures directory**

Create the directory and tell SwiftPM about it. Both happen now, in the
task that produces the fixture.

```bash
mkdir -p Tests/UsageMeterCLITests/Fixtures
```

In `Package.swift`, extend the `UsageMeterCLITests` target so it reads:

```swift
        .testTarget(
            name: "UsageMeterCLITests",
            dependencies: ["UsageMeterCLI", "UsageMeterCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
```

That matches how `UsageMeterCoreTests` and `UsageMeterClaudeWebTests`
declare theirs.

- [ ] **Step 2: Write the document types**

Create `Sources/UsageMeterCLI/UsageReportDocument.swift`:

```swift
import Foundation
import UsageMeterCore

/// The command's published shape. Consumers depend on these names, so
/// treat a change to any of them as a schema version bump.
struct UsageReportDocument: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let generatedAt: Date
  let accounts: [Account]

  init(report: UsageReport, generatedAt: Date) {
    schemaVersion = Self.currentSchemaVersion
    self.generatedAt = generatedAt
    accounts = report.accounts.map(Account.init)
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  struct Account: Codable, Equatable {
    let id: UUID
    let provider: String
    let providerDisplayName: String
    let displayName: String
    let identity: String?
    let fetchedAt: Date?
    let windows: [Window]
    let balances: [Balance]

    init(account: UsageReportAccount) {
      id = account.accountID
      provider = account.provider.rawValue
      providerDisplayName = account.providerDisplayName
      displayName = account.displayName
      identity = account.identity
      fetchedAt = account.fetchedAt
      windows = account.windows.map(Window.init)
      balances = account.balances.map(Balance.init)
    }
  }

  struct Window: Codable, Equatable {
    let id: String
    let kind: String
    let label: String?
    let durationSeconds: Int
    let consumedPercent: Int
    let remainingFraction: Double
    let resetAt: Date?

    init(window: UsageWindow) {
      id = window.id
      kind = window.kind.rawValue
      label = window.label
      durationSeconds = Int(window.duration.rounded())
      consumedPercent = Int((window.consumedFraction * 100).rounded())
      remainingFraction = window.remainingFraction
      resetAt = window.resetAt
    }
  }

  struct Balance: Codable, Equatable {
    let id: String
    let label: String
    let state: String
    let remainingAmount: Double?
    let unit: String?
    let cycleEndsAt: Date?

    init(balance: UsageBalance) {
      id = balance.id
      label = balance.label
      cycleEndsAt = balance.cycleEndsAt
      // Both return nil unless the value is .available.
      remainingAmount = balance.remainingAmount
      unit = balance.unit
      state =
        switch balance.value {
        case .available: "available"
        case .unlimited: "unlimited"
        case .disabled: "disabled"
        }
    }
  }
}
```

- [ ] **Step 3: Generate the golden fixture from the code**

Hand-typing the fixture would mean guessing at ISO-8601 output and
sorted-key ordering. Generate it instead. Add this test temporarily to
`Tests/UsageMeterCLITests/UsageReportDocumentTests.swift`:

```swift
import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterCLI

@Suite
struct UsageReportDocumentFixtureWriter {
  @Test
  func writeGoldenFixture() throws {
    let document = UsageReportDocument(
      report: UsageReport(state: StateFixture.populatedState()),
      generatedAt: StateFixture.referenceDate
    )
    let destination = URL(filePath: #filePath)
      .deletingLastPathComponent()
      .appending(path: "Fixtures/usage-report-v1.json")

    try UsageReportDocument.encoder()
      .encode(document)
      .write(to: destination)
  }
}
```

`#filePath` resolves to this test file's own source location, so the
fixture lands in the source tree rather than in a build directory.

Run: `swift test --filter writeGoldenFixture`

- [ ] **Step 4: Read the generated fixture and approve it**

Run: `cat Tests/UsageMeterCLITests/Fixtures/usage-report-v1.json`

Check by eye against the spec:

- `schemaVersion` is `1`.
- Four accounts, ordered Claude/Work, Claude/Personal,
  Codex/Personal, Kimi.
- Claude/Personal has `"fetchedAt" : null`, `"windows" : []`,
  `"balances" : []`.
- Claude/Work's windows read `short` then `weekly`, with
  `consumedPercent` 61 and 44.
- `identity` is `"harper@example.com"` on Claude/Work and `null` on
  Claude/Personal.
- Balance `state` values read `available`, `unlimited`, `disabled`, and
  only the available one carries `remainingAmount` and `unit`.
- Every date is an ISO-8601 string.

If any of that is wrong, the implementation is wrong. Fix the code and
regenerate — never edit the fixture to match a bug.

- [ ] **Step 5: Replace the writer with the real tests**

Overwrite `Tests/UsageMeterCLITests/UsageReportDocumentTests.swift`,
deleting `UsageReportDocumentFixtureWriter` entirely:

```swift
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
```

Comparing `Data` rather than `String` keeps the test free of
trailing-newline guesswork: the fixture is exactly what the encoder
produces.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter UsageReportDocumentTests`
Expected: PASS, all four tests.

Run: `git grep -n writeGoldenFixture`
Expected: no output — the writer is gone.

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
        Sources/UsageMeterCLI/UsageReportDocument.swift \
        Tests/UsageMeterCLITests/UsageReportDocumentTests.swift \
        Tests/UsageMeterCLITests/Fixtures/usage-report-v1.json
git commit -m "Publish the usage report as versioned JSON"
```

---

### Task 6: Table and one-line rendering

**Files:**
- Create: `Sources/UsageMeterCLI/UsageTextReport.swift`
- Test: `Tests/UsageMeterCLITests/UsageTextReportTests.swift`

**Interfaces:**
- Consumes: `UsageReport`, `UsageReportAccount` (Task 3).
- Produces:
  - `static func UsageTextReport.table(_ report: UsageReport, now: Date) -> String`
  - `static func UsageTextReport.tightestLine(_ report: UsageReport, now: Date) -> String`
  - `static func UsageTextReport.relativeDuration(from now: Date, to date: Date?) -> String`
  - `static func UsageTextReport.balanceValueText(_ balance: UsageBalance) -> String`

`now` is a parameter, never `Date()`, so every expectation is exact.

- [ ] **Step 1: Write the failing tests**

Create `Tests/UsageMeterCLITests/UsageTextReportTests.swift`:

```swift
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
      ) == "Codex/Personal 78% · resets in 5d 1h"
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
```

The expected table above was computed by hand. If the real output
differs by a space, print it and correct the **expectation** — the
alignment code is what defines the layout.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageTextReportTests`
Expected: FAIL — `UsageTextReport` is undefined.

- [ ] **Step 3: Write the renderer**

Create `Sources/UsageMeterCLI/UsageTextReport.swift`:

```swift
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
          "\(percent(of: window))%",
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
    let head = "\(name(of: tightest.account)) \(percent(of: tightest.window))%"
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

  private static func percent(of window: UsageWindow) -> Int {
    Int((window.consumedFraction * 100).rounded())
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageTextReportTests`
Expected: PASS, all seven tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCLI/UsageTextReport.swift \
        Tests/UsageMeterCLITests/UsageTextReportTests.swift
git commit -m "Render the usage report as a table and a single line"
```

---

### Task 7: Wire up the entry point

**Files:**
- Modify: `Sources/UsageMeterCLI/UsageMeterCLI.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 through 6.
- Produces: the working command.

- [ ] **Step 1: Replace the placeholder entry point**

Rewrite `Sources/UsageMeterCLI/UsageMeterCLI.swift`:

```swift
import Darwin
import Foundation
import UsageMeterCore

@main
enum UsageMeterCLI {
  static let usage = """
    usage:
      usage-meter                  usage table
      usage-meter --json           machine-readable report
      usage-meter --tightest       the window with the least headroom
      usage-meter --help           this message

    options:
      --state-file <path>          read state from <path> instead of
                                   the application's own state file
    """

  static func main() async {
    do {
      switch try UsageMeterCLICommand.parse(
        arguments: CommandLine.arguments
      ) {
      case .help:
        writeStandardOutput(usage)
      case let .report(output, stateFileURL):
        try await report(
          output: output,
          stateFileURL: stateFileURL ?? AppStateStore.defaultFileURL()
        )
      }
    } catch UsageMeterCLICommandError.invalidArguments {
      writeStandardError(usage)
      Darwin.exit(EX_USAGE)
    } catch let error as UsageMeterCLIError {
      writeStandardError(message(for: error))
      Darwin.exit(exitCode(for: error))
    } catch {
      writeStandardError("could not read usage: \(error)")
      Darwin.exit(exitCode(for: error))
    }
  }

  private static func report(
    output: UsageMeterCLIOutput,
    stateFileURL: URL
  ) async throws {
    let report = UsageReport(
      state: try await UsageStateLoader.load(from: stateFileURL)
    )
    let now = Date()

    switch output {
    case .table:
      writeStandardOutput(UsageTextReport.table(report, now: now))
    case .tightest:
      writeStandardOutput(UsageTextReport.tightestLine(report, now: now))
    case .json:
      let data = try UsageReportDocument.encoder().encode(
        UsageReportDocument(report: report, generatedAt: now)
      )
      writeStandardOutput(String(decoding: data, as: UTF8.self))
    }
  }

  private static func message(
    for error: UsageMeterCLIError
  ) -> String {
    switch error {
    case let .stateFileMissing(url):
      "no state file at \(url.path); "
        + "open Agentic Usage Meter and connect an account"
    case .stateFileUnreadable:
      "the state file could not be decoded"
    }
  }

  /// An empty report prints nothing rather than a blank line, so a
  /// shell prompt embedding --tightest stays clean.
  private static func writeStandardOutput(_ message: String) {
    guard !message.isEmpty else {
      return
    }
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
  }

  private static func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }
}
```

- [ ] **Step 2: Verify the whole suite passes**

Run: `swift build && swift test`
Expected: build succeeds, every test passes, no new warnings.

- [ ] **Step 3: Exercise the failure paths**

```bash
swift run usage-meter --help
swift run usage-meter --state-file /nonexistent/state.json; echo "exit=$?"
swift run usage-meter --json --tightest; echo "exit=$?"
```

Expected: the usage text; then the missing-state message with
`exit=66`; then the usage text with `exit=64`.

- [ ] **Step 4: Exercise it against the real application state**

```bash
swift run usage-meter
swift run usage-meter --tightest
swift run usage-meter --json | jq -e '.schemaVersion == 1' >/dev/null \
  && echo "schema ok"
```

Expected: a table of the accounts this machine actually has, one
summary line, and `schema ok`. With no accounts connected, expect empty
output and exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCLI/UsageMeterCLI.swift
git commit -m "Wire the usage-meter command to its outputs"
```

---

### Task 8: Ship the command inside the bundle

**Files:**
- Modify: `Scripts/assemble-app.sh`
- Modify: `Scripts/sign-app.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: the `usage-meter` product (Task 2).
- Produces: `Contents/MacOS/usage-meter` inside the assembled, signed
  application.

Both scripts are `#!/bin/zsh` with `set -euo pipefail` and 4-space
indentation.

- [ ] **Step 1: Build and copy the second binary**

In `Scripts/assemble-app.sh`, after this line:

```sh
executable_name="AgenticUsageMeter"
```

add:

```sh
cli_name="usage-meter"
```

Immediately after the first `swift build` invocation — the one that
passes `--product "${executable_name}"` — add a second:

```sh
swift build \
    --package-path "${repository_root}" \
    --configuration "${configuration}" \
    --product "${cli_name}"
```

Then, after this existing line near the end:

```sh
/bin/chmod 755 "${contents_path}/MacOS/${executable_name}"
```

add:

```sh
/bin/cp \
    "${binary_directory}/${cli_name}" \
    "${contents_path}/MacOS/${cli_name}"
/bin/chmod 755 "${contents_path}/MacOS/${cli_name}"
```

- [ ] **Step 2: Sign it before the bundle**

In `Scripts/sign-app.sh`, insert this immediately **before** the
existing block that signs `Contents/MacOS/AgenticUsageMeter`. Nested
code must be signed before its container, which is why it cannot go
after.

```sh
"${codesign_bin}" \
    "${signing_arguments[@]}" \
    "${application_path}/Contents/MacOS/usage-meter"
```

- [ ] **Step 3: Assemble and verify the bundle**

```bash
CONFIGURATION=debug Scripts/assemble-app.sh
ls -l "build/Agentic Usage Meter.app/Contents/MacOS/"
"build/Agentic Usage Meter.app/Contents/MacOS/usage-meter" --help
```

Expected: both `AgenticUsageMeter` and `usage-meter` present and
executable, and the second prints its usage text.

- [ ] **Step 4: Verify the signature nests correctly**

```bash
codesign --force --options runtime --timestamp=none \
  --sign - "build/Agentic Usage Meter.app/Contents/MacOS/usage-meter"
codesign --force --options runtime --timestamp=none \
  --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 \
  "build/Agentic Usage Meter.app"
```

Expected: `valid on disk` and `satisfies its Designated Requirement`.

This signs ad-hoc on purpose, to prove the nesting order works without
depending on a certificate.
`Scripts/select-local-signing-identity.sh` requires exactly one
`Developer ID Application` identity, so `Scripts/build-and-run-local.sh`
may not be runnable on every machine. If it is available here, run it
too and confirm the application still launches.

- [ ] **Step 5: Document the command**

In `README.md`, insert a new section between `## Refresh behavior` and
`## Provider diagnostics`:

````markdown
## Terminal access

The application bundle includes a `usage-meter` command that prints the
quota picture the application last fetched. It reads the application's
state file and makes no network requests, so it returns immediately and
works whether or not the application is running.

```sh
"/Applications/Agentic Usage Meter.app/Contents/MacOS/usage-meter"
```

Link it onto your path to shorten that:

```sh
ln -s "/Applications/Agentic Usage Meter.app/Contents/MacOS/usage-meter" \
    /usr/local/bin/usage-meter
```

`usage-meter` prints a table. `usage-meter --json` prints a versioned
report for scripts. `usage-meter --tightest` prints one line for the
window with the least headroom, which suits a shell prompt or a status
line.

The command exits 66 when the application has never written its state
file and 65 when that file cannot be decoded, so a prompt can tell an
unconfigured application from a broken one.
````

- [ ] **Step 6: Run the full suite one last time**

Run: `swift build && swift test`
Expected: everything passes.

- [ ] **Step 7: Commit**

```bash
git add Scripts/assemble-app.sh Scripts/sign-app.sh README.md
git commit -m "Ship the usage-meter command in the application bundle"
```

---

## Verification Before Calling This Done

- [ ] `swift build` succeeds with no new warnings.
- [ ] `swift test` passes in full, including the pre-existing targets.
- [ ] `swift run usage-meter --json | jq -e '.schemaVersion == 1'` succeeds.
- [ ] `swift run usage-meter --state-file /nonexistent; echo $?` prints 66.
- [ ] The assembled bundle contains `Contents/MacOS/usage-meter`.
- [ ] `git grep -n ABOUTME -- Sources/UsageMeterCLI Tests/UsageMeterCLITests`
      finds nothing.
- [ ] `git grep -n writeGoldenFixture` finds nothing.
- [ ] `git log main..HEAD --format=%s | grep -E '^(feat|fix|chore|docs|refactor):'`
      finds nothing.
