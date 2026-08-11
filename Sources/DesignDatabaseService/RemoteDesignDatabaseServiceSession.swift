import CircuiteFoundation
import DesignDatabaseCore

public actor RemoteDesignDatabaseServiceSession: DesignDatabaseServiceSession {
  public nonisolated let id: DesignDatabaseServiceSessionID
  public nonisolated let databaseID: DesignDatabaseID
  public nonisolated let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public nonisolated let featureCapabilities: DesignCapabilitySet
  public nonisolated let authorizationGrants: DesignDatabaseAuthorizationGrantSet
  public nonisolated let genesisRevision: DesignRevisionReference

  private let client: DesignDatabaseServiceRemoteClient
  private var isClosed = false

  package init(
    descriptor: DesignDatabaseServiceRemoteSessionDescriptor,
    client: DesignDatabaseServiceRemoteClient
  ) {
    id = descriptor.id
    databaseID = descriptor.databaseID
    authorizationSubjectScopeID = descriptor.authorizationSubjectScopeID
    featureCapabilities = descriptor.featureCapabilities
    authorizationGrants = descriptor.authorizationGrants
    genesisRevision = descriptor.genesisRevision
    self.client = client
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionReference {
    try requireOpen()
    return try await client.call(
      operation: .resolve,
      input: DesignDatabaseServiceWirePayload.SessionValue(
        sessionID: id,
        value: selector
      )
    )
  }

  public func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseServiceError)
    -> DesignDatabaseServiceSnapshotDescriptor
  {
    try requireOpen()
    return try await client.call(
      operation: .openSnapshot,
      input: DesignDatabaseServiceWirePayload.OpenSnapshot(
        sessionID: id,
        revision: revision
      )
    )
  }

  public func closeSnapshot(
    _ snapshotID: DesignDatabaseServiceSnapshotID
  ) async throws(DesignDatabaseServiceError) -> DesignSnapshotTermination {
    try requireOpen()
    return try await client.call(
      operation: .closeSnapshot,
      input: DesignDatabaseServiceWirePayload.CloseSnapshot(
        sessionID: id,
        snapshotID: snapshotID
      )
    )
  }

  public func query(
    snapshotID: DesignDatabaseServiceSnapshotID,
    request: DesignQueryRequest
  ) async throws(DesignDatabaseServiceError) -> DesignQueryPage {
    try requireOpen()
    return try await client.query(
      DesignDatabaseServiceWirePayload.Query(
        sessionID: id,
        snapshotID: snapshotID,
        request: request
      )
    )
  }

  public func diff(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionDiff {
    try requireOpen()
    return try await sessionCall(operation: .diff, value: request)
  }

  public func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseServiceError) -> DesignDisjointMergeAssessment {
    try requireOpen()
    return try await sessionCall(operation: .assessDisjointMerge, value: request)
  }

  public func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseServiceError)
    -> DesignDisjointMergePublicationResult
  {
    try requireOpen()
    return try await sessionCall(
      operation: .publishDisjointMerge,
      value: submission
    )
  }

  public func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError)
    -> DesignDisjointMergePublicationStatus
  {
    try requireOpen()
    return try await statusCall(
      wireOperation: .disjointMergePublicationStatus,
      operation: operation,
      requestDigest: requestDigest
    )
  }

  public func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseServiceError) -> DesignCommitResult {
    try requireOpen()
    return try await sessionCall(operation: .submit, value: submission)
  }

  public func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignCommitStatus {
    try requireOpen()
    return try await statusCall(
      wireOperation: .commitStatus,
      operation: operation,
      requestDigest: requestDigest
    )
  }

  public func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateResult {
    try requireOpen()
    return try await sessionCall(
      operation: .compareAndSetReference,
      value: request
    )
  }

  public func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateStatus {
    try requireOpen()
    return try await statusCall(
      wireOperation: .referenceStatus,
      operation: operation,
      requestDigest: requestDigest
    )
  }

  public func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission {
    try requireOpen()
    return try await sessionCall(operation: .retain, value: request)
  }

  public func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission {
    try requireOpen()
    return try await sessionCall(operation: .releaseRetention, value: request)
  }

  public func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionStatus {
    try requireOpen()
    return try await statusCall(
      wireOperation: .retentionStatus,
      operation: operation,
      requestDigest: requestDigest
    )
  }

  package func markClosed() {
    isClosed = true
  }

  private func sessionCall<Input, Output>(
    operation: DesignDatabaseServiceWireOperation,
    value: Input,
    expecting outputType: Output.Type = Output.self
  ) async throws(DesignDatabaseServiceError) -> Output
  where Input: Sendable & Codable, Output: Sendable & Decodable {
    try await client.call(
      operation: operation,
      input: DesignDatabaseServiceWirePayload.SessionValue(
        sessionID: id,
        value: value
      )
    )
  }

  private func statusCall<Output>(
    wireOperation: DesignDatabaseServiceWireOperation,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    expecting outputType: Output.Type = Output.self
  ) async throws(DesignDatabaseServiceError) -> Output
  where Output: Sendable & Decodable {
    try await client.call(
      operation: wireOperation,
      input: DesignDatabaseServiceWirePayload.OperationStatus(
        sessionID: id,
        operation: operation,
        requestDigest: requestDigest
      )
    )
  }

  private func requireOpen() throws(DesignDatabaseServiceError) {
    guard !isClosed else { throw .closed }
  }
}
