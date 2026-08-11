import CircuiteFoundation
import DesignDatabaseCore
import Foundation

package enum DesignDatabaseRuntimeDependencyLockDirectory {
  package static func encode(
    _ lock: DesignDependencyLock
  ) throws(DesignDatabaseRuntimeError) -> String {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return String(decoding: try encoder.encode(lock), as: UTF8.self)
    } catch {
      throw .persistedStateCorrupt(
        reason: "The direct dependency lock could not be encoded canonically."
      )
    }
  }

  package static func decode(
    count: Int64,
    encoded: String,
    expectedRootDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDependencyLock {
    guard let expectedCount = Int(exactly: count), expectedCount >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest contains an invalid dependency-lock count."
      )
    }
    let lock: DesignDependencyLock
    do {
      lock = try JSONDecoder().decode(
        DesignDependencyLock.self,
        from: Data(encoded.utf8)
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A revision manifest contains a malformed direct dependency lock."
      )
    }
    guard lock.entries.count == expectedCount else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest dependency-lock count does not match its entries."
      )
    }
    let canonical = try encode(lock)
    guard canonical == encoded else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest dependency lock is not canonical."
      )
    }
    let actualRoot: ContentDigest
    do {
      actualRoot = try DesignDependencyLockDigest.root(lock, using: digester)
    } catch {
      throw .persistedStateCorrupt(
        reason: "A revision manifest dependency-lock root could not be verified."
      )
    }
    guard actualRoot == expectedRootDigest else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest dependency lock does not match its root digest."
      )
    }
    return lock
  }
}
