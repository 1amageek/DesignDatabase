import DesignDatabaseCore

package actor DesignDatabaseRuntimeHandleLifecycle {
  private enum State {
    case open
    case closing
    case closed
  }

  private var state: State = .open
  private var activeOperationCount: UInt64 = 0
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []

  package func perform<Result: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Result
  ) async throws(DesignDatabaseError) -> Result {
    guard state == .open else { throw .closed }
    let (nextCount, overflow) = activeOperationCount.addingReportingOverflow(1)
    guard !overflow else {
      throw .resourceExhausted(limit: UInt64.max, requested: UInt64.max)
    }
    activeOperationCount = nextCount
    do {
      let result = try await operation()
      finishOperation()
      return result
    } catch let error as DesignDatabaseError {
      finishOperation()
      throw error
    } catch {
      finishOperation()
      throw .corruption(
        "A runtime handle operation escaped its typed failure contract: \(error)"
      )
    }
  }

  package func beginClose() async -> Bool {
    switch state {
    case .open:
      state = .closing
      if activeOperationCount > 0 {
        await withCheckedContinuation { continuation in
          drainWaiters.append(continuation)
        }
      }
      return true
    case .closing:
      await withCheckedContinuation { continuation in
        closeWaiters.append(continuation)
      }
      return false
    case .closed:
      return false
    }
  }

  package func finishClose() {
    precondition(state == .closing)
    precondition(activeOperationCount == 0)
    state = .closed
    let waiters = closeWaiters
    closeWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func finishOperation() {
    precondition(activeOperationCount > 0)
    activeOperationCount -= 1
    guard state == .closing, activeOperationCount == 0 else { return }
    let waiters = drainWaiters
    drainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }
}
