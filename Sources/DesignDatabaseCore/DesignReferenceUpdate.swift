import CircuiteFoundation

public struct DesignReferenceUpdate: Sendable, Hashable, Codable {
  public let name: DesignReferenceName
  public let previous: DesignRevisionReference?
  public let current: DesignRevisionReference

  public init(
    name: DesignReferenceName,
    previous: DesignRevisionReference?,
    current: DesignRevisionReference
  ) {
    self.name = name
    self.previous = previous
    self.current = current
  }
}
