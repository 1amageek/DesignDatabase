import CircuiteFoundation

public struct DesignServiceNegotiationResult: Sendable, Hashable, Codable {
  public let report: DesignCompatibilityReport

  public init(report: DesignCompatibilityReport) {
    self.report = report
  }
}
