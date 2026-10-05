import CircuiteFoundation

/// Preserves the existing Runtime admission encoding and persisted request identities.
public enum DesignRevisionCollectionDigest {
  public static func request(operation: DesignDatabaseOperationReference,
                             revisions: [DesignRevisionReference],
                             using digester: any ContentDigesting) throws(DesignDatabaseError) -> ContentDigest {
    guard !revisions.isEmpty, Set(revisions).count == revisions.count,
          revisions.allSatisfy({ $0.databaseID == operation.databaseID }) else {
      throw .invalidMutationPlan(reason: "Collection requires unique exact revisions in one database.")
    }
    var bytes: [UInt8] = []
    func appendInteger(_ value: UInt64, width: Int) {
      for index in (0..<width).reversed() { bytes.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
    func appendString(_ value: String) {
      appendInteger(UInt64(value.utf8.count), width: 4)
      bytes.append(contentsOf: value.utf8)
    }
    appendString("DesignDatabase.CollectionAdmissionRequest")
    appendInteger(1, width: 2)
    appendString(operation.databaseID.description)
    appendString(operation.authorizationSubjectScopeID.description)
    appendString(operation.operationID.rawValue)
    appendInteger(UInt64(revisions.count), width: 8)
    for revision in revisions.sorted(by: { $0.revisionID.description < $1.revisionID.description }) {
      appendString(revision.revisionID.description)
    }
    do {
      let count = max(UInt64(bytes.count), 1)
      let limits = try ContentDigestSessionLimits(maximumChunkByteCount: count, maximumTotalByteCount: count, maximumUpdateCount: 1)
      return try digester.digest(using: .sha256, limits: limits) {
        (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(bytes)
      }.digest
    } catch { throw .contentDigest(String(describing: error)) }
  }
}
