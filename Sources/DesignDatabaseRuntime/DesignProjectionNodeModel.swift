import Database

@Persistable
package struct DesignProjectionNodeModel {
  #Directory<DesignProjectionNodeModel>(
    "design-database",
    "projection-node"
  )

  package var id: String = ""
  package var family: String = ""
  package var physicalCodecMajor: Int64 = 0
  package var physicalCodecMinor: Int64 = 0
  package var physicalProfileDigestAlgorithm: String = ""
  package var physicalProfileDigestValue: String = ""
  package var nodeKind: Int64 = 0
  package var level: Int64 = 0
  package var minimumKey: String = ""
  package var maximumKey: String = ""
  package var subtreeEntryCount: String = ""
  package var subtreeNodeCount: String = ""
  package var itemCount: Int64 = 0
  package var payload: ByteString = ByteString()
  package var encodedByteCount: String = ""
}
