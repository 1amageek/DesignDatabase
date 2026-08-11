import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DatabaseWire
import DesignDatabaseCore

public struct DesignDatabaseRuntimeRegistrationBuilder: Sendable {
  private static let registrationFormatVersion: UInt16 = 2

  private let digester: any ContentDigesting

  public init(
    digester: any ContentDigesting = SHA256ContentDigester()
  ) {
    self.digester = digester
  }

  public func build(
    schemaVersion: Schema.Version,
    contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeRegistrationBundle {
    let orderedDomainContributions = contributions.sorted { $0.id < $1.id }
    let orderedContributions = try (
      [DesignDatabaseRuntimeCoreContribution.make()] + orderedDomainContributions
    ).sorted { $0.id < $1.id }
    try validateUniqueContributions(orderedContributions)
    let designSchemaBundle = try makeDesignSchemaBundle(
      contributions: orderedDomainContributions
    )

    let entities = orderedContributions
      .flatMap(\.entities)
      .sorted { $0.name < $1.name }
    try validateUniqueEntities(entities)

    let runtimes = orderedContributions
      .flatMap(\.entityRuntimes)
      .sorted { $0.entity.name < $1.entity.name }

    let schema: Schema
    do {
      schema = try Schema(entities: entities, version: schemaVersion)
    } catch {
      throw .schemaConstructionFailed(reason: String(describing: error))
    }

    let runtimeConfiguration: DatabaseRuntimeConfiguration
    do {
      runtimeConfiguration = try DatabaseFrameworkRuntime.configuration(
        entityRuntimes: runtimes
      )
      try runtimeConfiguration.validate(schema: schema)
    } catch {
      throw .frameworkConfigurationFailed(reason: String(describing: error))
    }

    let schemaFingerprint = try makeSchemaFingerprint(schema)
    let registrationDigest = try makeRegistrationDigest(
      schemaFingerprint: schemaFingerprint,
      designSchemaBundleDigest: designSchemaBundle.rootDigest,
      contributions: orderedContributions
    )
    let mutationAdapters = try makeMutationAdapters(orderedContributions)
    let physicalWriteReclaimers = try makePhysicalWriteReclaimers(
      orderedContributions
    )
    return DesignDatabaseRuntimeRegistrationBundle(
      schema: schema,
      runtimeConfiguration: runtimeConfiguration,
      contributionIDs: orderedContributions.map(\.id),
      schemaFingerprint: schemaFingerprint,
      designSchemaBundle: designSchemaBundle,
      registrationDigest: registrationDigest,
      mutationAdapters: mutationAdapters,
      physicalWriteReclaimers: physicalWriteReclaimers
    )
  }

  private func makePhysicalWriteReclaimers(
    _ contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError)
    -> [String: any DesignDatabaseRuntimePhysicalWriteReclaimer]
  {
    var reclaimers: [
      String: any DesignDatabaseRuntimePhysicalWriteReclaimer
    ] = [:]
    for reclaimer in contributions.flatMap(\.physicalWriteReclaimers) {
      guard !reclaimer.storageType.isEmpty else {
        throw .invalidPhysicalWriteReclaimer(storageType: reclaimer.storageType)
      }
      guard reclaimers[reclaimer.storageType] == nil else {
        throw .duplicatePhysicalWriteReclaimer(
          storageType: reclaimer.storageType
        )
      }
      reclaimers[reclaimer.storageType] = reclaimer
    }
    return reclaimers
  }

  private func makeMutationAdapters(
    _ contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError)
    -> [DesignSchemaID: any DesignDatabaseRuntimeMutationAdapter] {
    var adapters: [DesignSchemaID: any DesignDatabaseRuntimeMutationAdapter] = [:]
    for adapter in contributions.compactMap(\.mutationAdapter) {
      guard adapters[adapter.schemaID] == nil else {
        throw .duplicateMutationAdapter(adapter.schemaID)
      }
      adapters[adapter.schemaID] = adapter
    }
    return adapters
  }

  private func validateUniqueContributions(
    _ contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError) {
    for index in contributions.indices.dropFirst() {
      if contributions[index - 1].id == contributions[index].id {
        throw .duplicateContribution(contributions[index].id)
      }
    }
  }

  private func validateUniqueEntities(
    _ entities: [Schema.Entity]
  ) throws(DesignDatabaseRuntimeError) {
    for index in entities.indices.dropFirst() {
      if entities[index - 1].name == entities[index].name {
        throw .duplicateEntity(name: entities[index].name)
      }
    }
  }

  private func makeSchemaFingerprint(
    _ schema: Schema
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      let fingerprint = try SchemaManifest(schema: schema).fingerprint()
      return try ContentDigest(
        algorithm: .sha256,
        hexadecimalValue: Self.hexadecimal(fingerprint.bytes)
      )
    } catch {
      throw .registrationDigestFailed(reason: String(describing: error))
    }
  }

