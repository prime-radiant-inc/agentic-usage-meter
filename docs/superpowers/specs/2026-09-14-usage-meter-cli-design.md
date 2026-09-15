# Usage Meter CLI

## Problem

Nothing outside the application can read its usage data. There is no
URL scheme, scripting dictionary, XPC service, or listening socket;
the only network listener is the one-shot OAuth redirect catcher.
`UsageMeterProbe` prints JSON but fetches live from providers through
its own Keychain service, so it cannot see configured accounts.

A shell prompt, a tmux status line, or an agent's status display has
nowhere to ask what the quota picture looks like.

## Design

A `usage-meter` command reads the application's state file and prints
it. No daemon, no socket, and no second file on disk: the command's
`--json` output is the contract.

The command ships inside the application bundle and compiles from the
same source tree, so it decodes `PersistedAppState` directly and moves
with it. Pinning a published schema to a file on disk would instead
freeze an internal format that should stay free to change.
`AppStateStore` writes through a temporary file and `rename`, so a
concurrent read returns either the previous state or the next one,
never a torn one.

`AgenticUsageMeterApp.stateFileURL` moves to `AppStateStore` as
`defaultFileURL`, so the application and the command resolve one path
rather than two copies of the same logic. `--state-file` overrides it.

Three outputs:

- No flag: an aligned table, one row per usage window.
- `--json`: the whole picture, `schemaVersion` 1, ISO-8601 dates,
  sorted keys.
- `--tightest`: one line for the window with the least headroom.

The table carries provider, account, window, percentage used, and time
until reset. Rows sort by the catalog's provider order, then by the
account's display order, then by window duration ascending, so a
five-hour window precedes the weekly one that contains it. Provider
names render from `ProviderCatalog.live` so the command and the
interface agree.

Snapshots carry balances as well as windows, and Extra Credits is a
section of the interface, so the command reports them too. JSON
carries each balance's label and value, including the unlimited and
disabled states the domain model distinguishes from a zero amount. The
table prints balances as their own lines below the window rows, and
only when an account has any, rather than bending window columns
around a quantity that is not a percentage.

JSON carries the account identifier as well as the display name, so a
script can key on an account that gets renamed.

`--tightest` calls `UsageSummary.tightestWindow`, the ranking the menu
bar label already uses: lowest remaining fraction, ties broken by the
soonest reset and then the window identifier. It ranks windows only; a
balance has no fraction to compare. The line reads as provider,
account, percentage used, and time until reset, short enough for a
prompt.

Account records carry the authenticated identity, and `--json`
includes it. The table does not: display names exist so that a glance
does not have to read an address, and `--tightest` often feeds a
prompt that is visible over someone's shoulder.

An account with no snapshot yet appears in the table with an em dash,
appears in JSON with an empty window list and a null fetch time, and
is skipped by `--tightest`. Having no accounts at all is an empty
success rather than a failure.

Exit codes separate an unconfigured application from a broken one:
`EX_NOINPUT` when the state file is absent, `EX_DATAERR` when it will
not decode, `EX_USAGE` for bad arguments, `EX_UNAVAILABLE` otherwise.

Arguments parse by hand into a separately testable type, the shape
`UsageMeterProbe` already uses. The package gains no dependency.

Target `UsageMeterCLI` builds as product `usage-meter`, keeping the
target name in the convention the package uses and giving the binary
the name a person types. `assemble-app.sh` builds the second product
and copies it to `Contents/MacOS/usage-meter`; `sign-app.sh` signs it
before the bundle, in the nested-first order it already uses for
Sparkle. The README documents the path and a symlink. The application
gains no installer interface, which would cost a settings pane and a
privilege prompt to save one `ln -s`.

## Out of scope

A desktop widget reads the same data, but it needs a sandboxed
extension and a signing decision that belongs to the project owner.
Designing it here would guess at that decision. Nothing in this design
blocks it.

Refreshing on demand is also excluded. The command reports what the
application last fetched, and the application governs refresh.

## Testing

Fixture state files drive every case through `--state-file`, so no
test substitutes a fake store.

Argument parsing covers each flag, unknown flags, and a missing
`--state-file` value. Projection tests cover sort order across
providers, accounts, and window durations; an account without a
snapshot; and identity present and absent. A golden fixture pins the
schema-1 JSON, including a balance in each of the available,
unlimited, and disabled states. Table tests cover column alignment
against long display names, the balance lines, and the empty state.
`--tightest` tests cover selection across accounts, the tie broken by
reset time, and the case where no account has a window. Exit-code
tests cover an absent state file and an undecodable one.
