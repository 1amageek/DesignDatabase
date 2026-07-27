public struct DesignQueryExplain: Sendable, Hashable, Codable {
  public let selectedIndex: DesignIndexKind
  public let estimatedScanCount: UInt64
  public let admittedFullScan: Bool
  public let ordering: DesignOrdering

  public init(
    selectedIndex: DesignIndexKind,
    estimatedScanCount: UInt64,
    admittedFullScan: Bool,
    ordering: DesignOrdering
  ) {
    self.selectedIndex = selectedIndex
    self.estimatedScanCount = estimatedScanCount
    self.admittedFullScan = admittedFullScan
    self.ordering = ordering
  }
}
