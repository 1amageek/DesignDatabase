import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func reserveIdentities(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    validatedDirectory: DesignDatabaseRuntimeValidatedMutationDirectory,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws -> DesignDatabaseRuntimeReservedIdentities {
    let counts = try Self.identityCounts(in: submission.plan)
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    let submissionCapsule = try DesignDatabaseRuntimeCommitSubmissionCapsule(
      submission: submission,
      operation: operation,
      using: digester
    )
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existing = try await transaction.fetch(
          DesignIdentityReservationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingValidation = try await transaction.fetch(
          DesignValidatedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingSubmission = try await transaction.fetch(
          DesignCommitSubmissionModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        if let claim, let existing, let existingValidation,
           let existingSubmission {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            claim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
              operation: key
            )
          }
          let persistedValidation = try DesignDatabaseRuntimeValidatedMutationDirectory(
            model: existingValidation,
            operation: operation,
            submission: submission,
            using: digester
          )
          let persistedSubmission = try
            DesignDatabaseRuntimeCommitSubmissionCapsule(
              model: existingSubmission,
              operation: operation,
              expectedRequestDigest: submission.requestDigest,
              expectedPlanDigest: submission.plan.planDigest,
              using: digester
            )
          guard persistedValidation.digest == validatedDirectory.digest,
                persistedValidation.records == validatedDirectory.records,
                persistedSubmission.submission == submission,
                persistedSubmission.digest == submissionCapsule.digest else {
            throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
              operation: key
            )
          }
          return try Self.validateIdentityReservation(
            existing,
            operation: operation,
            submission: submission,
            counts: counts,
            validatedDirectory: persistedValidation,
            using: digester
          )
        }
        guard claim == nil, existing == nil, existingValidation == nil,
              existingSubmission == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit submission, validated mutation directory, identity reservation, and operation claim are not atomic."
          )
        }
        guard var allocator = try await transaction.fetch(
          DesignIdentityAllocatorStateModel.self,
          identifiedBy: "active",
          consistency: .serializable
        ), allocator.databaseID == operation.databaseID.description else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The database identity allocator is missing or belongs to another database."
          )
        }
        let entityRange = try Self.reserveRange(
          after: allocator.nextEntityValue,
          count: counts.entities,
          kind: "entity identity"
        )
        let occurrenceRange = try Self.reserveRange(
          after: allocator.nextRelationOccurrenceValue,
          count: counts.relationOccurrences,
          kind: "relation-occurrence identity"
        )
        let (nextGeneration, generationOverflow) = allocator.generation
          .addingReportingOverflow(1)
        guard !generationOverflow else {
          throw DesignDatabaseRuntimeError.generationExhausted(
            kind: "identity allocator"
          )
        }
        allocator.nextEntityValue = entityRange.last
        allocator.nextRelationOccurrenceValue = occurrenceRange.last
        allocator.generation = nextGeneration

        let reserved = try Self.makeReservedIdentities(
          plan: submission.plan,
          firstEntityValue: entityRange.first,
          firstRelationOccurrenceValue: occurrenceRange.first,
          using: digester
        )
        var reservation = DesignIdentityReservationModel()
        reservation.id = key
        reservation.databaseID = operation.databaseID.description
        reservation.subjectScopeID = operation.authorizationSubjectScopeID.description
        reservation.operationID = operation.operationID.rawValue
        reservation.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
        reservation.requestDigestValue = submission.requestDigest.hexadecimalValue
        reservation.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
        reservation.planDigestValue = submission.plan.planDigest.hexadecimalValue
        reservation.firstEntityValue = entityRange.first
        reservation.entityCount = counts.entities
        reservation.firstRelationOccurrenceValue = occurrenceRange.first
        reservation.relationOccurrenceCount = counts.relationOccurrences
        reservation.assignmentDigestAlgorithm = reserved.assignmentDigest.algorithm.rawValue
        reservation.assignmentDigestValue = reserved.assignmentDigest.hexadecimalValue
        reservation.validatedDirectoryDigestAlgorithm = validatedDirectory.digest.algorithm.rawValue
        reservation.validatedDirectoryDigestValue = validatedDirectory.digest.hexadecimalValue
        reservation.validatedMutationCount = UInt64(validatedDirectory.records.count)
        reservation.allocatorGeneration = nextGeneration

        try await transaction.save(allocator, precondition: .exists)
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(reservation, precondition: .notExists)
        try await transaction.save(
          submissionCapsule.model(operation: operation),
          precondition: .notExists
        )
        try await transaction.save(
          validatedDirectory.model(
            operation: operation,
            submission: submission
          ),
          precondition: .notExists
        )
        return reserved
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      throw DatabaseContextError.commitOutcomeUnknown
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw DesignDatabaseRuntimeError.commitTransactionFailed(
        reason: String(describing: error)
      )
    }
  }

  package static func validateIdentityReservationStatus(
    _ model: DesignIdentityReservationModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    validatedDirectoryDigest: ContentDigest,
    validatedMutationCount: UInt64
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue,
          model.validatedDirectoryDigestAlgorithm
            == validatedDirectoryDigest.algorithm.rawValue,
          model.validatedDirectoryDigestValue
            == validatedDirectoryDigest.hexadecimalValue,
          model.validatedMutationCount == validatedMutationCount,
          model.allocatorGeneration > 0 else {
      throw .commitIdempotencyConflict(operation: model.id)
    }
    try validateStoredRange(
      first: model.firstEntityValue,
      count: model.entityCount,
      kind: "entity identity"
    )
    try validateStoredRange(
      first: model.firstRelationOccurrenceValue,
      count: model.relationOccurrenceCount,
      kind: "relation-occurrence identity"
    )
    do {
      _ = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.assignmentDigestAlgorithm
        ),
        hexadecimalValue: model.assignmentDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "An identity reservation has an invalid assignment digest."
      )
    }
  }

  private static func validateIdentityReservation(
    _ model: DesignIdentityReservationModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    counts: (entities: UInt64, relationOccurrences: UInt64),
    validatedDirectory: DesignDatabaseRuntimeValidatedMutationDirectory,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeReservedIdentities {
    try validateIdentityReservationStatus(
      model,
      operation: operation,
      requestDigest: submission.requestDigest,
      validatedDirectoryDigest: validatedDirectory.digest,
      validatedMutationCount: UInt64(validatedDirectory.records.count)
    )
    guard model.planDigestAlgorithm == submission.plan.planDigest.algorithm.rawValue,
          model.planDigestValue == submission.plan.planDigest.hexadecimalValue,
          model.entityCount == counts.entities,
          model.relationOccurrenceCount == counts.relationOccurrences else {
      throw .commitIdempotencyConflict(operation: model.id)
    }
    let reserved = try makeReservedIdentities(
      plan: submission.plan,
      firstEntityValue: model.firstEntityValue,
      firstRelationOccurrenceValue: model.firstRelationOccurrenceValue,
      using: digester
    )
    guard model.assignmentDigestAlgorithm
            == reserved.assignmentDigest.algorithm.rawValue,
          model.assignmentDigestValue
            == reserved.assignmentDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "An identity reservation does not match its canonical assignments."
      )
    }
    return reserved
  }

  private static func identityCounts(
    in plan: DesignMutationPlan
  ) throws(DesignDatabaseRuntimeError) -> (
    entities: UInt64,
    relationOccurrences: UInt64
  ) {
    var entities: UInt64 = 0
    var occurrences: UInt64 = 0
    for segment in plan.segments {
      guard let segmentEntityCount = UInt64(
        exactly: segment.identityPlan.provisionalEntityIDs.count
      ), let segmentOccurrenceCount = UInt64(
        exactly: segment.identityPlan.provisionalRelationOccurrenceIDs.count
      ) else {
        throw .commitTransactionFailed(
          reason: "A mutation identity plan count is not representable."
        )
      }
      let (nextEntities, entityOverflow) = entities.addingReportingOverflow(
        segmentEntityCount
      )
      let (nextOccurrences, occurrenceOverflow) = occurrences
        .addingReportingOverflow(segmentOccurrenceCount)
      guard !entityOverflow, !occurrenceOverflow else {
        throw .generationExhausted(kind: "mutation identity count")
      }
      entities = nextEntities
      occurrences = nextOccurrences
    }
    return (entities, occurrences)
  }

  private static func reserveRange(
    after previous: UInt64,
    count: UInt64,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> (first: UInt64, last: UInt64) {
    guard count > 0 else { return (0, previous) }
    let (first, firstOverflow) = previous.addingReportingOverflow(1)
    let (last, lastOverflow) = previous.addingReportingOverflow(count)
    guard !firstOverflow, !lastOverflow, first > 0 else {
      throw .generationExhausted(kind: kind)
    }
    return (first, last)
  }

  private static func validateStoredRange(
    first: UInt64,
    count: UInt64,
    kind: String
  ) throws(DesignDatabaseRuntimeError) {
    if count == 0 {
      guard first == 0 else {
        throw .persistedStateCorrupt(
          reason: "An empty \(kind) reservation has a nonzero first value."
        )
      }
      return
    }
    let (_, overflow) = first.addingReportingOverflow(count - 1)
    guard first > 0, !overflow else {
      throw .persistedStateCorrupt(
        reason: "A persisted \(kind) reservation range is invalid."
      )
    }
  }

  private static func makeReservedIdentities(
    plan: DesignMutationPlan,
    firstEntityValue: UInt64,
    firstRelationOccurrenceValue: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeReservedIdentities {
    let counts = try identityCounts(in: plan)
    var nextEntityValue = firstEntityValue
    var nextOccurrenceValue = firstRelationOccurrenceValue
    var remainingEntityCount = counts.entities
    var remainingOccurrenceCount = counts.relationOccurrences
    var assignments: [
      DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
    ] = [:]
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.IdentityAssignments"
    )
    encoder.append(plan.planDigest)
    guard let segmentCount = UInt32(exactly: plan.segments.count) else {
      throw .commitTransactionFailed(
        reason: "The identity assignment segment count is not representable."
      )
    }
    encoder.append(segmentCount)
    for segment in plan.segments {
      var entityAssignments: [DesignEntityIdentityAssignment] = []
      entityAssignments.reserveCapacity(
        segment.identityPlan.provisionalEntityIDs.count
      )
      encoder.append(segment.id.rawValue)
      guard let segmentEntityCount = UInt32(
        exactly: segment.identityPlan.provisionalEntityIDs.count
      ), let segmentOccurrenceCount = UInt32(
        exactly: segment.identityPlan.provisionalRelationOccurrenceIDs.count
      ) else {
        throw .commitTransactionFailed(
          reason: "A segment identity assignment count is not representable."
        )
      }
      encoder.append(segmentEntityCount)
      for provisionalID in segment.identityPlan.provisionalEntityIDs {
        let permanentID: DesignEntityID
        do {
          permanentID = try DesignEntityID(rawValue: nextEntityValue)
        } catch {
          throw .persistedStateCorrupt(
            reason: "A reserved entity identity is invalid."
          )
        }
        entityAssignments.append(
          DesignEntityIdentityAssignment(
            provisionalID: provisionalID,
            permanentID: permanentID
          )
        )
        encoder.append(provisionalID.rawValue)
        encoder.append(permanentID.rawValue)
        remainingEntityCount -= 1
        if remainingEntityCount > 0 {
          let (next, overflow) = nextEntityValue.addingReportingOverflow(1)
          guard !overflow else {
            throw .generationExhausted(kind: "entity identity")
          }
          nextEntityValue = next
        }
      }

      var occurrenceAssignments: [
        DesignRelationOccurrenceIdentityAssignment
      ] = []
      occurrenceAssignments.reserveCapacity(
        segment.identityPlan.provisionalRelationOccurrenceIDs.count
      )
      encoder.append(segmentOccurrenceCount)
      for provisionalID in segment.identityPlan.provisionalRelationOccurrenceIDs {
        let permanentID: DesignRelationOccurrenceID
        do {
          permanentID = try DesignRelationOccurrenceID(
            rawValue: nextOccurrenceValue
          )
        } catch {
          throw .persistedStateCorrupt(
            reason: "A reserved relation-occurrence identity is invalid."
          )
        }
        occurrenceAssignments.append(
          DesignRelationOccurrenceIdentityAssignment(
            provisionalID: provisionalID,
            permanentID: permanentID
          )
        )
        encoder.append(provisionalID.rawValue)
        encoder.append(permanentID.rawValue)
        remainingOccurrenceCount -= 1
        if remainingOccurrenceCount > 0 {
          let (next, overflow) = nextOccurrenceValue
            .addingReportingOverflow(1)
          guard !overflow else {
            throw .generationExhausted(kind: "relation-occurrence identity")
          }
          nextOccurrenceValue = next
        }
      }
      do {
        assignments[segment.id] = try DesignMutationIdentityAssignments(
          entities: entityAssignments,
          relationOccurrences: occurrenceAssignments
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "Reserved mutation identities are not canonical."
        )
      }
    }
    return DesignDatabaseRuntimeReservedIdentities(
      assignments: assignments,
      assignmentDigest: try encoder.finalize(using: digester)
    )
  }
}
