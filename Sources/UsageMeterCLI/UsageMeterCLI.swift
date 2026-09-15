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
