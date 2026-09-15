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
