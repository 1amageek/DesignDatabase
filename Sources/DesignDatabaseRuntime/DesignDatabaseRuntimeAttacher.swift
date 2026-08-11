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
    let container = try await containerProvider.openContainer(
      for: locator,
      registration: registration
    )
    do {
      let actualFingerprint = try Self.schemaFingerprint(container.schema)
      guard actualFingerprint == registration.schemaFingerprint else {
        throw DesignDatabaseRuntimeError.containerSchemaMismatch(
          expected: registration.schemaFingerprint.hexadecimalValue,
          actual: actualFingerprint.hexadecimalValue
        )
      }
      try container.runtimeConfiguration.validate(schema: registration.schema)
      let attachment = DesignDatabaseRuntimeAttachment(
        locator: locator,
        registration: registration,
        container: container
      )
      try await attachment.validateCommitRecoveryBeforeServingOpens()
      try await attachment.restoreCollectionAdmissionsBeforeServingOpens()
      return attachment
    } catch let error as DesignDatabaseRuntimeError {
      await container.shutdown()
      throw error
    } catch {
      await container.shutdown()
      throw .frameworkConfigurationFailed(reason: String(describing: error))
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
