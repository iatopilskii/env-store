// swift-tools-version: 6.2

import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"]),
]

let package = Package(
    name: "EnvStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnvStoreCore", targets: ["EnvStoreCore"]),
        .library(name: "EnvStoreCrypto", targets: ["EnvStoreCrypto"]),
        .library(name: "EnvStoreStorage", targets: ["EnvStoreStorage"]),
        .library(name: "EnvStoreIPC", targets: ["EnvStoreIPC"]),
        .executable(name: "envstore", targets: ["EnvStoreCLI"]),
        .executable(name: "EnvStoreBroker", targets: ["EnvStoreBroker"]),
        .executable(name: "EnvStoreApp", targets: ["EnvStoreApp"]),
    ],
    targets: [
        .target(name: "EnvStoreCore", swiftSettings: strictSwiftSettings),
        .target(
            name: "EnvStoreCrypto",
            dependencies: ["EnvStoreCore"],
            swiftSettings: strictSwiftSettings
        ),
        .systemLibrary(name: "CSQLite"),
        .target(
            name: "EnvStoreStorage",
            dependencies: ["EnvStoreCore", "EnvStoreCrypto", "CSQLite"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "EnvStoreIPC",
            dependencies: ["EnvStoreCore"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "EnvStoreCLI",
            dependencies: ["EnvStoreCore", "EnvStoreIPC"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "EnvStoreBroker",
            dependencies: ["EnvStoreCore", "EnvStoreCrypto", "EnvStoreStorage", "EnvStoreIPC"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "EnvStoreApp",
            dependencies: ["EnvStoreCore", "EnvStoreIPC"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "EnvStoreCoreTests",
            dependencies: ["EnvStoreCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "EnvStoreCryptoTests",
            dependencies: ["EnvStoreCrypto"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "EnvStoreStorageTests",
            dependencies: ["EnvStoreStorage"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "EnvStoreIPCTests",
            dependencies: ["EnvStoreIPC"],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

