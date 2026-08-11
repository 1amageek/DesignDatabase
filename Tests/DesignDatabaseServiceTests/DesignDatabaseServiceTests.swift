import CircuiteFoundation
import DesignDatabaseCore
import DesignDatabaseService
import Foundation
import Testing

@Suite
struct DesignDatabaseServiceTests {
  @Test
  func decodedServiceInputsReapplyPublicInvariants() throws {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDatabaseServiceSessionID.self,
        from: Data("0".utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDatabaseServiceSnapshotID.self,
        from: Data("0".utf8)
      )
    }
    let invalidSessionConfiguration = InvalidServiceSessionConfiguration(
      leaseDuration: .seconds(1),
      maximumInFlightOperationCount: 0
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDatabaseServiceSessionConfiguration.self,
        from: JSONEncoder().encode(invalidSessionConfiguration)
      )
    }
  }

  @Test
  func remoteDispatcherRejectsScopeMisroutingAndUnqualifiedShutdown() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(fixture: fixture, blocksResolve: false)
    let localService = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 1
      )
    )
    let configuration = try DesignDatabaseServiceRemoteConfiguration(
      wireCodecBudget: DesignDatabaseServiceWireCodecBudget(
        maximumFrameByteCount: 65_536,
        maximumMetadataByteCount: 8_192,
        maximumPayloadByteCount: 32_768
      ),
      queryPageCodecBudget: DesignDatabaseServiceQueryPageCodecBudget(
        maximumFrameByteCount: 32_768,
        maximumMetadataByteCount: 8_192,
        maximumRowCount: 16
      ),
      requestTimeout: .seconds(2)
    )
    let wrongScope = try DesignAuthorizationSubjectScopeID(high: 9, low: 9)
    let dispatcher = DesignDatabaseServiceRemoteDispatcher(
      service: localService,
      subjectContext: DesignDatabaseServiceAuthenticatedSubjectContext(
        authorizationSubjectScopeID: wrongScope
      ),
      configuration: configuration
    )
    let transport = LoopbackDesignDatabaseServiceWireTransport(
      dispatcher: dispatcher,
      codecBudget: configuration.wireCodecBudget
    )
    let remote = RemoteDesignDatabaseService(
      transport: transport,
      configuration: configuration
    )
    do {
      _ = try await remote.openSession(
        configuration: DesignDatabaseServiceSessionConfiguration(
          leaseDuration: .seconds(60),
          maximumInFlightOperationCount: 1
        )
      )
      Issue.record("A dispatcher accepted a session for another subject scope.")
    } catch let error {
      guard case .transport(.protocolViolation) = error else {
        Issue.record("Unexpected subject-scope routing error: \(error)")
        return
      }
    }
    await #expect(
      throws: DesignDatabaseServiceError.database(
        .unauthorized(grant: .administer, subjectScopeID: wrongScope)
      )
    ) {
      _ = try await remote.shutdown()
    }

    let localSession = try await localService.openSession(
      configuration: DesignDatabaseServiceSessionConfiguration(
        leaseDuration: .seconds(60),
        maximumInFlightOperationCount: 1
      )
    )
    #expect(await localService.closeSession(localSession.id) == .closed)
    #expect(await localService.shutdown() == .closed)
  }

  @Test
  func processWireTransportCrossesARealProcessAndEnforcesDeadline() async throws {
    let budget = try DesignDatabaseServiceWireCodecBudget(
      maximumFrameByteCount: 16_384,
      maximumMetadataByteCount: 8_192,
      maximumPayloadByteCount: 8_192
    )
    let request = try DesignDatabaseServiceWireMessage(
      requestID: 1,
      operation: .negotiate,
      kind: .request,
      payloadFormat: .json,
      payload: [0x7b, 0x7d]
    )
    let frame = try DesignDatabaseServiceWireCodec.encode(
      request,
      budget: budget
    )
    let echoTransport = try DesignDatabaseServiceProcessWireTransport(
      executableURL: URL(fileURLWithPath: "/bin/cat"),
      maximumFrameByteCount: budget.maximumFrameByteCount
    )
    #expect(
      try await echoTransport.exchange(
        frame,
        timeout: .seconds(2)
      ) == frame
    )
    try await echoTransport.close()

    let stalledTransport = try DesignDatabaseServiceProcessWireTransport(
      executableURL: URL(fileURLWithPath: "/usr/bin/tail"),
      arguments: ["-f", "/dev/null"],
      maximumFrameByteCount: budget.maximumFrameByteCount
    )
    await #expect(throws: DesignDatabaseServiceWireTransportError.deadlineExceeded) {
      _ = try await stalledTransport.exchange(
        frame,
        timeout: .milliseconds(50)
      )
    }
    try await stalledTransport.close()

    let uncooperativeTransport = try DesignDatabaseServiceProcessWireTransport(
      executableURL: URL(fileURLWithPath: "/usr/bin/tail"),
      arguments: ["-f", "/dev/null"],
      maximumFrameByteCount: budget.maximumFrameByteCount,
      closeGracePeriod: .milliseconds(50)
    )
    await #expect(throws: DesignDatabaseServiceWireTransportError.self) {
      try await uncooperativeTransport.close()
    }
  }

  @Test
  func standardIOHostDispatchesAndTerminatesOnTypedShutdown() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(fixture: fixture, blocksResolve: false)
    let localService = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 1
      )
    )
    let remoteConfiguration = try DesignDatabaseServiceRemoteConfiguration(
      wireCodecBudget: DesignDatabaseServiceWireCodecBudget(
        maximumFrameByteCount: 65_536,
        maximumMetadataByteCount: 8_192,
        maximumPayloadByteCount: 32_768
      ),
      queryPageCodecBudget: DesignDatabaseServiceQueryPageCodecBudget(
        maximumFrameByteCount: 32_768,
        maximumMetadataByteCount: 8_192,
        maximumRowCount: 16
      ),
      requestTimeout: .seconds(2)
    )
    let dispatcher = DesignDatabaseServiceRemoteDispatcher(
      service: localService,
      subjectContext: DesignDatabaseServiceAuthenticatedSubjectContext(
        authorizationSubjectScopeID: fixture.subjectScopeID,
        serviceShutdownAuthorized: true
      ),
      configuration: remoteConfiguration
    )
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let hostTask = Task {
      try await DesignDatabaseServiceStandardIOHost.run(
        dispatcher: dispatcher,
        wireCodecBudget: remoteConfiguration.wireCodecBudget,
        input: inputPipe.fileHandleForReading,
        output: outputPipe.fileHandleForWriting
      )
    }
    let payload = Array(
      try JSONEncoder().encode(
        DesignDatabaseServiceWirePayload.Empty()
      )
    )
    let request = try DesignDatabaseServiceWireMessage(
      requestID: 1,
      operation: .shutdown,
      kind: .request,
      payloadFormat: .json,
      payload: payload
    )
    let requestFrame = try DesignDatabaseServiceWireCodec.encode(
      request,
      budget: remoteConfiguration.wireCodecBudget
    )
    try inputPipe.fileHandleForWriting.write(
      contentsOf: DesignDatabaseServiceLengthPrefixedFrameIO.encoded(
        requestFrame,
        maximumFrameByteCount:
          remoteConfiguration.wireCodecBudget.maximumFrameByteCount
      )
    )
    var responseIterator = outputPipe.fileHandleForReading.bytes
      .makeAsyncIterator()
    let responseFrame = try #require(
      try await DesignDatabaseServiceLengthPrefixedFrameIO.read(
        from: &responseIterator,
        maximumFrameByteCount:
          remoteConfiguration.wireCodecBudget.maximumFrameByteCount
      )
    )
    let response = try DesignDatabaseServiceWireCodec.decode(
      responseFrame,
      budget: remoteConfiguration.wireCodecBudget
    )
    #expect(response.requestID == request.requestID)
    #expect(response.operation == .shutdown)
    #expect(response.kind == .success)
    #expect(response.payloadFormat == .json)
    #expect(
      try JSONDecoder().decode(
        DesignDatabaseTermination.self,
        from: Data(response.payload)
      ) == .closed
    )
    #expect(try await hostTask.value == .serviceShutdown)
    try inputPipe.fileHandleForWriting.close()
    try inputPipe.fileHandleForReading.close()
    try outputPipe.fileHandleForWriting.close()
    try outputPipe.fileHandleForReading.close()
  }

  @Test
  func remoteProxyExecutesTypedSessionLineageOverVersionedFrames() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(fixture: fixture, blocksResolve: false)
    let localService = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 2
      )
    )
    let remoteConfiguration = try DesignDatabaseServiceRemoteConfiguration(
      wireCodecBudget: DesignDatabaseServiceWireCodecBudget(
        maximumFrameByteCount: 1_048_576,
        maximumMetadataByteCount: 16_384,
        maximumPayloadByteCount: 1_000_000
      ),
      queryPageCodecBudget: DesignDatabaseServiceQueryPageCodecBudget(
        maximumFrameByteCount: 1_000_000,
        maximumMetadataByteCount: 16_384,
        maximumRowCount: 1_024
      ),
      requestTimeout: .seconds(5)
    )
    let dispatcher = DesignDatabaseServiceRemoteDispatcher(
      service: localService,
      subjectContext: DesignDatabaseServiceAuthenticatedSubjectContext(
        authorizationSubjectScopeID: fixture.subjectScopeID,
        serviceShutdownAuthorized: true
      ),
      configuration: remoteConfiguration
    )
    let transport = LoopbackDesignDatabaseServiceWireTransport(
      dispatcher: dispatcher,
      codecBudget: remoteConfiguration.wireCodecBudget
    )
    let remote = RemoteDesignDatabaseService(
      transport: transport,
      configuration: remoteConfiguration
    )

    let negotiation = try await remote.negotiate(
      DesignServiceNegotiationRequest(
        requiredSchemas: [
          DesignSchemaRequirement(
            schemaID: fixture.schema.schemaID,
            versions: try SchemaVersionRange(
              lowerBound: .v1,
              upperBound: SchemaVersion(major: 2, minor: 0, patch: 0)
            )
          ),
        ],
        requiredCapabilities: []
      )
    )
    #expect(negotiation.report.isCompatible)
    let session = try await remote.openSession(
      configuration: DesignDatabaseServiceSessionConfiguration(
        leaseDuration: .seconds(60),
        maximumInFlightOperationCount: 2
      )
    )
    #expect(session.databaseID == fixture.databaseID)
    #expect(session.authorizationSubjectScopeID == fixture.subjectScopeID)
    #expect(try await session.resolve(.named(.main)) == fixture.genesis)

    let snapshot = try await session.openSnapshot(at: fixture.genesis)
    let page = try await session.query(
      snapshotID: snapshot.snapshotID,
      request: DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: DesignQueryBudget(
          maximumResultCount: 1,
          maximumNodeFetchCount: 1,
          maximumEncodedReadByteCount: 1,
          maximumDecodedByteCount: 1,
          maximumOutputByteCount: 1,
          maximumWorkCount: 1
        )
      )
    )
    #expect(page.revision == fixture.genesis)
    #expect(page.rows.isEmpty)
    #expect(page.completion == .sourceExhausted)
    #expect(try await session.closeSnapshot(snapshot.snapshotID) == .closed)
    await #expect(throws: DesignDatabaseServiceError.snapshotNotFound(snapshot.snapshotID)) {
      _ = try await session.query(
        snapshotID: snapshot.snapshotID,
        request: DesignQueryRequest(
          family: .facet,
          maximumPageResultCount: 1,
          budget: DesignQueryBudget(
            maximumResultCount: 1,
            maximumNodeFetchCount: 1,
            maximumEncodedReadByteCount: 1,
            maximumDecodedByteCount: 1,
            maximumOutputByteCount: 1,
            maximumWorkCount: 1
          )
        )
      )
    }

    let submission = try fixture.commitSubmission(operation: "remote-commit")
    let receipt: DesignCommitReceipt
    switch try await session.submit(submission) {
    case .committed(let value):
      receipt = value
    case .rejected(let rejection):
      Issue.record("A remote commit was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("A remote commit outcome was unknown.")
      return
    }
    #expect(
      try await remote.closeSession(session.id) == .closed
    )
    await #expect(throws: DesignDatabaseServiceError.closed) {
      _ = try await session.resolve(.named(.main))
    }

    let replacementSession = try await remote.openSession(
      configuration: DesignDatabaseServiceSessionConfiguration(
        leaseDuration: .seconds(60),
        maximumInFlightOperationCount: 2
      )
    )
    #expect(
      try await replacementSession.commitStatus(
        operation: receipt.operation,
        requestDigest: receipt.requestDigest
      ) == .committed(receipt)
    )
    #expect(
      try await remote.closeSession(replacementSession.id) == .closed
    )
    #expect(try await remote.shutdown() == .closed)
    let observedSuccessfulQueryPage = await transport.observedSuccessfulQueryPage
    let transportIsClosed = await transport.isClosed
    #expect(observedSuccessfulQueryPage)
    #expect(transportIsClosed)
  }

  @Test
  func serviceWireCodecBindsOperationIdentityAndPayloadIntegrity() throws {
    let budget = try DesignDatabaseServiceWireCodecBudget(
      maximumFrameByteCount: 16_384,
      maximumMetadataByteCount: 8_192,
      maximumPayloadByteCount: 8_192
    )
    let message = try DesignDatabaseServiceWireMessage(
      requestID: 9,
      operation: .query,
      kind: .success,
      payloadFormat: .queryPageV1,
      payload: [0x01, 0x02, 0x03]
    )
    let frame = try DesignDatabaseServiceWireCodec.encode(
      message,
      budget: budget
    )
    #expect(
      try DesignDatabaseServiceWireCodec.decode(
        frame,
        budget: budget
      ) == message
    )

    var tamperedFrame = frame
    tamperedFrame[tamperedFrame.index(before: tamperedFrame.endIndex)] ^= 0xff
    do {
      _ = try DesignDatabaseServiceWireCodec.decode(
        tamperedFrame,
        budget: budget
      )
      Issue.record("A service wire frame accepted a modified payload.")
    } catch let error {
      guard case .payloadDigestMismatch = error else {
        Issue.record("Unexpected service payload-integrity error: \(error)")
        return
      }
    }

    #expect(throws: DesignDatabaseServiceWireCodecError.self) {
      _ = try DesignDatabaseServiceWireMessage(
        requestID: 9,
        operation: .submit,
        kind: .request,
        payloadFormat: .queryPageV1,
        payload: [0x01]
      )
    }

    let restrictivePayloadBudget = try DesignDatabaseServiceWireCodecBudget(
      maximumFrameByteCount: 16_384,
      maximumMetadataByteCount: 8_192,
      maximumPayloadByteCount: 2
    )
    #expect(
      throws: DesignDatabaseServiceWireCodecError.budgetExceeded(
        kind: "payload bytes",
        limit: 2,
        requested: 3
      )
    ) {
      _ = try DesignDatabaseServiceWireCodec.decode(
        frame,
        budget: restrictivePayloadBudget
      )
    }
  }

  @Test
  func serviceErrorsPreserveTypedPayloadsAcrossSerialization() throws {
    let fixture = try ServiceFixture()
    let errors: [DesignDatabaseServiceError] = [
      .backpressure(limit: 4),
      .snapshotNotFound(
        try DesignDatabaseServiceSnapshotID(rawValue: 7)
      ),
      .database(
        .schemaContract(
          .duplicateSchema(try DesignSchemaID(rawValue: "lsi.service"))
        )
      ),
      .database(.revisionNotFound(fixture.genesis)),
      .transport(.deadlineExceeded),
      .transport(.invalidFrame(.unsupportedVersion(2))),
    ]

    let encoded = try JSONEncoder().encode(errors)
    #expect(
      try JSONDecoder().decode(
        [DesignDatabaseServiceError].self,
        from: encoded
      ) == errors
    )
  }

  @Test
  func versionedBinaryQueryPageCodecRoundTripsAndRejectsMalformedFrames()
    throws
  {
    let fixture = try ServiceFixture()
    let materialization = try DesignProjectionMaterializationReference(
      semanticDescriptorDigest: fixture.stateDigest,
      bindingGeneration: 1,
      physicalCodecVersion: DesignProjectionPhysicalCodecVersion(
        major: 1,
        minor: 0
      ),
      physicalProfileDigest: fixture.dependencyDigest,
      rootNodeDigest: fixture.directChangeDigest
    )
    let page = try DesignQueryPage(
      revision: fixture.genesis,
      designSchemaBundleDigest: fixture.schemaDigest,
      projectionSemanticDigest: fixture.stateDigest,
      materialization: materialization,
      rows: [
        try DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [0x01]),
          value: [0x10, 0x11]
        ),
        try DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [0x02]),
          value: [0x20, 0x21, 0x22]
        ),
      ],
      continuation: nil,
      completion: .sourceExhausted,
      report: DesignQueryResourceReport(
        resultCount: 2,
        nodeFetchCount: 1,
        encodedReadByteCount: 5,
        decodedByteCount: 5,
        outputByteCount: 5,
        workCount: 2
      )
    )
    let budget = try DesignDatabaseServiceQueryPageCodecBudget(
      maximumFrameByteCount: 16_384,
      maximumMetadataByteCount: 8_192,
      maximumRowCount: 16
    )
    let frame = try DesignDatabaseServiceQueryPageCodec.encode(
      page,
      budget: budget
    )
    #expect(
      try DesignDatabaseServiceQueryPageCodec.decode(
        frame,
        budget: budget
      ) == page
    )

    var unsupportedVersionFrame = frame
    unsupportedVersionFrame[4] = 0
    unsupportedVersionFrame[5] = 2
    #expect(throws: DesignDatabaseServiceQueryPageCodecError.unsupportedVersion(2)) {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        unsupportedVersionFrame,
        budget: budget
      )
    }

    #expect(throws: DesignDatabaseServiceQueryPageCodecError.truncated) {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        Array(frame.dropLast()),
        budget: budget
      )
    }

    var frameWithTrailingByte = frame
    frameWithTrailingByte.append(0)
    #expect(throws: DesignDatabaseServiceQueryPageCodecError.trailingBytes(1)) {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        frameWithTrailingByte,
        budget: budget
      )
    }

    let restrictiveFrameBudget = try DesignDatabaseServiceQueryPageCodecBudget(
      maximumFrameByteCount: UInt64(frame.count - 1),
      maximumMetadataByteCount: 8_192,
      maximumRowCount: 16
    )
    #expect(
      throws: DesignDatabaseServiceQueryPageCodecError.budgetExceeded(
        kind: "frame bytes",
        limit: UInt64(frame.count - 1),
        requested: UInt64(frame.count)
      )
    ) {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        frame,
        budget: restrictiveFrameBudget
      )
    }

    let restrictiveMetadataBudget = try DesignDatabaseServiceQueryPageCodecBudget(
      maximumFrameByteCount: 16_384,
      maximumMetadataByteCount: 1,
      maximumRowCount: 16
    )
    let metadataByteCount = frame[8..<16].reduce(UInt64(0)) {
      ($0 << 8) | UInt64($1)
    }
    #expect(
      throws: DesignDatabaseServiceQueryPageCodecError.budgetExceeded(
        kind: "metadata bytes",
        limit: 1,
        requested: metadataByteCount
      )
    ) {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        frame,
        budget: restrictiveMetadataBudget
      )
    }

    var duplicateKeyFrame = frame
    let firstRowOffset = 24 + Int(metadataByteCount)
    let firstRowKeyByteCount = 1
    let firstRowValueByteCount = 2
    let secondRowOffset = firstRowOffset
      + 12
      + firstRowKeyByteCount
      + firstRowValueByteCount
    duplicateKeyFrame[secondRowOffset + 12] = 0x01
    do {
      _ = try DesignDatabaseServiceQueryPageCodec.decode(
        duplicateKeyFrame,
        budget: budget
      )
      Issue.record("A binary query page accepted duplicate canonical keys.")
    } catch let error {
      guard case .invalidPage = error else {
        Issue.record("Unexpected duplicate-key error: \(error)")
        return
      }
    }
  }

  @Test
  func exactHandleSessionOwnsSnapshotsAndExposesOutcomeReconciliation() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(fixture: fixture, blocksResolve: false)
    let service = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 2
      )
    )
    let negotiation = try await service.negotiate(
      DesignServiceNegotiationRequest(
        requiredSchemas: [
          DesignSchemaRequirement(
            schemaID: fixture.schema.schemaID,
            versions: try SchemaVersionRange(
              lowerBound: .v1,
              upperBound: SchemaVersion(major: 2, minor: 0, patch: 0)
            )
          ),
        ],
        requiredCapabilities: []
      )
    )
    #expect(negotiation.report.isCompatible)

    let session = try await service.openSession(
      configuration: DesignDatabaseServiceSessionConfiguration(
        leaseDuration: .seconds(60),
        maximumInFlightOperationCount: 2
      )
    )
    #expect(session.databaseID == fixture.databaseID)
    #expect(session.authorizationSubjectScopeID == fixture.subjectScopeID)
    #expect(try await session.resolve(.named(.main)) == fixture.genesis)

    let snapshot = try await session.openSnapshot(at: fixture.genesis)
    #expect(snapshot.revision == fixture.genesis)
    #expect(snapshot.designSchemaBundleDigest == fixture.schemaDigest)
    #expect(snapshot.projectionSemantics.map(\.family) == [.facet])
    #expect(snapshot.materializationBindings[.facet] != nil)
    let queryPage = try await session.query(
      snapshotID: snapshot.snapshotID,
      request: DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: DesignQueryBudget(
          maximumResultCount: 1,
          maximumNodeFetchCount: 1,
          maximumEncodedReadByteCount: 1,
          maximumDecodedByteCount: 1,
          maximumOutputByteCount: 1,
          maximumWorkCount: 1
        )
      )
    )
    #expect(queryPage.revision == fixture.genesis)
    #expect(queryPage.rows.isEmpty)
    #expect(queryPage.completion == .sourceExhausted)
    #expect(try await session.closeSnapshot(snapshot.snapshotID) == .closed)
    await #expect(throws: DesignDatabaseServiceError.self) {
      _ = try await session.query(
        snapshotID: snapshot.snapshotID,
        request: DesignQueryRequest(
          family: .facet,
          maximumPageResultCount: 1,
          budget: DesignQueryBudget(
            maximumResultCount: 1,
            maximumNodeFetchCount: 1,
            maximumEncodedReadByteCount: 1,
            maximumDecodedByteCount: 1,
            maximumOutputByteCount: 1,
            maximumWorkCount: 1
          )
        )
      )
    }
    await #expect(throws: DesignDatabaseServiceError.self) {
      _ = try await session.closeSnapshot(snapshot.snapshotID)
    }
    _ = try await session.openSnapshot(at: fixture.genesis)

    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.databaseID,
      authorizationSubjectScopeID: fixture.subjectScopeID,
      operationID: try DesignDatabaseOperationID(rawValue: "reconcile")
    )
    #expect(
      try await session.commitStatus(
        operation: operation,
        requestDigest: fixture.stateDigest
      ) == .notRecorded
    )
    #expect(
      try await session.referenceStatus(
        operation: operation,
        requestDigest: fixture.stateDigest
      ) == .notRecorded
    )
    #expect(
      try await session.retentionStatus(
        operation: operation,
        requestDigest: fixture.stateDigest
      ) == .notRecorded
    )

    let diffRequest = try DesignRevisionDiffRequest(
      fromRevision: fixture.genesis,
      toRevision: fixture.genesis,
      budget: try DesignRevisionDiffBudget(maximumFacetComparisonCount: 1)
    )
    let diff = try await session.diff(diffRequest)
    #expect(diff.fromRevision == fixture.genesis)
    #expect(diff.toRevision == fixture.genesis)
    #expect(!diff.stateChanged)
    #expect(diff.facetChanges.isEmpty)
    #expect(await handle.lastDiffRequest == diffRequest)

    let leftRevision = DesignRevisionReference(
      databaseID: fixture.databaseID,
      revisionID: DesignRevisionID(high: 0, low: 2)
    )
    let rightRevision = DesignRevisionReference(
      databaseID: fixture.databaseID,
      revisionID: DesignRevisionID(high: 0, low: 3)
    )
    let mergeRequest = try DesignDisjointMergeRequest(
      baseRevision: fixture.genesis,
      leftRevision: leftRevision,
      rightRevision: rightRevision,
      budget: DesignDisjointMergeBudget(
        maximumFacetComparisonCount: 1,
        maximumAncestryRevisionCount: 3
      )
    )
    let merge = try await session.assessDisjointMerge(mergeRequest)
    guard case .requiresSemanticValidation(let mergeCandidate) = merge else {
      Issue.record("The service did not forward the disjoint merge assessment.")
      return
    }
    #expect(mergeCandidate.parentRevisions == [leftRevision, rightRevision])
    #expect(await handle.lastMergeRequest == mergeRequest)

    let publicationOperationID = try DesignDatabaseOperationID(
      rawValue: "publish-merge"
    )
    let validatedStateCommit = try fixture.commitSubmission(
      operation: "validate-merge"
    )
    let publication = try DesignDisjointMergePublicationSubmission(
      operationID: publicationOperationID,
      candidate: mergeCandidate,
      validatedStateRevision: leftRevision,
      validatedStateCommit: validatedStateCommit,
      budget: DesignDisjointMergePublicationBudget(
        maximumProjectionCount: 1,
        maximumPhysicalIdentityCount: 1
      ),
      requestDigest: fixture.directChangeDigest
    )
    let publicationResult = try await session.publishDisjointMerge(publication)
    let publicationReceipt: DesignDisjointMergePublicationReceipt
    switch publicationResult {
    case .published(let receipt):
      publicationReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The service merge publication was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The service merge publication outcome was unknown.")
      return
    }
    #expect(await handle.lastMergePublicationSubmission == publication)
    #expect(
      try await session.disjointMergePublicationStatus(
        operation: publicationReceipt.operation,
        requestDigest: publication.requestDigest
      ) == .published(publicationReceipt)
    )

    #expect(await service.closeSession(session.id) == .closed)
    #expect(await handle.allSnapshotsClosed())
    await #expect(throws: DesignDatabaseServiceError.self) {
      _ = try await session.resolve(.named(.main))
    }
    #expect(await service.shutdown() == .closed)
    #expect(await handle.isClosed)
  }

  @Test
  func inFlightLimitRejectsExcessWorkWithoutExecutingIt() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(fixture: fixture, blocksResolve: true)
    let service = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 1
      )
    )
    let session = try await service.openSession(
      configuration: DesignDatabaseServiceSessionConfiguration(
        leaseDuration: .seconds(60),
        maximumInFlightOperationCount: 1
      )
    )
    let first = Task {
      try await session.resolve(.named(.main))
    }
    var observedPendingResolve = false
    for _ in 0..<1_000 {
      if await handle.hasPendingResolve {
        observedPendingResolve = true
        break
      }
      await Task.yield()
    }
    #expect(observedPendingResolve)
    do {
      _ = try await session.resolve(.named(.main))
      Issue.record("The session accepted work beyond its in-flight limit.")
    } catch let error {
      #expect(error == .backpressure(limit: 1))
    }
    #expect(await handle.resolveCallCount == 1)
    await handle.resumePendingResolves()
    #expect(try await first.value == fixture.genesis)
    #expect(await service.shutdown() == .closed)
  }

  @Test
  func disconnectedCommitIsReconciledByExactOperationAfterReconnect() async throws {
    let fixture = try ServiceFixture()
    let handle = try ServiceTestHandle(
      fixture: fixture,
      blocksResolve: false,
      blocksSubmit: true
    )
    let service = InProcessDesignDatabaseService(
      database: handle,
      schemas: [fixture.schema],
      configuration: try DesignDatabaseServiceConfiguration(
        maximumSessionCount: 1
      )
    )
    let sessionConfiguration = try DesignDatabaseServiceSessionConfiguration(
      leaseDuration: .seconds(60),
      maximumInFlightOperationCount: 1
    )
    let firstSession = try await service.openSession(
      configuration: sessionConfiguration
    )
    let submission = try fixture.commitSubmission(
      operation: "disconnect-reconcile"
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.databaseID,
      authorizationSubjectScopeID: fixture.subjectScopeID,
      operationID: submission.operationID
    )

    let submitTask = Task {
      try await firstSession.submit(submission)
    }
    var observedPendingSubmit = false
    for _ in 0..<1_000 {
      if await handle.hasPendingSubmit {
        observedPendingSubmit = true
        break
      }
      await Task.yield()
    }
    #expect(observedPendingSubmit)
    #expect(await handle.submitCallCount == 1)

    let disconnectTask = Task {
      await service.closeSession(firstSession.id)
    }
    var replacementSession: (any DesignDatabaseServiceSession)?
    for _ in 0..<1_000 {
      do {
        replacementSession = try await service.openSession(
          configuration: sessionConfiguration
        )
        break
      } catch let error {
        guard case .sessionLimitReached = error else { throw error }
        await Task.yield()
      }
    }

    if let replacementSession {
      #expect(
        try await replacementSession.commitStatus(
          operation: operation,
          requestDigest: submission.requestDigest
        ) == .inProgress
      )
    }

    await handle.resumePendingSubmissions()
    let submittedResult = try await submitTask.value
    guard case .committed(let submittedReceipt) = submittedResult else {
      Issue.record("The accepted commit did not complete after disconnect.")
      _ = await disconnectTask.value
      _ = await service.shutdown()
      return
    }
    #expect(await disconnectTask.value == .closed)

    guard let replacementSession else {
      Issue.record("The service did not admit a reconnecting exact session.")
      _ = await service.shutdown()
      return
    }
    #expect(replacementSession.id != firstSession.id)
    #expect(replacementSession.databaseID == firstSession.databaseID)
    #expect(
      replacementSession.authorizationSubjectScopeID
        == firstSession.authorizationSubjectScopeID
    )
    #expect(
      try await replacementSession.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .committed(submittedReceipt)
    )

    do {
      _ = try await replacementSession.commitStatus(
        operation: operation,
        requestDigest: fixture.directChangeDigest
      )
      Issue.record("A reconnect used a mismatched request digest as authority.")
    } catch let error {
      #expect(
        error == .database(.idempotencyConflict(operation: operation))
      )
    }

    #expect(await service.closeSession(replacementSession.id) == .closed)
    #expect(await service.shutdown() == .closed)
  }
}

