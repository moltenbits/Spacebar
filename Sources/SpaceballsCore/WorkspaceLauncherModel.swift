import Foundation

public enum WorkspaceLaunchType: String, Codable, CaseIterable, Identifiable, Sendable {
  case shell
  case applescript
  case open
  case launchServices

  public var id: String { rawValue }
}

public struct WorkspaceEnvironmentVariable: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var value: String

  public init(id: UUID = UUID(), name: String = "", value: String = "") {
    self.id = id
    self.name = name
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, value
  }
}

public struct WorkspaceLaunchServicesConfiguration: Codable, Equatable, Sendable {
  public var target: String
  public var arguments: [String]
  public var environment: [WorkspaceEnvironmentVariable]
  public var createsNewApplicationInstance: Bool

  public init(
    target: String = "",
    arguments: [String] = [],
    environment: [WorkspaceEnvironmentVariable] = [],
    createsNewApplicationInstance: Bool = false
  ) {
    self.target = target
    self.arguments = arguments
    self.environment = environment
    self.createsNewApplicationInstance = createsNewApplicationInstance
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment =
      try container.decodeIfPresent([WorkspaceEnvironmentVariable].self, forKey: .environment)
      ?? []
    createsNewApplicationInstance =
      try container.decodeIfPresent(Bool.self, forKey: .createsNewApplicationInstance) ?? false
  }

  private enum CodingKeys: String, CodingKey {
    case target, arguments, environment, createsNewApplicationInstance
  }
}

public enum WorkspaceLauncherAction: Equatable, Sendable {
  case shell(String)
  case appleScript(String)
  case openApplication(String)
  case launchServices(WorkspaceLaunchServicesConfiguration)

  public var type: WorkspaceLaunchType {
    switch self {
    case .shell: .shell
    case .appleScript: .applescript
    case .openApplication: .open
    case .launchServices: .launchServices
    }
  }

  public init(type: WorkspaceLaunchType, value: String) {
    switch type {
    case .shell:
      self = .shell(value)
    case .applescript:
      self = .appleScript(value)
    case .open:
      self = .openApplication(value)
    case .launchServices:
      self = .launchServices(WorkspaceLaunchServicesConfiguration(target: value))
    }
  }

  public static func empty(for type: WorkspaceLaunchType) -> WorkspaceLauncherAction {
    WorkspaceLauncherAction(type: type, value: "")
  }

  public func duplicated() -> WorkspaceLauncherAction {
    switch self {
    case .shell, .appleScript, .openApplication:
      return self
    case .launchServices(let configuration):
      return .launchServices(
        WorkspaceLaunchServicesConfiguration(
          target: configuration.target,
          arguments: configuration.arguments,
          environment: configuration.environment.map {
            WorkspaceEnvironmentVariable(name: $0.name, value: $0.value)
          },
          createsNewApplicationInstance: configuration.createsNewApplicationInstance))
    }
  }
}

extension WorkspaceLauncherAction: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case command
    case source
    case applicationName
    case configuration
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(WorkspaceLaunchType.self, forKey: .type)
    switch type {
    case .shell:
      self = .shell(try container.decodeIfPresent(String.self, forKey: .command) ?? "")
    case .applescript:
      self = .appleScript(try container.decodeIfPresent(String.self, forKey: .source) ?? "")
    case .open:
      self = .openApplication(
        try container.decodeIfPresent(String.self, forKey: .applicationName) ?? "")
    case .launchServices:
      self = .launchServices(
        try container.decodeIfPresent(
          WorkspaceLaunchServicesConfiguration.self, forKey: .configuration)
          ?? WorkspaceLaunchServicesConfiguration())
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    switch self {
    case .shell(let command):
      try container.encode(command, forKey: .command)
    case .appleScript(let source):
      try container.encode(source, forKey: .source)
    case .openApplication(let applicationName):
      try container.encode(applicationName, forKey: .applicationName)
    case .launchServices(let configuration):
      try container.encode(configuration, forKey: .configuration)
    }
  }
}

public struct WorkspaceLauncherStep: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var action: WorkspaceLauncherAction

  public var type: WorkspaceLaunchType { action.type }

  public init(id: UUID = UUID(), action: WorkspaceLauncherAction) {
    self.id = id
    self.action = action
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    action = try container.decode(WorkspaceLauncherAction.self, forKey: .action)
  }

  private enum CodingKeys: String, CodingKey {
    case id, action
  }

  public func duplicated() -> WorkspaceLauncherStep {
    WorkspaceLauncherStep(action: action.duplicated())
  }
}
