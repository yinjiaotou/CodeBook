// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PwdlockMac",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PwdlockCore", targets: ["PwdlockCore"]),
        .executable(name: "PwdlockMacApp", targets: ["PwdlockMacApp"])
    ],
    targets: [
        .systemLibrary(name: "CArgon2", pkgConfig: "libargon2", providers: [.brew(["argon2"])]),
        .systemLibrary(name: "CSQLCipher", pkgConfig: "sqlcipher", providers: [.brew(["sqlcipher"])]),
        .target(name: "PwdlockCore", dependencies: ["CArgon2", "CSQLCipher"]),
        .executableTarget(name: "PwdlockMacApp", dependencies: ["PwdlockCore"]),
        .testTarget(name: "PwdlockCoreTests", dependencies: ["PwdlockCore"]),
        .testTarget(name: "PwdlockMacAppTests", dependencies: ["PwdlockMacApp"])
    ]
)