private struct ServiceFixture: Sendable {
  let databaseID: DesignDatabaseID
  let subjectScopeID: DesignAuthorizationSubjectScopeID
  let genesis: DesignRevisionReference
  let schema: DesignSchemaDescriptor
  let stateDigest: ContentDigest
  let schemaDigest: ContentDigest
  let dependencyDigest: ContentDigest
  let semanticGraphDigest: ContentDigest
  let directChangeDigest: ContentDigest

  init() throws {
    databaseID = try DesignDatabaseID(high: 0x444442, low: 1)
    subjectScopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x53455256494345,
      low: 1
    )
    genesis = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 1)
    )
    stateDigest = try Self.digest("11")
    schemaDigest = try Self.digest("12")
    dependencyDigest = try Self.digest("13")
    semanticGraphDigest = try Self.digest("14")
    directChangeDigest = try Self.digest("15")
    schema = try DesignSchemaDescriptor(
      schemaID: DesignSchemaID(rawValue: "lsi.service"),
      facetID: DesignFacetID(rawValue: "service"),
      version: .v1,
      canonicalDigest: schemaDigest
    )
  }

  func commitSubmission(
    operation: String
  ) throws -> DesignCommitSubmission {
    let segment = try DesignMutationPlanSegment(
      id: DesignMutationPlanSegmentID(rawValue: "service-commit"),
      schemaID: schema.schemaID,
      schemaVersion: schema.version,
      adapterVersion: "1.0.0",
      targetFacet: schema.facetID,
      payload: [0x01],
      payloadDigest: stateDigest,
      expectedWriteCount: 1
    )
    let plan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: genesis,
      designSchemaBundleDigest: schemaDigest,
      dependencyRootDigest: dependencyDigest,
      semanticDependencyGraphDigest: semanticGraphDigest,
      sourceEvidenceDigest: stateDigest,
      budget: try DesignMutationPlanBudget(
        maximumSegmentCount: 1,
        maximumPayloadByteCount: 1,
        maximumPreparedWriteCount: 1,
        maximumValidationReadCount: 1
      ),
      segments: [segment],
      planDigest: directChangeDigest
    )
    return DesignCommitSubmission(
      operationID: try DesignDatabaseOperationID(rawValue: operation),
      plan: plan,
      requestDigest: semanticGraphDigest
    )
  }

  private static func digest(_ byte: String) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: byte, count: 32)
    )
  }
}

