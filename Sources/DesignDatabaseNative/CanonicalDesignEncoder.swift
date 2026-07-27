import CircuiteFoundation
import DesignDatabaseCore
import Foundation

enum CanonicalDesignEncoder {
  static func stateDigest(
    entities: [DesignEntityID: DesignEntityRecord],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    let canonical = entities.values.sorted { $0.key.entityID < $1.key.entityID }.map {
      CanonicalEntity(record: $0)
    }
    return try digest(canonical, using: digester)
  }

  static func changeDigest(
    changes: [DesignEntityChange],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    try digest(changes.sorted(by: changePrecedes), using: digester)
  }

  static func sortedChanges(_ changes: [DesignEntityChange]) -> [DesignEntityChange] {
    changes.sorted(by: changePrecedes)
  }

  private static func digest<Value: Encodable>(
    _ value: Value,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return try digester.digest(data: encoder.encode(value), using: .sha256)
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .contentDigest(String(describing: error))
    }
  }

  private static func changePrecedes(_ lhs: DesignEntityChange, _ rhs: DesignEntityChange) -> Bool {
    changeKey(lhs).lexicographicallyPrecedes(changeKey(rhs))
  }

  private static func changeKey(_ change: DesignEntityChange) -> [String] {
    switch change {
    case .created(let id): return [id.description, "0"]
    case .deleted(let id): return [id.description, "1"]
    case .fieldChanged(let id, let field): return [id.description, "2", field.rawValue]
    case .relationChanged(let id, let relation): return [id.description, "3", relation.rawValue]
    case .spatialChanged(let id): return [id.description, "4"]
    }
  }

  private struct CanonicalEntity: Encodable {
    let entityID: DesignEntityID
    let facetID: DesignFacetID
    let kindID: DesignEntityKindID
    let fields: [CanonicalField]
    let relations: [CanonicalRelation]
    let spatialEntries: [DesignSpatialEntry]

    init(record: DesignEntityRecord) {
      entityID = record.key.entityID
      facetID = record.facetID
      kindID = record.kindID
      fields = record.fields.map { CanonicalField(id: $0.key, value: $0.value) }.sorted {
        $0.id < $1.id
      }
      relations = record.relations.map {
        CanonicalRelation(id: $0.key, targets: $0.value.sorted())
      }.sorted { $0.id < $1.id }
      spatialEntries = record.spatialEntries.sorted {
        if $0.container != $1.container { return $0.container < $1.container }
        if $0.layer?.rawValue != $1.layer?.rawValue {
          return ($0.layer?.rawValue ?? "") < ($1.layer?.rawValue ?? "")
        }
        if $0.bounds.minimumX != $1.bounds.minimumX {
          return $0.bounds.minimumX < $1.bounds.minimumX
        }
        if $0.bounds.minimumY != $1.bounds.minimumY {
          return $0.bounds.minimumY < $1.bounds.minimumY
        }
        if $0.bounds.maximumX != $1.bounds.maximumX {
          return $0.bounds.maximumX < $1.bounds.maximumX
        }
        return $0.bounds.maximumY < $1.bounds.maximumY
      }
    }
  }

  private struct CanonicalField: Encodable {
    let id: DesignFieldID
    let value: DesignValue
  }

  private struct CanonicalRelation: Encodable {
    let id: DesignRelationKindID
    let targets: [DesignEntityID]
  }
}
