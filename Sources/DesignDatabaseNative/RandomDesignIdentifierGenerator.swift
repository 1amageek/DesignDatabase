import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public struct RandomDesignIdentifierGenerator: Sendable {
  public init() {}

  public func databaseID() throws(DesignDatabaseError) -> DesignDatabaseID {
    let words = words(from: UUID())
    do {
      return try DesignDatabaseID(high: words.high, low: words.low)
    } catch {
      throw .corruption("UUID generator produced the reserved zero database identity.")
    }
  }

  public func revisionID() -> DesignRevisionID {
    let words = words(from: UUID())
    return DesignRevisionID(high: words.high, low: words.low)
  }

  private func words(from uuid: UUID) -> (high: UInt64, low: UInt64) {
    let value = uuid.uuid
    let high = UInt64(value.0) << 56 | UInt64(value.1) << 48 | UInt64(value.2) << 40
      | UInt64(value.3) << 32 | UInt64(value.4) << 24 | UInt64(value.5) << 16
      | UInt64(value.6) << 8 | UInt64(value.7)
    let low = UInt64(value.8) << 56 | UInt64(value.9) << 48 | UInt64(value.10) << 40
      | UInt64(value.11) << 32 | UInt64(value.12) << 24 | UInt64(value.13) << 16
      | UInt64(value.14) << 8 | UInt64(value.15)
    return (high, low)
  }
}
