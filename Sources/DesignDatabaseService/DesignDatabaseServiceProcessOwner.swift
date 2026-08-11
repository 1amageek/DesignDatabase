import Foundation
import Synchronization

#if os(macOS)
import Darwin

package final class DesignDatabaseServiceProcessOwner: Sendable {
  package struct Launch: Sendable {
    package let owner: DesignDatabaseServiceProcessOwner
    package let requestHandle: FileHandle
    package let responseHandle: FileHandle
  }

  private struct State: Sendable {
    var isReaped = false
  }

  private let processID: pid_t
  private let state = Mutex(State())

  private init(processID: pid_t) {
    self.processID = processID
  }

  package static func launch(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]?
  ) throws(DesignDatabaseServiceWireTransportError) -> Launch {
    let requestPipe = Pipe()
    let responsePipe = Pipe()
    var actions: posix_spawn_file_actions_t? = nil
    var attributes: posix_spawnattr_t? = nil
    try requireSuccess(
      posix_spawn_file_actions_init(&actions),
      operation: "posix_spawn_file_actions_init"
    )
    defer { posix_spawn_file_actions_destroy(&actions) }
    try requireSuccess(
      posix_spawnattr_init(&attributes),
      operation: "posix_spawnattr_init"
    )
    defer { posix_spawnattr_destroy(&attributes) }

    let requestRead = requestPipe.fileHandleForReading.fileDescriptor
    let requestWrite = requestPipe.fileHandleForWriting.fileDescriptor
    let responseRead = responsePipe.fileHandleForReading.fileDescriptor
    let responseWrite = responsePipe.fileHandleForWriting.fileDescriptor
    try addClose(&actions, descriptor: requestWrite)
    try addClose(&actions, descriptor: responseRead)
    try addDuplicate(&actions, from: requestRead, to: STDIN_FILENO)
    try addDuplicate(&actions, from: responseWrite, to: STDOUT_FILENO)
    if requestRead != STDIN_FILENO {
      try addClose(&actions, descriptor: requestRead)
    }
    if responseWrite != STDOUT_FILENO {
      try addClose(&actions, descriptor: responseWrite)
    }
    try requireSuccess(
      posix_spawnattr_setflags(
        &attributes,
        Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)
      ),
      operation: "posix_spawnattr_setflags"
    )

    let executablePath = executableURL.path(percentEncoded: false)
    let argv = try ProcessCStringArray([executablePath] + arguments)
    let envp: ProcessCStringArray?
    if let environment {
      envp = try ProcessCStringArray(
        environment.keys.sorted().map { key in
          "\(key)=\(environment[key] ?? "")"
        }
      )
    } else {
      envp = nil
    }
    var processID = pid_t()
    let result: Int32
    do {
      result = try executablePath.withCString { executable in
        try argv.withUnsafeMutablePointers { arguments in
          if let envp {
            return try envp.withUnsafeMutablePointers { environment in
              posix_spawn(
                &processID,
                executable,
                &actions,
                &attributes,
                arguments,
                environment
              )
            }
          }
          return posix_spawn(
            &processID,
            executable,
            &actions,
            &attributes,
            arguments,
            Darwin.environ
          )
        }
      }
    } catch let error as DesignDatabaseServiceWireTransportError {
      throw error
    } catch {
      throw .inputOutputFailure(reason: String(describing: error))
    }
    try requireSuccess(result, operation: "posix_spawn")
    let owner = DesignDatabaseServiceProcessOwner(processID: processID)
    do {
      try requestPipe.fileHandleForReading.close()
      try responsePipe.fileHandleForWriting.close()
    } catch {
      _ = owner.terminateAndReap(initialGracePeriod: .zero, signalGracePeriod: .seconds(1))
      throw .inputOutputFailure(reason: String(describing: error))
    }
    return Launch(
      owner: owner,
      requestHandle: requestPipe.fileHandleForWriting,
      responseHandle: responsePipe.fileHandleForReading
    )
  }

  package var isRunning: Bool {
    !pollForExit()
  }

  package func terminateAndReap(
    initialGracePeriod: Duration,
    signalGracePeriod: Duration
  ) -> String? {
    if waitForExit(for: initialGracePeriod) { return nil }
    if kill(-processID, SIGTERM) != 0, errno != ESRCH {
      return "SIGTERM failed for process group \(processID) with errno \(errno)."
    }
    if waitForExit(for: signalGracePeriod) { return nil }
    if kill(-processID, SIGKILL) != 0, errno != ESRCH {
      return "SIGKILL failed for process group \(processID) with errno \(errno)."
    }
    if waitForExit(for: signalGracePeriod) { return nil }
    return "Process \(processID) did not exit and reap after SIGKILL."
  }

  private func waitForExit(for duration: Duration) -> Bool {
    if pollForExit() { return true }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    while clock.now < deadline {
      Thread.sleep(forTimeInterval: 0.01)
      if pollForExit() { return true }
    }
    return pollForExit()
  }

  private func pollForExit() -> Bool {
    state.withLock { state in
      if state.isReaped { return true }
      var status: Int32 = 0
      let result = waitpid(processID, &status, WNOHANG)
      if result == processID || (result == -1 && errno == ECHILD) {
        state.isReaped = true
        return true
      }
      return false
    }
  }

  private static func addClose(
    _ actions: inout posix_spawn_file_actions_t?,
    descriptor: Int32
  ) throws(DesignDatabaseServiceWireTransportError) {
    try requireSuccess(
      posix_spawn_file_actions_addclose(&actions, descriptor),
      operation: "posix_spawn_file_actions_addclose"
    )
  }

  private static func addDuplicate(
    _ actions: inout posix_spawn_file_actions_t?,
    from source: Int32,
    to destination: Int32
  ) throws(DesignDatabaseServiceWireTransportError) {
    try requireSuccess(
      posix_spawn_file_actions_adddup2(&actions, source, destination),
      operation: "posix_spawn_file_actions_adddup2"
    )
  }

  private static func requireSuccess(
    _ result: Int32,
    operation: String
  ) throws(DesignDatabaseServiceWireTransportError) {
    guard result == 0 else {
      throw .inputOutputFailure(
        reason: "\(operation) failed with error code \(result)."
      )
    }
  }
}

private final class ProcessCStringArray {
  private var pointers: [UnsafeMutablePointer<CChar>?] = []

  init(_ strings: [String]) throws(DesignDatabaseServiceWireTransportError) {
    for string in strings {
      guard let pointer = strdup(string) else {
        throw .inputOutputFailure(reason: "strdup failed with ENOMEM.")
      }
      pointers.append(pointer)
    }
    pointers.append(nil)
  }

  deinit {
    for pointer in pointers { free(pointer) }
  }

  func withUnsafeMutablePointers<Result>(
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
  ) throws -> Result {
    try pointers.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        throw DesignDatabaseServiceWireTransportError.inputOutputFailure(
          reason: "The process argument buffer is unavailable."
        )
      }
      return try body(baseAddress)
    }
  }
}
#endif
