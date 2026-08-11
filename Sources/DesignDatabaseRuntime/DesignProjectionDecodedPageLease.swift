import CircuiteFoundation
import DesignDatabaseCore
import Synchronization

package final class DesignProjectionDecodedPageLease: Sendable {
  private let cache: DesignProjectionDecodedPageCache?
  private let key: DesignProjectionDecodedPageKey
  private let page: DesignProjectionDecodedPage
  private let releaseState = Mutex(false)

  package init(
    cache: DesignProjectionDecodedPageCache?,
    key: DesignProjectionDecodedPageKey,
    page: DesignProjectionDecodedPage
  ) {
    self.cache = cache
    self.key = key
    self.page = page
  }

  deinit {
    close()
  }

  package var digest: ContentDigest { page.digest }
  package var family: DesignProjectionFamily { page.family }
  package var kind: DesignProjectionNodeKind { page.kind }
  package var level: UInt16 { page.level }
  package var minimumKey: DesignCanonicalKey? { page.minimumKey }
  package var maximumKey: DesignCanonicalKey? { page.maximumKey }
  package var subtreeEntryCount: UInt64 { page.subtreeEntryCount }
  package var subtreeNodeCount: UInt64 { page.subtreeNodeCount }
  package var encodedByteCount: UInt64 { page.encodedByteCount }
  package var entryCount: Int { page.entryCount }
  package var childCount: Int { page.childCount }

  package func entry(at index: Int) -> DesignProjectionEntry {
    page.entry(at: index)
  }

  package func child(at index: Int) -> DesignProjectionChildReference {
    page.child(at: index)
  }

  package func close() {
    let shouldRelease = releaseState.withLock { released in
      guard !released else { return false }
      released = true
      return true
    }
    guard shouldRelease else { return }
    cache?.release(key)
  }
}
