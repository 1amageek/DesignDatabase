import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionDecodedPageKey: Sendable, Hashable {
  package let family: DesignProjectionFamily
  package let physicalCodecVersion: DesignProjectionPhysicalCodecVersion
  package let physicalProfileDigest: ContentDigest
  package let nodeDigest: ContentDigest

  package init(
    family: DesignProjectionFamily,
    reference: DesignProjectionMaterializationReference,
    nodeDigest: ContentDigest
  ) {
    self.family = family
    self.physicalCodecVersion = reference.physicalCodecVersion
    self.physicalProfileDigest = reference.physicalProfileDigest
    self.nodeDigest = nodeDigest
  }

  package var canonicalSortKey: String {
    [
      family.rawValue,
      String(physicalCodecVersion.major),
      String(physicalCodecVersion.minor),
      physicalProfileDigest.algorithm.rawValue,
      physicalProfileDigest.hexadecimalValue,
      nodeDigest.algorithm.rawValue,
      nodeDigest.hexadecimalValue,
    ].joined(separator: "\u{1f}")
  }

  package var stableShardHash: UInt64 {
    var result: UInt64 = 14_695_981_039_346_656_037
    Self.update(&result, with: family.rawValue.utf8)
    Self.update(&result, with: physicalCodecVersion.major)
    Self.update(&result, with: physicalCodecVersion.minor)
    Self.update(&result, with: physicalProfileDigest.algorithm.rawValue.utf8)
    Self.update(&result, with: physicalProfileDigest.hexadecimalValue.utf8)
    Self.update(&result, with: nodeDigest.algorithm.rawValue.utf8)
    Self.update(&result, with: nodeDigest.hexadecimalValue.utf8)
    return result
  }

  private static func update<Bytes: Sequence>(
    _ hash: inout UInt64,
    with bytes: Bytes
  ) where Bytes.Element == UInt8 {
    for byte in bytes {
      hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  private static func update(_ hash: inout UInt64, with value: UInt16) {
    hash = (hash ^ UInt64(UInt8(truncatingIfNeeded: value >> 8)))
      &* 1_099_511_628_211
    hash = (hash ^ UInt64(UInt8(truncatingIfNeeded: value)))
      &* 1_099_511_628_211
  }
}
