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
  func aStateFilePathThatIsActuallyAFlagIsARejectedArgument() {
    #expect(throws: UsageMeterCLICommandError.invalidArguments) {
      try UsageMeterCLICommand.parse(
        arguments: ["usage-meter", "--state-file", "--json"]
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
