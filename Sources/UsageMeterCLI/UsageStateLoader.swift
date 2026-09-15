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
