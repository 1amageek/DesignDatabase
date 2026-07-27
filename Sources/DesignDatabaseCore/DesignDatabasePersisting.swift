import CircuiteFoundation

public protocol DesignDatabasePersisting: Sendable {
  func load() async throws(DesignDatabaseError) -> DesignDatabaseImage?

  func persist(
    _ image: DesignDatabaseImage,
    publishing revision: DesignRevisionReference?
  ) async throws(DesignDatabaseError)

  func close() async throws(DesignDatabaseError)
}