private actor ServiceTestSnapshot: DesignReadSnapshot {
  nonisolated let revision: DesignRevisionReference
  nonisolated let parents: [DesignRevisionReference]
  nonisolated let stateDigest: ContentDigest
  nonisolated let designSchemaBundle: DesignSchemaBundle
  nonisolated let designSchemaBundleDigest: ContentDigest
  nonisolated let directDependencyLock: DesignDependencyLock
  nonisolated let dependencyRootDigest: ContentDigest
  nonisolated let semanticDependencyGraphDigest: ContentDigest
  nonisolated let facetRoots: [DesignFacetRoot]
  nonisolated let directChangeRootDigest: ContentDigest
  nonisolated let projectionSemantics: [DesignProjectionSemanticDescriptor]
  nonisolated let materializationBindings: DesignProjectionMaterializationBindingSet
  private var isClosed = false

  var closed: Bool { isClosed }

  init(fixture: ServiceFixture) throws(DesignDatabaseError) {
    revision = fixture.genesis
    parents = []
    stateDigest = fixture.stateDigest
    designSchemaBundle = try DesignSchemaBundle(
      members: [
        DesignSchemaBundleMember(
          schemaID: fixture.schema.schemaID,
          version: fixture.schema.version,
          canonicalDigest: fixture.schema.canonicalDigest
        ),
      ],
      rootDigest: fixture.schemaDigest
    )
    designSchemaBundleDigest = fixture.schemaDigest
    directDependencyLock = try DesignDependencyLock(entries: [])
    dependencyRootDigest = fixture.dependencyDigest
    semanticDependencyGraphDigest = fixture.semanticGraphDigest
    facetRoots = []
    directChangeRootDigest = fixture.directChangeDigest
    let materialization = try DesignProjectionMaterializationReference(
      semanticDescriptorDigest: fixture.stateDigest,
      bindingGeneration: 1,
      physicalCodecVersion: DesignProjectionPhysicalCodecVersion(
        major: 1,
        minor: 0
      ),
      physicalProfileDigest: fixture.dependencyDigest,
      rootNodeDigest: fixture.directChangeDigest
    )
    projectionSemantics = [
      try DesignProjectionSemanticDescriptor(
        family: .facet,
        semanticVersion: DesignProjectionSemanticVersion(major: 1, minor: 0),
        entryCount: 0,
        minimumKey: nil,
        maximumKey: nil,
        canonicalSequenceDigest: fixture.semanticGraphDigest
      ),
    ]
    materializationBindings = try DesignProjectionMaterializationBindingSet([
      DesignProjectionMaterializationBinding(
        family: .facet,
        materialization: materialization
      ),
    ])
  }

  func query(
    _ request: DesignQueryRequest
  ) throws(DesignDatabaseError) -> DesignQueryPage {
    guard !isClosed else { throw .closed }
    guard request.family == .facet,
          request.continuation == nil,
          let materialization = materializationBindings[.facet] else {
      throw .projectionUnavailable(request.family)
    }
    return try DesignQueryPage(
      revision: revision,
      designSchemaBundleDigest: designSchemaBundleDigest,
      projectionSemanticDigest: materialization.semanticDescriptorDigest,
      materialization: materialization,
      rows: [],
      continuation: nil,
      completion: .sourceExhausted,
      report: DesignQueryResourceReport()
    )
  }

  func close() -> DesignSnapshotTermination {
    guard !isClosed else { return .alreadyClosed }
    isClosed = true
    return .closed
  }
}

