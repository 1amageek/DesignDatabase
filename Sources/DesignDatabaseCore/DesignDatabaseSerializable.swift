#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
public typealias DesignDatabaseSerializable = Codable
#else
public protocol DesignDatabaseSerializable {}
#endif
