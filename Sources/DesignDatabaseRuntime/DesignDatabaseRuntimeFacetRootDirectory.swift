import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeFacetRootDirectory {
  package static func encode(
    _ roots: [DesignFacetRoot]
  ) throws(DesignDatabaseRuntimeError) -> String {
    let canonical = try canonicalize(roots)
    return canonical.map { root in
      root.facetID.rawValue
        + "\t" + root.digest.algorithm.rawValue
        + "\t" + root.digest.hexadecimalValue
    }.joined(separator: "\n")
  }

  package static func decode(
    count: Int64,
    encoded: String
  ) throws(DesignDatabaseRuntimeError) -> [DesignFacetRoot] {
    guard let expectedCount = Int(exactly: count), expectedCount >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest contains an invalid facet-root count."
      )
    }
    let lines = encoded.isEmpty
      ? []
      : encoded.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == expectedCount else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest facet-root directory has the wrong count."
      )
    }
    let roots: [DesignFacetRoot]
    do {
      roots = try lines.map { line in
        let fields = line.split(
          separator: "\t",
          omittingEmptySubsequences: false
        )
        guard fields.count == 3 else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A revision manifest facet-root entry is malformed."
          )
        }
        return try DesignFacetRoot(
          facetID: DesignFacetID(rawValue: String(fields[0])),
          digest: ContentDigest(
            algorithm: ContentDigestAlgorithm(rawValue: String(fields[1])),
            hexadecimalValue: String(fields[2])
          )
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A revision manifest facet-root entry is invalid."
      )
    }
    let canonical = try canonicalize(roots)
    guard canonical == roots else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest facet-root directory is not canonical."
      )
    }
    return canonical
  }

  package static func replacing(
    _ base: [DesignFacetRoot],
    with replacements: [DesignFacetRoot]
  ) throws(DesignDatabaseRuntimeError) -> [DesignFacetRoot] {
    let canonicalBase = try canonicalize(base)
    let canonicalReplacements = try canonicalize(replacements)
    var rootsByFacet: [DesignFacetID: DesignFacetRoot] = [:]
    for root in canonicalBase {
      rootsByFacet[root.facetID] = root
    }
    for replacement in canonicalReplacements {
      rootsByFacet[replacement.facetID] = replacement
    }
    return try canonicalize(Array(rootsByFacet.values))
  }

  package static func stateDigest(
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    projectionSemantics: [DesignProjectionSemanticDescriptor] = [],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    let roots = try canonicalize(facetRoots)
    let projections = projectionSemantics.sorted()
    for index in projections.indices.dropFirst() where
      projections[index - 1].family == projections[index].family {
      throw .persistedStateCorrupt(
        reason: "A revision state contains duplicate projection semantics."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.RevisionState"
    )
    encoder.append(designSchemaBundleDigest)
    encoder.append(dependencyRootDigest)
    encoder.append(semanticDependencyGraphDigest)
    encoder.append(UInt32(roots.count))
    for root in roots {
      encoder.append(root.facetID.rawValue)
      encoder.append(root.digest)
    }
    encoder.append(UInt32(projections.count))
    for projection in projections {
      encoder.append(projection.family.rawValue)
      encoder.append(projection.semanticVersion.major)
      encoder.append(projection.semanticVersion.minor)
      encoder.append(projection.entryCount)
      encoder.append(projection.minimumKey == nil ? UInt16(0) : UInt16(1))
      if let minimumKey = projection.minimumKey {
        encoder.append(minimumKey.bytes)
      }
      encoder.append(projection.maximumKey == nil ? UInt16(0) : UInt16(1))
      if let maximumKey = projection.maximumKey {
        encoder.append(maximumKey.bytes)
      }
      encoder.append(projection.canonicalSequenceDigest)
    }
    return try encoder.finalize(using: digester)
  }

  private static func canonicalize(
    _ roots: [DesignFacetRoot]
  ) throws(DesignDatabaseRuntimeError) -> [DesignFacetRoot] {
    guard roots.count <= Int(UInt32.max) else {
      throw .persistedStateCorrupt(
        reason: "The facet-root directory exceeds the canonical count limit."
      )
    }
    do {
      return try DesignFacetRoot.canonicalizing(roots)
    } catch {
      throw .persistedStateCorrupt(reason: String(describing: error))
    }
  }
}
