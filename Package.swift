// swift-tools-version: 6.4
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
  atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace
  && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
  )
  ? .package(path: "../CircuiteFoundation")
  : .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    revision: "1dd75ecf2b8758c54c4e008ff5fd59e263cce0e6"
  )

let databaseFrameworkDependency: Package.Dependency = .package(
  url: "https://github.com/1amageek/database-framework.git",
  exact: "26.0809.1",
  traits: ["SQLite"]
)

let package = Package(
  name: "DesignDatabase",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "DesignDatabaseCore", targets: ["DesignDatabaseCore"]),
    .library(name: "DesignDatabaseNative", targets: ["DesignDatabaseNative"]),
    .library(name: "DesignDatabasePersistence", targets: ["DesignDatabasePersistence"]),
    .library(name: "DesignDatabaseRuntime", targets: ["DesignDatabaseRuntime"]),
    .library(name: "DesignDatabaseService", targets: ["DesignDatabaseService"]),
  ],
  traits: [
    .default(enabledTraits: ["FoundationSerialization"]),
    .trait(
      name: "FoundationSerialization",
      description: "Enables Foundation-backed Codable contracts for host persistence and service boundaries."
    ),
  ],
  dependencies: [
    circuiteFoundationDependency,
    databaseFrameworkDependency,
  ],
  targets: [
    .target(
      name: "DesignDatabaseCore",
      dependencies: [
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(
          name: "CircuiteFoundationFoundation",
          package: "CircuiteFoundation",
          condition: .when(traits: ["FoundationSerialization"])
        ),
      ],
      swiftSettings: [
        .define(
          "DESIGN_DATABASE_FOUNDATION_SERIALIZATION",
          .when(traits: ["FoundationSerialization"])
        ),
      ]
    ),
    .target(
      name: "DesignDatabaseNative",
      dependencies: [
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
      ]
    ),
    .target(
      name: "DesignDatabasePersistence",
      dependencies: [
        "DesignDatabaseCore",
        "DesignDatabaseNative",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
      ]
    ),
    .target(
      name: "DesignDatabaseRuntime",
      dependencies: [
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
        .product(name: "Database", package: "database-framework"),
      ]
    ),
    .target(
      name: "DesignDatabaseService",
      dependencies: [
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
      ]
    ),
    .target(
      name: "DesignDatabaseCorePortabilityProbeSupport",
      dependencies: ["DesignDatabaseCore"]
    ),
    .executableTarget(
      name: "DesignDatabaseCorePortabilityProbe",
      dependencies: ["DesignDatabaseCorePortabilityProbeSupport"]
    ),
    .executableTarget(
      name: "DesignDatabaseEmbeddedCorePortabilityProbe",
      dependencies: ["DesignDatabaseCorePortabilityProbeSupport"],
      linkerSettings: [
        .linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi]))
      ]
    ),
    .testTarget(
      name: "DesignDatabaseCoreTests",
      dependencies: [
        "DesignDatabaseCore",
        "DesignDatabaseNative",
        .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
      ]
    ),
    .testTarget(
      name: "DesignDatabasePersistenceTests",
      dependencies: [
        "DesignDatabasePersistence",
        "DesignDatabaseNative",
        .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
      ]
    ),
    .testTarget(
      name: "DesignDatabaseRuntimeTests",
      dependencies: [
        "DesignDatabaseRuntime",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
        .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
        .product(name: "Database", package: "database-framework"),
      ],
      resources: [
        .process("PerformanceEvidence")
      ]
    ),
    .testTarget(
      name: "DesignDatabaseServiceTests",
      dependencies: [
        "DesignDatabaseService",
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
      ]
    ),
  ]
)
