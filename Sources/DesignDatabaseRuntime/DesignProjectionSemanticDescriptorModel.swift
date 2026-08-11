import Database

@Persistable
package struct DesignProjectionSemanticDescriptorModel {
  #Directory<DesignProjectionSemanticDescriptorModel>(
    "design-database",
    "projection-semantic-descriptor"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var revisionID: String = ""
  package var family: String = ""
  package var semanticVersionMajor: Int64 = 0
  package var semanticVersionMinor: Int64 = 0
  package var entryCount: String = ""
  package var minimumKey: String = ""
  package var maximumKey: String = ""
  package var sequenceDigestAlgorithm: String = ""
  package var sequenceDigestValue: String = ""
  package var accumulatorFirst: String = ""
  package var accumulatorSecond: String = ""
  package var descriptorDigestAlgorithm: String = ""
  package var descriptorDigestValue: String = ""
}
