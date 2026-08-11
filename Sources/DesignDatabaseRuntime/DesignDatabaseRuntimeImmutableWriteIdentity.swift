public struct DesignDatabaseRuntimeImmutableWriteIdentity:
  Sendable,
  Hashable,
  Codable,
  Comparable
{
  public static let maximumComponentByteCount: UInt64 = 4_096
  public static let maximumPartitionCount: UInt64 = 32
  public static let maximumCanonicalByteCount: UInt64 = 65_536

  public let storageType: String
  public let partitionComponents: [String]
  public let modelID: String

  public init(
    storageType: String,
    partitionComponents: [String] = [],
    modelID: String
  ) throws(DesignDatabaseRuntimePreparedMutationError) {
    guard !storageType.isEmpty, !modelID.isEmpty else {
      throw .invalidImmutableWriteIdentity(
        reason: "A physical storage type and model identity must be nonempty."
      )
    }
    guard let partitionCount = UInt64(exactly: partitionComponents.count),
          partitionCount <= Self.maximumPartitionCount else {
      throw .invalidImmutableWriteIdentity(
        reason: "A physical partition directory exceeds its component limit."
      )
    }
    let components = [storageType] + partitionComponents + [modelID]
    var canonicalByteCount: UInt64 = 8
    for component in components {
      guard let byteCount = UInt64(exactly: component.utf8.count),
            byteCount > 0,
            byteCount <= Self.maximumComponentByteCount else {
        throw .invalidImmutableWriteIdentity(
          reason: "A physical identity component exceeds its byte limit."
        )
      }
      let (withLength, lengthOverflow) = canonicalByteCount
        .addingReportingOverflow(8)
      let (withComponent, componentOverflow) = withLength
        .addingReportingOverflow(byteCount)
      guard !lengthOverflow, !componentOverflow,
            withComponent <= Self.maximumCanonicalByteCount else {
        throw .invalidImmutableWriteIdentity(
          reason: "A physical identity exceeds its canonical byte limit."
        )
      }
      canonicalByteCount = withComponent
    }
    self.storageType = storageType
    self.partitionComponents = partitionComponents
    self.modelID = modelID
  }

  public static func < (
    lhs: DesignDatabaseRuntimeImmutableWriteIdentity,
    rhs: DesignDatabaseRuntimeImmutableWriteIdentity
  ) -> Bool {
    if lhs.storageType != rhs.storageType {
      return lhs.storageType < rhs.storageType
    }
    if lhs.partitionComponents != rhs.partitionComponents {
      return lhs.partitionComponents.lexicographicallyPrecedes(
        rhs.partitionComponents
      )
    }
    return lhs.modelID < rhs.modelID
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storageType = try container.decode(String.self, forKey: .storageType)
    let partitionComponents = try container.decode(
      [String].self,
      forKey: .partitionComponents
    )
    let modelID = try container.decode(String.self, forKey: .modelID)
    do {
      try self.init(
        storageType: storageType,
        partitionComponents: partitionComponents,
        modelID: modelID
      )
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: "Invalid immutable physical write identity."
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(storageType, forKey: .storageType)
    try container.encode(partitionComponents, forKey: .partitionComponents)
    try container.encode(modelID, forKey: .modelID)
  }

  package var canonicalBytes: [UInt8] {
    var bytes: [UInt8] = []
    append(UInt64(partitionComponents.count), to: &bytes)
    append(storageType, to: &bytes)
    for component in partitionComponents {
      append(component, to: &bytes)
    }
    append(modelID, to: &bytes)
    return bytes
  }

  private func append(_ value: String, to bytes: inout [UInt8]) {
    append(UInt64(value.utf8.count), to: &bytes)
    bytes.append(contentsOf: value.utf8)
  }

  private func append(_ value: UInt64, to bytes: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }

  private enum CodingKeys: String, CodingKey {
    case storageType
    case partitionComponents
    case modelID
  }
}
