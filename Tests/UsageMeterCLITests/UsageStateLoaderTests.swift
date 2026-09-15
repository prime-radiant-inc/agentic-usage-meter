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
