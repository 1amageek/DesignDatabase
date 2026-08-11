import CircuiteFoundation
import Database

public struct DesignDatabaseRuntimeReadSnapshot: Sendable {
  public let revision: DesignRevisionReference

  private let context: DatabaseContext
  private let budget: DesignDatabaseRuntimeValidationReadBudget

  package init(
    context: DatabaseContext,
    revision: DesignRevisionReference,
    maximumReadCount: UInt64
  ) {
    self.revision = revision
    self.context = context
    self.budget = DesignDatabaseRuntimeValidationReadBudget(
      limit: maximumReadCount
    )
  }

  package func close() async {
    await budget.close()
  }

  public func fetch<Model: Persistable>(
    _ type: Model.Type,
    identifiedBy id: Model.ID,
    consistency: DatabaseReadConsistency = .serializable
  ) async throws -> Model? {
    try await budget.reserve(1)
    return try await DesignDatabaseRuntimeStorageSecurity.withAuthorizedAccess {
      try await context.withTransaction { transaction in
        try await transaction.fetch(
          type,
          identifiedBy: id,
          consistency: consistency
        )
      }
    }
  }

  public func fetch<Model: Persistable>(
    _ type: Model.Type,
    identifiedBy id: Model.ID,
    in partition: DirectoryPath<Model>,
    consistency: DatabaseReadConsistency = .serializable
  ) async throws -> Model? {
    try await budget.reserve(1)
    return try await DesignDatabaseRuntimeStorageSecurity.withAuthorizedAccess {
      try await context.withTransaction { transaction in
        try await transaction.fetch(
          type,
          identifiedBy: id,
          in: partition,
          consistency: consistency
        )
      }
    }
  }

  public func scan<Model: Persistable>(
    _ type: Model.Type,
    in partition: DirectoryPath<Model> = DirectoryPath<Model>(),
    after continuation: DatabaseScanContinuation? = nil,
    limit: Int,
    consistency: DatabaseReadConsistency = .serializable
  ) async throws -> DesignDatabaseRuntimeReadPage<Model> {
    guard limit > 0 else {
      throw DesignDatabaseRuntimeReadError.invalidReadCount(limit)
    }
    guard let requested = UInt64(exactly: limit) else {
      throw DesignDatabaseRuntimeReadError.invalidReadCount(limit)
    }
    try await budget.reserve(requested)
    return try await DesignDatabaseRuntimeStorageSecurity.withAuthorizedAccess {
      try await context.withTransaction { transaction in
        let page = try await transaction.scan(
          type,
          in: partition,
          after: continuation,
          limit: limit,
          consistency: consistency
        )
        return DesignDatabaseRuntimeReadPage(
          items: page.items,
          continuation: page.continuation
        )
      }
    }
  }
}
