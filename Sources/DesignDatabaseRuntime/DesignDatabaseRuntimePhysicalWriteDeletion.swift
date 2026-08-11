import Database

public enum DesignDatabaseRuntimePhysicalWriteDeletion {
  public static func requirePartitionComponents(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    storageType: String,
    count: Int
  ) throws(DesignDatabaseRuntimePhysicalWriteReclaimerError) -> [String] {
    guard identity.storageType == storageType,
          identity.partitionComponents.count == count else {
      throw .identityBindingMismatch(
        reason: "The immutable write identity does not match the registered storage and partition contract."
      )
    }
    return identity.partitionComponents
  }

  public static func delete<Model: Persistable>(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    model: Model.Type,
    identifiedBy modelID: Model.ID,
    in partition: DirectoryPath<Model>,
    expectedIdentity: (Model) throws -> DesignDatabaseRuntimeImmutableWriteIdentity,
    from transaction: any DatabaseTransactionWriting
  ) async throws(DesignDatabaseRuntimePhysicalWriteReclaimerError) {
    do {
      guard let persisted = try await transaction.fetch(
        model,
        identifiedBy: modelID,
        in: partition,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimePhysicalWriteReclaimerError
          .persistedWriteNotFound(identity: identity.modelID)
      }
      guard try expectedIdentity(persisted) == identity else {
        throw DesignDatabaseRuntimePhysicalWriteReclaimerError
          .identityBindingMismatch(
            reason: "The persisted immutable write does not match its collection identity."
          )
      }
      try await transaction.delete(persisted, precondition: .exists)
    } catch let error as DesignDatabaseRuntimePhysicalWriteReclaimerError {
      throw error
    } catch {
      throw .deleteFailed(reason: String(describing: error))
    }
  }

  public static func delete<Model: Persistable>(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    model: Model.Type,
    identifiedBy modelID: Model.ID,
    expectedIdentity: (Model) throws -> DesignDatabaseRuntimeImmutableWriteIdentity,
    from transaction: any DatabaseTransactionWriting
  ) async throws(DesignDatabaseRuntimePhysicalWriteReclaimerError) {
    do {
      guard let persisted = try await transaction.fetch(
        model,
        identifiedBy: modelID,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimePhysicalWriteReclaimerError
          .persistedWriteNotFound(identity: identity.modelID)
      }
      guard try expectedIdentity(persisted) == identity else {
        throw DesignDatabaseRuntimePhysicalWriteReclaimerError
          .identityBindingMismatch(
            reason: "The persisted immutable write does not match its collection identity."
          )
      }
      try await transaction.delete(persisted, precondition: .exists)
    } catch let error as DesignDatabaseRuntimePhysicalWriteReclaimerError {
      throw error
    } catch {
      throw .deleteFailed(reason: String(describing: error))
    }
  }
}