  private func makeRegistrationDigest(
    schemaFingerprint: ContentDigest,
    designSchemaBundleDigest: ContentDigest,
    contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var bytes: [UInt8] = []
    Self.append("DesignDatabase.RuntimeRegistration", to: &bytes)
    Self.append(Self.registrationFormatVersion, to: &bytes)
    Self.append(schemaFingerprint.algorithm.rawValue, to: &bytes)
    Self.append(schemaFingerprint.hexadecimalValue, to: &bytes)
    Self.append(designSchemaBundleDigest.algorithm.rawValue, to: &bytes)
    Self.append(designSchemaBundleDigest.hexadecimalValue, to: &bytes)
    Self.append(UInt32(contributions.count), to: &bytes)
    for contribution in contributions {
      Self.append(contribution.id.rawValue, to: &bytes)
      Self.append(contribution.bindingDigest.algorithm.rawValue, to: &bytes)
      Self.append(contribution.bindingDigest.hexadecimalValue, to: &bytes)
      let storageTypes = contribution.physicalWriteReclaimers
        .map(\.storageType)
        .sorted()
      Self.append(UInt32(storageTypes.count), to: &bytes)
      for storageType in storageTypes {
        Self.append(storageType, to: &bytes)
      }
    }

    do {
      let byteCount = UInt64(bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(byteCount, 1),
        maximumTotalByteCount: max(byteCount, 1),
        maximumUpdateCount: 1
      )
      let result = try digester.digest(
        using: .sha256,
        limits: limits
      ) { (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(bytes)
      }
      return result.digest
    } catch {
      throw .registrationDigestFailed(reason: String(describing: error))
    }
  }

  private func makeDesignSchemaBundle(
    contributions: [DesignDatabaseRuntimeContribution]
  ) throws(DesignDatabaseRuntimeError) -> DesignSchemaBundle {
    let members = contributions.compactMap(\.designSchemaMember).sorted()
    precondition(members.count == contributions.count)
    for index in members.indices.dropFirst() {
      if members[index - 1].schemaID == members[index].schemaID {
        throw .duplicateDesignSchema(members[index].schemaID)
      }
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.DesignSchemaBundle"
    )
    encoder.append(UInt32(members.count))
    for member in members {
      encoder.append(member.schemaID.rawValue)
      encoder.append(member.version.major)
      encoder.append(member.version.minor)
      encoder.append(member.version.patch)
      encoder.append(member.canonicalDigest)
    }
    let rootDigest = try encoder.finalize(using: digester)
    do {
      return try DesignSchemaBundle(members: members, rootDigest: rootDigest)
    } catch {
      throw .registrationDigestFailed(reason: String(describing: error))
    }
  }

  private static func append(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  private static func append(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  private static func append(_ value: String, to bytes: inout [UInt8]) {
    let encoded = Array(value.utf8)
    precondition(encoded.count <= Int(UInt32.max))
    append(UInt32(encoded.count), to: &bytes)
    bytes.append(contentsOf: encoded)
  }

  private static func hexadecimal<Bytes: Collection>(_ bytes: Bytes) -> String
  where Bytes.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var encoded: [UInt8] = []
    encoded.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      encoded.append(digits[Int(byte >> 4)])
      encoded.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: encoded, as: UTF8.self)
  }
}
