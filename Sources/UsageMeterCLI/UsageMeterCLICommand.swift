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
