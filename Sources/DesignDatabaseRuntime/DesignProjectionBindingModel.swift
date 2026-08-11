import Database

@Persistable
package struct DesignProjectionBindingModel {
  #Directory<DesignProjectionBindingModel>(
    "design-database",
    "projection-binding"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var revisionID: String = ""
  package var family: String = ""
  package var semanticDescriptorDigestAlgorithm: String = ""
  package var semanticDescriptorDigestValue: String = ""
  package var bindingGeneration: String = ""
  package var physicalCodecMajor: Int64 = 0
  package var physicalCodecMinor: Int64 = 0
  package var physicalProfileDigestAlgorithm: String = ""
  package var physicalProfileDigestValue: String = ""
  package var rootNodeDigestAlgorithm: String = ""
  package var rootNodeDigestValue: String = ""
}
