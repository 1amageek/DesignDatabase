import DesignDatabaseCore

public enum DesignDatabaseCorePortabilityProbeOutput {
  public static func make() throws -> String {
    let locator = try DesignDatabaseLocator(
      namespace: "lsi",
      segments: ["portability", "core"]
    )
    let operationID = try DesignDatabaseOperationID(
      rawValue: "agent-operation"
    )
    let referenceName = try DesignReferenceName(rawValue: "candidate/main")
    let key = try DesignCanonicalKey(bytes: [0, 1, 2, 3])
    let outerBounds = try DesignIntegerBounds(
      minimumX: -10,
      minimumY: -20,
      maximumX: 30,
      maximumY: 40
    )
    let innerBounds = try DesignIntegerBounds(
      minimumX: 0,
      minimumY: 0,
      maximumX: 10,
      maximumY: 10
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .proposeCandidate,
    ])

    guard locator.namespace == "lsi",
          locator.segments == ["portability", "core"],
          operationID.rawValue == "agent-operation",
          referenceName.rawValue == "candidate/main",
          key.bytes == [0, 1, 2, 3],
          outerBounds.contains(innerBounds),
          outerBounds.intersects(innerBounds),
          grants.grants == [.proposeCandidate, .read] else {
      throw DesignDatabaseCorePortabilityProbeError.valueMismatch
    }

    return [
      "DesignDatabaseCorePortabilityProbe",
      locator.namespace,
      locator.segments.joined(separator: "."),
      operationID.rawValue,
      referenceName.rawValue,
      "key4",
      grants.grants.map { $0.rawValue }.joined(separator: ","),
    ].joined(separator: ":")
  }
}

private enum DesignDatabaseCorePortabilityProbeError: Error {
  case valueMismatch
}
