import CircuiteFoundation
import Database
import DatabaseWire
import DesignDatabaseCore

public struct DesignDatabaseRuntimeAttacher: Sendable {
  private let containerProvider: any DesignDatabaseRuntimeContainerProviding

  public init(
    containerProvider: any DesignDatabaseRuntimeContainerProviding
  ) {
    self.containerProvider = containerProvider
  }

  public func open(
    locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeAttachment {
    let owned: (any DesignDatabaseRuntimeOwnedContainer)?
    let container: DBContainer
    if let provider = containerProvider as? any DesignDatabaseRuntimeOwnedContainerProviding {
      let resource = try await provider.openOwnedContainer(for: locator, registration: registration)
      owned = resource
      container = resource.container
    } else {
      owned = nil
      container = try await containerProvider.openContainer(for: locator, registration: registration)
    }
    var attachment: DesignDatabaseRuntimeAttachment?
    do {
      let actualFingerprint = try Self.schemaFingerprint(container.schema)
      guard actualFingerprint == registration.schemaFingerprint else {
        throw DesignDatabaseRuntimeError.containerSchemaMismatch(
          expected: registration.schemaFingerprint.hexadecimalValue,
          actual: actualFingerprint.hexadecimalValue)
      }
      try container.runtimeConfiguration.validate(schema: registration.schema)
      let opened = DesignDatabaseRuntimeAttachment(locator: locator, registration: registration,
                                                   container: container, ownedContainer: owned)
      attachment = opened
      try await opened.validateCommitRecoveryBeforeServingOpens()
      try await opened.restoreCollectionAdmissionsBeforeServingOpens()
      return opened
    } catch {
      let primary = error
      if let attachment {
        if case .cleanupFailed(let reason) = await attachment.close() {
          throw .containerProviderFailed(reason: "Open failed: \(primary); cleanup failed: \(reason)")
        }
      } else {
        await container.shutdown()
        do { try await owned?.release() }
        catch { throw .containerProviderFailed(reason: "Open failed: \(primary); cleanup failed: \(error)") }
      }
      if let runtime = primary as? DesignDatabaseRuntimeError { throw runtime }
      throw .frameworkConfigurationFailed(reason: String(describing: primary))
    }
  }

  private static func schemaFingerprint(
    _ schema: Schema
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      let fingerprint = try SchemaManifest(schema: schema).fingerprint()
      let digits = Array("0123456789abcdef".utf8)
      var hexadecimal: [UInt8] = []
      hexadecimal.reserveCapacity(fingerprint.bytes.count * 2)
      for byte in fingerprint.bytes {
        hexadecimal.append(digits[Int(byte >> 4)])
        hexadecimal.append(digits[Int(byte & 0x0f)])
      }
      return try ContentDigest(
        algorithm: .sha256,
        hexadecimalValue: String(decoding: hexadecimal, as: UTF8.self)
      )
    } catch {
      throw .registrationDigestFailed(reason: String(describing: error))
    }
  }
}
