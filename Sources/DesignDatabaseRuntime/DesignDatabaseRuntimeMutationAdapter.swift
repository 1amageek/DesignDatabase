import CircuiteFoundation
import DesignDatabaseCore

public protocol DesignDatabaseRuntimeMutationAdapter: Sendable {
  var schemaID: DesignSchemaID { get }
  var schemaVersion: SchemaVersion { get }
  var adapterVersion: String { get }
  var supportedFacets: Set<DesignFacetID> { get }

  /// Validates a mutation against its exact immutable base revision and
  /// returns the complete opaque input required for deterministic
  /// materialization. Runtime invokes this only before claiming the operation.
  func validate(
    _ segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationValidation
  ) async throws(DesignDatabaseRuntimeMutationAdapterError)
    -> DesignDatabaseRuntimeValidatedMutation

  /// Materializes a persisted validated input without reading canonical state,
  /// invoking tools, emitting events, or repeating domain validation.
  func materializeValidatedMutation(
    _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
    for segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationRestoration
  ) throws(DesignDatabaseRuntimeMutationAdapterError)
    -> any DesignDatabaseRuntimePreparedMutation
}
