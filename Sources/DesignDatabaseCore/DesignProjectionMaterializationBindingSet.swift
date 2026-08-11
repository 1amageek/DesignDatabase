public struct DesignProjectionMaterializationBindingSet: Sendable, Hashable, DesignDatabaseSerializable {
  public let bindings: [DesignProjectionMaterializationBinding]

  public init(
    _ bindings: [DesignProjectionMaterializationBinding]
  ) throws(DesignDatabaseError) {
    let ordered = bindings.sorted()
    for index in ordered.indices.dropFirst() where
      ordered[index - 1].family == ordered[index].family {
      throw .invalidQuery(
        "A projection materialization binding set contains a duplicate family."
      )
    }
    self.bindings = ordered
  }

  public subscript(
    family: DesignProjectionFamily
  ) -> DesignProjectionMaterializationReference? {
    bindings.first { $0.family == family }?.materialization
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case bindings
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        container.decode(
          [DesignProjectionMaterializationBinding].self,
          forKey: .bindings
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif
}
