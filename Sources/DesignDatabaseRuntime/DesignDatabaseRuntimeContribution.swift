import CircuiteFoundation
import Database
import DesignDatabaseCore

public struct DesignDatabaseRuntimeContribution: Sendable {
  public let id: DesignDatabaseRuntimeContributionID
  public let designSchemaMember: DesignSchemaBundleMember?
  public let bindingDigest: ContentDigest
  public let entities: [Schema.Entity]
  public let entityRuntimes: [EntityRuntimeRegistration]
  public let mutationAdapter: (any DesignDatabaseRuntimeMutationAdapter)?
  public let physicalWriteReclaimers: [
    any DesignDatabaseRuntimePhysicalWriteReclaimer
  ]

  public init(
    id: DesignDatabaseRuntimeContributionID,
    designSchemaMember: DesignSchemaBundleMember,
    bindingDigest: ContentDigest,
    entities: [Schema.Entity],
    entityRuntimes: [EntityRuntimeRegistration],
    mutationAdapter: (any DesignDatabaseRuntimeMutationAdapter)? = nil,
    physicalWriteReclaimers: [
      any DesignDatabaseRuntimePhysicalWriteReclaimer
    ] = []
  ) throws(DesignDatabaseRuntimeError) {
    try self.init(
      id: id,
      internalDesignSchemaMember: designSchemaMember,
      bindingDigest: bindingDigest,
      entities: entities,
      entityRuntimes: entityRuntimes,
      mutationAdapter: mutationAdapter,
      physicalWriteReclaimers: physicalWriteReclaimers
    )
  }

  package init(
    coreID id: DesignDatabaseRuntimeContributionID,
    bindingDigest: ContentDigest,
    entities: [Schema.Entity],
    entityRuntimes: [EntityRuntimeRegistration]
  ) throws(DesignDatabaseRuntimeError) {
    try self.init(
      id: id,
      internalDesignSchemaMember: nil,
      bindingDigest: bindingDigest,
      entities: entities,
      entityRuntimes: entityRuntimes,
      mutationAdapter: nil,
      physicalWriteReclaimers: []
    )
  }

  private init(
    id: DesignDatabaseRuntimeContributionID,
    internalDesignSchemaMember designSchemaMember: DesignSchemaBundleMember?,
    bindingDigest: ContentDigest,
    entities: [Schema.Entity],
    entityRuntimes: [EntityRuntimeRegistration],
    mutationAdapter: (any DesignDatabaseRuntimeMutationAdapter)?,
    physicalWriteReclaimers: [
      any DesignDatabaseRuntimePhysicalWriteReclaimer
    ]
  ) throws(DesignDatabaseRuntimeError) {
    guard !entities.isEmpty else {
      throw .emptyContribution(id)
    }
    let entityNames = entities.map(\.name).sorted()
    let runtimeEntityNames = entityRuntimes.map(\.entity.name).sorted()
    guard entityNames == runtimeEntityNames else {
      throw .contributionEntityRuntimeMismatch(
        contribution: id,
        entityNames: entityNames,
        runtimeEntityNames: runtimeEntityNames
      )
    }
    if let mutationAdapter {
      guard let designSchemaMember,
            mutationAdapter.schemaID == designSchemaMember.schemaID,
            mutationAdapter.schemaVersion == designSchemaMember.version,
            !mutationAdapter.adapterVersion.isEmpty,
            !mutationAdapter.supportedFacets.isEmpty else {
        throw .mutationAdapterBindingMismatch(contribution: id)
      }
    }
    let storageTypes = physicalWriteReclaimers.map(\.storageType).sorted()
    guard storageTypes.allSatisfy({ !$0.isEmpty }) else {
      throw .invalidPhysicalWriteReclaimer(storageType: "")
    }
    for index in storageTypes.indices.dropFirst()
      where storageTypes[index - 1] == storageTypes[index] {
      throw .duplicatePhysicalWriteReclaimer(
        storageType: storageTypes[index]
      )
    }
    self.id = id
    self.designSchemaMember = designSchemaMember
    self.bindingDigest = bindingDigest
    self.entities = entities
    self.entityRuntimes = entityRuntimes
    self.mutationAdapter = mutationAdapter
    self.physicalWriteReclaimers = physicalWriteReclaimers
  }
}
