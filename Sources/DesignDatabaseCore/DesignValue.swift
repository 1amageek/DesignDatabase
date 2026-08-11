import CircuiteFoundation

public enum DesignValue: Sendable, Hashable, DesignDatabaseSerializable {
  case signed(Int64)
  case unsigned(UInt64)
  case real(Double)
  case boolean(Bool)
  case string(String)
  case digest(ContentDigest)
  case entity(DesignEntityKey)

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .signed: self = .signed(try container.decode(Int64.self, forKey: .signed))
    case .unsigned: self = .unsigned(try container.decode(UInt64.self, forKey: .unsigned))
    case .real:
      let value = try container.decode(Double.self, forKey: .real)
      guard value.isFinite else {
        throw DesignDatabaseError.invalidQuery("DesignValue.real must be finite.")
      }
      self = .real(value)
    case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
    case .string: self = .string(try container.decode(String.self, forKey: .string))
    case .digest: self = .digest(try container.decode(ContentDigest.self, forKey: .digest))
    case .entity: self = .entity(try container.decode(DesignEntityKey.self, forKey: .entity))
    }
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .signed(let value):
      try container.encode(Kind.signed, forKey: .kind)
      try container.encode(value, forKey: .signed)
    case .unsigned(let value):
      try container.encode(Kind.unsigned, forKey: .kind)
      try container.encode(value, forKey: .unsigned)
    case .real(let value):
      guard value.isFinite else {
        throw DesignDatabaseError.invalidQuery("DesignValue.real must be finite.")
      }
      try container.encode(Kind.real, forKey: .kind)
      try container.encode(value, forKey: .real)
    case .boolean(let value):
      try container.encode(Kind.boolean, forKey: .kind)
      try container.encode(value, forKey: .boolean)
    case .string(let value):
      try container.encode(Kind.string, forKey: .kind)
      try container.encode(value, forKey: .string)
    case .digest(let value):
      try container.encode(Kind.digest, forKey: .kind)
      try container.encode(value, forKey: .digest)
    case .entity(let value):
      try container.encode(Kind.entity, forKey: .kind)
      try container.encode(value, forKey: .entity)
    }
  }
#endif

  private enum Kind: String, DesignDatabaseSerializable {
    case signed, unsigned, real, boolean, string, digest, entity
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case kind, signed, unsigned, real, boolean, string, digest, entity
  }
#endif
}
