import DesignDatabaseCore

package struct DesignProjectionPhysicalProfile: Sendable, Hashable {
  package static let checkedDefault = DesignProjectionPhysicalProfile(
    codecVersion: DesignProjectionPhysicalCodecVersion(major: 2, minor: 0),
    maximumLeafEntryCount: 64,
    minimumLeafEntryCount: 32,
    maximumInternalChildCount: 64,
    minimumInternalChildCount: 32,
    maximumNodePayloadByteCount: 49_152
  )

  package let codecVersion: DesignProjectionPhysicalCodecVersion
  package let maximumLeafEntryCount: Int
  package let minimumLeafEntryCount: Int
  package let maximumInternalChildCount: Int
  package let minimumInternalChildCount: Int
  package let maximumNodePayloadByteCount: Int

  package init(
    codecVersion: DesignProjectionPhysicalCodecVersion,
    maximumLeafEntryCount: Int,
    minimumLeafEntryCount: Int,
    maximumInternalChildCount: Int,
    minimumInternalChildCount: Int,
    maximumNodePayloadByteCount: Int
  ) {
    precondition(maximumLeafEntryCount >= 2)
    precondition(minimumLeafEntryCount >= 1)
    precondition(minimumLeafEntryCount <= maximumLeafEntryCount / 2 + 1)
    precondition(maximumInternalChildCount >= 2)
    precondition(minimumInternalChildCount >= 2)
    precondition(
      minimumInternalChildCount <= maximumInternalChildCount / 2 + 1
    )
    precondition(maximumNodePayloadByteCount > 0)
    self.codecVersion = codecVersion
    self.maximumLeafEntryCount = maximumLeafEntryCount
    self.minimumLeafEntryCount = minimumLeafEntryCount
    self.maximumInternalChildCount = maximumInternalChildCount
    self.minimumInternalChildCount = minimumInternalChildCount
    self.maximumNodePayloadByteCount = maximumNodePayloadByteCount
  }
}