private actor ServiceTestHandle:
  DesignDatabaseHandle,
  DesignDisjointMergePublishing
{
  nonisolated let databaseID: DesignDatabaseID
  nonisolated let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  nonisolated let featureCapabilities: DesignCapabilitySet
  nonisolated let authorizationGrants: DesignDatabaseAuthorizationGrantSet
  nonisolated let genesisRevision: DesignRevisionReference

  private let fixture: ServiceFixture
  private let blocksResolve: Bool
  private let blocksSubmit: Bool
  private var pendingResolveContinuations: [CheckedContinuation<Void, Never>] = []
  private var pendingSubmitContinuations: [CheckedContinuation<Void, Never>] = []
  private var commitRecords: [
    DesignDatabaseOperationReference: ServiceTestCommitRecord
  ] = [:]
  private var mergePublicationRecords: [
    DesignDatabaseOperationReference: (
      requestDigest: ContentDigest,
      receipt: DesignDisjointMergePublicationReceipt
    )
  ] = [:]
  private var openedSnapshots: [ServiceTestSnapshot] = []
  private(set) var resolveCallCount: UInt64 = 0
  private(set) var submitCallCount: UInt64 = 0
  private(set) var lastDiffRequest: DesignRevisionDiffRequest?
  private(set) var lastMergeRequest: DesignDisjointMergeRequest?
  private(set) var lastMergePublicationSubmission:
    DesignDisjointMergePublicationSubmission?
  private(set) var isClosed = false

  init(
    fixture: ServiceFixture,
    blocksResolve: Bool,
    blocksSubmit: Bool = false
  ) throws {
    self.fixture = fixture
    self.blocksResolve = blocksResolve
    self.blocksSubmit = blocksSubmit
    databaseID = fixture.databaseID
    authorizationSubjectScopeID = fixture.subjectScopeID
    featureCapabilities = try DesignCapabilitySet([])
    authorizationGrants = DesignDatabaseAuthorizationGrantSet(
      DesignDatabaseAuthorizationGrant.allCases
    )
    genesisRevision = fixture.genesis
  }

  var hasPendingResolve: Bool {
    !pendingResolveContinuations.isEmpty
  }

  var hasPendingSubmit: Bool {
    !pendingSubmitContinuations.isEmpty
  }

  func resumePendingResolves() {
    let continuations = pendingResolveContinuations
    pendingResolveContinuations.removeAll(keepingCapacity: false)
    for continuation in continuations { continuation.resume() }
  }

  func resumePendingSubmissions() {
    let continuations = pendingSubmitContinuations
    pendingSubmitContinuations.removeAll(keepingCapacity: false)
    for continuation in continuations { continuation.resume() }
  }

  func allSnapshotsClosed() async -> Bool {
    for snapshot in openedSnapshots where !(await snapshot.closed) {
      return false
    }
    return true
  }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
    guard !isClosed else { throw .closed }
    resolveCallCount += 1
    if blocksResolve {
      await withCheckedContinuation { continuation in
        pendingResolveContinuations.append(continuation)
      }
    }
    return fixture.genesis
  }

  func openSnapshot(
    at revision: DesignRevisionReference
  ) throws(DesignDatabaseError) -> any DesignReadSnapshot {
    guard revision == fixture.genesis else { throw .revisionNotFound(revision) }
    let snapshot = try ServiceTestSnapshot(fixture: fixture)
    openedSnapshots.append(snapshot)
    return snapshot
  }

  func diff(
    _ request: DesignRevisionDiffRequest
  ) throws(DesignDatabaseError) -> DesignRevisionDiff {
    lastDiffRequest = request
    return try DesignRevisionDiffer().diff(
      from: stateDescriptor(
        revision: request.fromRevision,
        parents: []
      ),
      to: stateDescriptor(
        revision: request.toRevision,
        parents: []
      ),
      budget: request.budget
    )
  }

  func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) throws(DesignDatabaseError) -> DesignDisjointMergeAssessment {
    lastMergeRequest = request
    return try DesignDisjointMergeAssessor().assess(
      base: stateDescriptor(revision: request.baseRevision, parents: []),
      left: stateDescriptor(
        revision: request.leftRevision,
        parents: [request.baseRevision]
      ),
      right: stateDescriptor(
        revision: request.rightRevision,
        parents: [request.baseRevision]
      ),
      baseIsAncestorOfLeft: true,
      baseIsAncestorOfRight: true,
      ancestryRevisionReadCount: 3,
      budget: request.budget
    )
  }

  func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) throws(DesignDatabaseError) -> DesignDisjointMergePublicationResult {
    guard !isClosed else { throw .closed }
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    if let existing = mergePublicationRecords[operation] {
      guard existing.requestDigest == submission.requestDigest else {
        throw .idempotencyConflict(operation: operation)
      }
      return .published(existing.receipt)
    }
    lastMergePublicationSubmission = submission
    let receipt = DesignDisjointMergePublicationReceipt(
      operation: operation,
      requestDigest: submission.requestDigest,
      candidateDigest: fixture.schemaDigest,
      baseRevision: submission.candidate.baseRevision,
      parentRevisions: submission.candidate.parentRevisions,
      validatedStateRevision: submission.validatedStateRevision,
      validatedStateCommitOperation: DesignDatabaseOperationReference(
        databaseID: databaseID,
        authorizationSubjectScopeID: authorizationSubjectScopeID,
        operationID: submission.validatedStateCommit.operationID
      ),
      validatedStateCommitRequestDigest:
        submission.validatedStateCommit.requestDigest,
      validatedStatePlanDigest:
        submission.validatedStateCommit.plan.planDigest,
      candidateRevision: DesignRevisionReference(
        databaseID: databaseID,
        revisionID: DesignRevisionID(high: 0, low: 4)
      ),
      stateDigest: fixture.stateDigest,
      changeSetDigest: fixture.directChangeDigest,
      designSchemaBundleDigest: submission.candidate.designSchemaBundleDigest,
      dependencyRootDigest: submission.candidate.dependencyRootDigest,
      semanticDependencyGraphDigest:
        submission.candidate.semanticDependencyGraphDigest,
      facetRoots: submission.candidate.facetRoots,
      outcomeDigest: fixture.semanticGraphDigest
    )
    mergePublicationRecords[operation] = (
      requestDigest: submission.requestDigest,
      receipt: receipt
    )
    return .published(receipt)
  }

  func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignDisjointMergePublicationStatus {
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID
            == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    guard let existing = mergePublicationRecords[operation] else {
      return .notRecorded
    }
    guard existing.requestDigest == requestDigest else {
      throw .idempotencyConflict(operation: operation)
    }
    return .published(existing.receipt)
  }

  func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseError) -> DesignCommitResult {
    guard !isClosed else { throw .closed }
    guard submission.plan.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: submission.plan.databaseID
      )
    }
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    if let existing = commitRecords[operation] {
      guard existing.requestDigest == submission.requestDigest else {
        throw .idempotencyConflict(operation: operation)
      }
      return try commitResult(
        from: existing.status,
        operation: operation,
        requestDigest: submission.requestDigest
      )
    }

    submitCallCount += 1
    commitRecords[operation] = ServiceTestCommitRecord(
      requestDigest: submission.requestDigest,
      status: .inProgress
    )
    if blocksSubmit {
      await withCheckedContinuation { continuation in
        pendingSubmitContinuations.append(continuation)
      }
    }
    guard !isClosed else { throw .closed }
    let receipt = DesignCommitReceipt(
      operation: operation,
      requestDigest: submission.requestDigest,
      planDigest: submission.plan.planDigest,
      baseRevision: submission.plan.baseRevision,
      candidateRevision: DesignRevisionReference(
        databaseID: databaseID,
        revisionID: DesignRevisionID(high: 0, low: 2)
      ),
      stateDigest: fixture.stateDigest,
      changeSetDigest: fixture.directChangeDigest,
      designSchemaBundleDigest: fixture.schemaDigest,
      dependencyRootDigest: fixture.dependencyDigest,
      semanticDependencyGraphDigest: fixture.semanticGraphDigest,
      facetRoots: [],
      outcomeDigest: fixture.directChangeDigest
    )
    commitRecords[operation] = ServiceTestCommitRecord(
      requestDigest: submission.requestDigest,
      status: .committed(receipt)
    )
    return .committed(receipt)
  }

  func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignCommitStatus {
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    guard let record = commitRecords[operation] else { return .notRecorded }
    guard record.requestDigest == requestDigest else {
      throw .idempotencyConflict(operation: operation)
    }
    return record.status
  }

  func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) throws(DesignDatabaseError) -> DesignReferenceUpdateResult {
    throw .invalidMutationPlan(reason: "The service test does not update a reference.")
  }

  func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) -> DesignReferenceUpdateStatus {
    .notRecorded
  }

  func retain(
    _ request: DesignRevisionRetentionRequest
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    throw .invalidMutationPlan(reason: "The service test does not retain a revision.")
  }

  func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    throw .invalidMutationPlan(reason: "The service test does not release retention.")
  }

  func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) -> DesignRevisionRetentionStatus {
    .notRecorded
  }

  func close() -> DesignDatabaseTermination {
    guard !isClosed else { return .alreadyClosed }
    isClosed = true
    resumePendingResolves()
    resumePendingSubmissions()
    return .closed
  }

  private func commitResult(
    from status: DesignCommitStatus,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignCommitResult {
    switch status {
    case .committed(let receipt):
      return .committed(receipt)
    case .rejected(let rejection):
      return .rejected(rejection)
    case .outcomeUnknown(let unknown):
      return .outcomeUnknown(unknown)
    case .inProgress:
      throw .outcomeUnknown(
        operation: operation,
        requestDigest: requestDigest
      )
    case .notRecorded:
      throw .corruption("A recorded service commit lost its status.")
    }
  }

  private func stateDescriptor(
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference]
  ) throws(DesignDatabaseError) -> DesignRevisionStateDescriptor {
    try DesignRevisionStateDescriptor(
      revision: revision,
      parents: parents,
      stateDigest: fixture.stateDigest,
      designSchemaBundleDigest: fixture.schemaDigest,
      dependencyRootDigest: fixture.dependencyDigest,
      semanticDependencyGraphDigest: fixture.semanticGraphDigest,
      facetRoots: [],
      directChangeRootDigest: fixture.directChangeDigest
    )
  }
}

