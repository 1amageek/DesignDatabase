public enum DesignValueKind: String, Sendable, Hashable, DesignDatabaseSerializable {
  case signed
  case unsigned
  case real
  case boolean
  case string
  case digest
  case entity

  public func accepts(_ value: DesignValue) -> Bool {
    switch (self, value) {
    case (.signed, .signed), (.unsigned, .unsigned), (.real, .real), (.boolean, .boolean),
      (.string, .string), (.digest, .digest), (.entity, .entity):
      return true
    default:
      return false
    }
  }
}
