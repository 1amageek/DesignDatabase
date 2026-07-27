// swift-tools-version: 6.3
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

let package = Package(
  name: "DesignDatabase",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "DesignDatabaseCore", targets: ["DesignDatabaseCore"]),
    .library(name: "DesignDatabaseNative", targets: ["DesignDatabaseNative"]),
    .library(name: "DesignDatabasePersistence", targets: ["DesignDatabasePersistence"]),
    .library(name: "DesignDatabaseService", targets: ["DesignDatabaseService"]),
  ],
  dependencies: [
    circuiteFoundationDependency
  ],
  targets: [
    .target(
      name: "DesignDatabaseCore",
      dependencies: [
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation")
      ]
    ),
    .target(
      name: "DesignDatabaseNative",
      dependencies: [
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation")
      ]
    ),
    .target(
      name: "DesignDatabasePersistence",
      dependencies: [
        "DesignDatabaseCore",
        "DesignDatabaseNative",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation")
      ]
    ),
    .target(
      name: "DesignDatabaseService",
      dependencies: [
        "DesignDatabaseCore",
        .product(name: "CircuiteFoundation", package: "CircuiteFoundation")
      ]
    ),
    .testTarget(
      name: "DesignDatabaseCoreTests",
      dependencies: ["DesignDatabaseCore", "DesignDatabaseNative"]
    ),
    .testTarget(
      name: "DesignDatabasePersistenceTests",
      dependencies: ["DesignDatabasePersistence", "DesignDatabaseNative"]
    ),
    .testTarget(
      name: "DesignDatabaseServiceTests",
      dependencies: ["DesignDatabaseService", "DesignDatabaseNative"]
    ),
  ]
)