private struct ServiceTestCommitRecord: Sendable {
  let requestDigest: ContentDigest
  let status: DesignCommitStatus
}

private struct InvalidServiceSessionConfiguration: Encodable {
  let leaseDuration: Duration
  let maximumInFlightOperationCount: UInt64
}

private actor LoopbackDesignDatabaseServiceWireTransport:
  DesignDatabaseServiceWireTransport
{
  private let dispatcher: DesignDatabaseServiceRemoteDispatcher
  private let codecBudget: DesignDatabaseServiceWireCodecBudget
  private(set) var observedSuccessfulQueryPage = false
  private(set) var isClosed = false

  init(
    dispatcher: DesignDatabaseServiceRemoteDispatcher,
    codecBudget: DesignDatabaseServiceWireCodecBudget
  ) {
    self.dispatcher = dispatcher
    self.codecBudget = codecBudget
  }

  func exchange(
    _ requestFrame: [UInt8],
    timeout: Duration
  ) async throws(DesignDatabaseServiceWireTransportError) -> [UInt8] {
    guard !isClosed else { throw .closed }
    guard timeout > .zero else { throw .deadlineExceeded }
    let request: DesignDatabaseServiceWireMessage
    do {
      request = try DesignDatabaseServiceWireCodec.decode(
        requestFrame,
        budget: codecBudget
      )
    } catch let error {
      throw .invalidFrame(error)
    }
    let responseFrame: [UInt8]
    do {
      responseFrame = try await dispatcher.dispatch(requestFrame)
    } catch let error {
      throw .invalidFrame(error)
    }
    if request.operation == .query {
      do {
        let response = try DesignDatabaseServiceWireCodec.decode(
          responseFrame,
          budget: codecBudget
        )
        if response.kind == .success,
           response.payloadFormat == .queryPageV1 {
          observedSuccessfulQueryPage = true
        }
      } catch let error {
        throw .invalidFrame(error)
      }
    }
    return responseFrame
  }

  func close() async throws(DesignDatabaseServiceWireTransportError) {
    isClosed = true
  }
}
