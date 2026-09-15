import Darwin
import Foundation
import Testing
import UsageMeterCore

@Suite
struct UsageMeterCLIProcessTests {
  /// SwiftPM puts this target's resource bundle beside the executables it
  /// builds, so the binary is a sibling of `Bundle.module`.
  static let binaryURL = Bundle.module.bundleURL
    .deletingLastPathComponent()
    .appending(path: "usage-meter")

  @Test
  func helpExitsSuccessfullyAndWritesUsageToStandardOutput() throws {
    let result = try run(["--help"])

    #expect(result.exitCode == EX_OK)
    #expect(result.standardOutput.contains("usage-meter --tightest"))
    #expect(result.standardError.isEmpty)
  }

  @Test
  func anUnknownArgumentExitsUsageAndWritesUsageToStandardError() throws {
    let result = try run(["--bogus"])

    #expect(result.exitCode == EX_USAGE)
    #expect(result.standardError.contains("usage-meter --tightest"))
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func aMissingStateFileExitsNoInput() throws {
    let missing = URL.temporaryDirectory
      .appending(path: "usage-meter-tests-\(UUID().uuidString)/state.json")

    let result = try run(["--state-file", missing.path])

    #expect(result.exitCode == EX_NOINPUT)
  }

  @Test
  func anUndecodableStateFileExitsDataError() throws {
    let url = try StateFixture.write(StateFixture.emptyState())
    try Data("not valid json".utf8).write(to: url)

    let result = try run(["--state-file", url.path])

    #expect(result.exitCode == EX_DATAERR)
  }

  @Test
  func anEmptyStateFileIsAnEmptySuccessRatherThanABlankLine() throws {
    let url = try StateFixture.write(StateFixture.emptyState())

    let result = try run(["--state-file", url.path])

    #expect(result.exitCode == EX_OK)
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func tableAndTightestProduceDifferentShapes() throws {
    let url = try StateFixture.write(StateFixture.populatedState())

    let table = try run(["--state-file", url.path])
    let tightest = try run(["--state-file", url.path, "--tightest"])

    #expect(table.exitCode == EX_OK)
    #expect(tightest.exitCode == EX_OK)

    let tableLines = table.standardOutput.split(separator: "\n")
    let tightestLines = tightest.standardOutput.split(separator: "\n")

    #expect(tightestLines.count == 1)
    #expect(tableLines.count > tightestLines.count)
  }

  @Test
  func jsonOutputDecodesWithTheCurrentSchemaVersion() throws {
    let url = try StateFixture.write(StateFixture.populatedState())

    let result = try run(["--state-file", url.path, "--json"])

    #expect(result.exitCode == EX_OK)
    let document = try JSONDecoder().decode(
      SchemaVersionDocument.self,
      from: Data(result.standardOutput.utf8)
    )
    #expect(document.schemaVersion == 1)
  }

  private struct SchemaVersionDocument: Decodable {
    let schemaVersion: Int
  }

  private struct ProcessResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
  }

  private func run(_ arguments: [String]) throws -> ProcessResult {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = Self.binaryURL
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    return ProcessResult(
      exitCode: process.terminationStatus,
      standardOutput: String(
        decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      ),
      standardError: String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
    )
  }
}
