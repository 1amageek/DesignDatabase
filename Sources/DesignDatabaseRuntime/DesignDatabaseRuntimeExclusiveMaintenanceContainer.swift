/// Issued only after exclusive access among all participating backing opens succeeds.
/// All readers and collectors share this resource's attachment until release.
public protocol DesignDatabaseRuntimeExclusiveMaintenanceContainer: DesignDatabaseRuntimeOwnedContainer {}
