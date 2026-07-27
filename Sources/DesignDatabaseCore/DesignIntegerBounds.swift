public struct DesignIntegerBounds: Sendable, Hashable, Codable {
  public let minimumX: Int64
  public let minimumY: Int64
  public let maximumX: Int64
  public let maximumY: Int64

  public init(
    minimumX: Int64,
    minimumY: Int64,
    maximumX: Int64,
    maximumY: Int64
  ) throws(DesignDatabaseError) {
    guard minimumX <= maximumX, minimumY <= maximumY else {
      throw DesignDatabaseError.invalidSpatialBounds
    }
    self.minimumX = minimumX
    self.minimumY = minimumY
    self.maximumX = maximumX
    self.maximumY = maximumY
  }

  public func intersects(_ other: Self) -> Bool {
    minimumX <= other.maximumX && maximumX >= other.minimumX
      && minimumY <= other.maximumY && maximumY >= other.minimumY
  }

  public func contains(_ other: Self) -> Bool {
    minimumX <= other.minimumX && minimumY <= other.minimumY
      && maximumX >= other.maximumX && maximumY >= other.maximumY
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      minimumX: container.decode(Int64.self, forKey: .minimumX),
      minimumY: container.decode(Int64.self, forKey: .minimumY),
      maximumX: container.decode(Int64.self, forKey: .maximumX),
      maximumY: container.decode(Int64.self, forKey: .maximumY)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case minimumX, minimumY, maximumX, maximumY
  }
}
