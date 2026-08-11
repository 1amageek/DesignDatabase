import Database

@Persistable
package struct DesignRuntimeRegistrationModel {
  #Directory<DesignRuntimeRegistrationModel>("design-database", "runtime-registration")

  package var id: String = "active"
  package var schemaFingerprintAlgorithm: String = ""
  package var schemaFingerprintValue: String = ""
  package var registrationDigestAlgorithm: String = ""
  package var registrationDigestValue: String = ""
  package var contributionCount: Int64 = 0
}
