import Foundation

public actor DesignDatabaseServiceProcessWireTransport:
  DesignDatabaseServiceWireTransport
{
  private enum TimedRead: Sendable {
    case frame([UInt8])
  }

  private let processOwner: DesignDatabaseServiceProcessOwner
  private let requestHandle: FileHandle
  private let responseHandle: FileHandle
  private var responseIterator: FileHandle.AsyncBytes.Iterator
  private let maximumFrameByteCount: UInt64
  private let closeGracePeriod: Duration
  private var exchangeIsAvailable = true
  private var exchangeWaiters: [CheckedContinuation<Void, Never>] = []
  private var isClosed = false
  private var closeIsInProgress = false
  private var closeWaiters: [
    CheckedContinuation<
      Result<Void, DesignDatabaseServiceWireTransportError>,
      Never
    >
  ] = []
  private var deadlineExpired = false

  public init(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    maximumFrameByteCount: UInt64,
    closeGracePeriod: Duration = .seconds(2)
  ) throws(DesignDatabaseServiceWireTransportError) {
    guard maximumFrameByteCount > 0 else {
      throw .invalidConfiguration(
        reason: "A process transport frame budget must be greater than zero."
      )
    }
    guard closeGracePeriod > .zero else {
      throw .invalidConfiguration(
        reason: "A process transport close grace period must be greater than zero."
      )
    }
    let launch = try DesignDatabaseServiceProcessOwner.launch(
      executableURL: executableURL,
      arguments: arguments,
      environment: environment
    )
    self.processOwner = launch.owner
    self.requestHandle = launch.requestHandle
    self.responseHandle = launch.responseHandle
    self.responseIterator = launch.responseHandle.bytes
      .makeAsyncIterator()
    self.maximumFrameByteCount = maximumFrameByteCount
    self.closeGracePeriod = closeGracePeriod
  }

  public func exchange(
    _ requestFrame: [UInt8],
    timeout: Duration
  ) async throws(DesignDatabaseServiceWireTransportError) -> [UInt8] {
    guard timeout > .zero else { throw .deadlineExceeded }
    await acquireExchange()
    defer { releaseExchange() }
    guard !isClosed, processOwner.isRunning else { throw .closed }
    let encoded = try DesignDatabaseServiceLengthPrefixedFrameIO.encoded(
      requestFrame,
      maximumFrameByteCount: maximumFrameByteCount
    )
    do {
      try requestHandle.write(contentsOf: encoded)
    } catch {
      let primaryReason = String(describing: error)
      do {
        try await closeResources()
      } catch let closeError {
        throw .inputOutputFailure(
          reason: "Process request write failed with \(primaryReason); cleanup also failed with \(closeError)."
        )
      }
      throw .inputOutputFailure(reason: primaryReason)
    }

    do {
      return try await withThrowingTaskGroup(
        of: TimedRead.self,
        returning: [UInt8].self
      ) { group in
        group.addTask { [self] in
          .frame(try await readResponseFrame())
        }
        group.addTask { [self] in
          try await ContinuousClock().sleep(for: timeout)
          try await terminateForDeadline()
          throw DesignDatabaseServiceWireTransportError.deadlineExceeded
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
          throw DesignDatabaseServiceWireTransportError.closed
        }
        switch result {
        case .frame(let frame):
          return frame
        }
      }
    } catch let error as DesignDatabaseServiceWireTransportError {
      throw error
    } catch {
      let primaryReason = String(describing: error)
      do {
        try await closeResources()
      } catch let closeError {
        throw .inputOutputFailure(
          reason: "Process response read failed with \(primaryReason); cleanup also failed with \(closeError)."
        )
      }
      throw .inputOutputFailure(reason: primaryReason)
    }
  }

  public func close() async throws(DesignDatabaseServiceWireTransportError) {
    guard beginClose() else {
      try await waitForCloseIfNeeded()
      return
    }
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }

    if let terminationFailure = await terminateAndReap(
      initialGracePeriod: closeGracePeriod
    ) {
      failures.append(terminationFailure)
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    let result = closeResult(failures)
    completeClose(with: result)
    try result.get()
  }

  private func closeResources()
    async throws(DesignDatabaseServiceWireTransportError) {
    guard beginClose() else {
      try await waitForCloseIfNeeded()
      return
    }
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    if let terminationFailure = await terminateAndReap(
      initialGracePeriod: .zero
    ) {
      failures.append(terminationFailure)
    }
    let result = closeResult(failures)
    completeClose(with: result)
    try result.get()
  }

  private func acquireExchange() async {
    if exchangeIsAvailable {
      exchangeIsAvailable = false
      return
    }
    await withCheckedContinuation { continuation in
      exchangeWaiters.append(continuation)
    }
  }

  private func releaseExchange() {
    guard !exchangeWaiters.isEmpty else {
      exchangeIsAvailable = true
      return
    }
    let waiter = exchangeWaiters.removeFirst()
    waiter.resume()
  }

  private func readResponseFrame()
    async throws(DesignDatabaseServiceWireTransportError) -> [UInt8] {
    do {
      var iterator = responseIterator
      guard let frame = try await DesignDatabaseServiceLengthPrefixedFrameIO.read(
        from: &iterator,
        maximumFrameByteCount: maximumFrameByteCount
      ) else {
        throw DesignDatabaseServiceWireTransportError.closed
      }
      responseIterator = iterator
      return frame
    } catch let error as DesignDatabaseServiceWireTransportError {
      if deadlineExpired { throw .deadlineExceeded }
      throw error
    } catch {
      if deadlineExpired { throw .deadlineExceeded }
      throw .inputOutputFailure(reason: String(describing: error))
    }
  }

  private func terminateForDeadline()
    async throws(DesignDatabaseServiceWireTransportError) {
    deadlineExpired = true
    guard beginClose() else {
      try await waitForCloseIfNeeded()
      return
    }
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    if let terminationFailure = await terminateAndReap(
      initialGracePeriod: .zero
    ) {
      failures.append(terminationFailure)
    }
    let result: Result<Void, DesignDatabaseServiceWireTransportError>
    if failures.isEmpty {
      result = .success(())
    } else {
      result = .failure(.inputOutputFailure(
        reason: "The request deadline expired and forced cleanup failed: \(failures.joined(separator: "; "))."
      ))
    }
    completeClose(with: result)
    try result.get()
  }

  private func beginClose() -> Bool {
    guard !isClosed else { return false }
    isClosed = true
    closeIsInProgress = true
    return true
  }

  private func waitForCloseIfNeeded()
    async throws(DesignDatabaseServiceWireTransportError) {
    guard closeIsInProgress else { return }
    let result = await withCheckedContinuation { continuation in
      closeWaiters.append(continuation)
    }
    try result.get()
  }

  private func closeResult(
    _ failures: [String]
  ) -> Result<Void, DesignDatabaseServiceWireTransportError> {
    guard !failures.isEmpty else { return .success(()) }
    return .failure(.inputOutputFailure(
      reason: failures.joined(separator: "; ")
    ))
  }

  private func completeClose(
    with result: Result<Void, DesignDatabaseServiceWireTransportError>
  ) {
    closeIsInProgress = false
    let waiters = closeWaiters
    closeWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume(returning: result)
    }
  }

  private func terminateAndReap(
    initialGracePeriod: Duration
  ) async -> String? {
    let owner = processOwner
    let signalGracePeriod = closeGracePeriod
    return await withCheckedContinuation { continuation in
      Thread {
        continuation.resume(
          returning: owner.terminateAndReap(
            initialGracePeriod: initialGracePeriod,
            signalGracePeriod: signalGracePeriod
          )
        )
      }.start()
    }
  }
}
