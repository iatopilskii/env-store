public enum EnvironmentKeyRisk: String, Codable, CaseIterable, Sendable {
  case executableSearchPath = "executable_search_path"
  case dynamicLoader = "dynamic_loader"
  case identityContext = "identity_context"
  case temporaryDirectory = "temporary_directory"

  public static func classify(_ key: String) -> EnvironmentKeyRisk? {
    if key == "PATH" {
      return .executableSearchPath
    }

    if key == "HOME" || key == "SHELL" || key == "USER" || key == "LOGNAME" {
      return .identityContext
    }

    if key == "TMPDIR" {
      return .temporaryDirectory
    }

    if key.hasPrefix("DYLD_") || key.hasPrefix("LD_") {
      return .dynamicLoader
    }

    return nil
  }
}
