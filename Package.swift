// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YouyeHealthCoach",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "YouyeHealthCoach", targets: ["YouyeHealthCoach"]),
        .executable(name: "YouyeHealthCoachRuleCheck", targets: ["YouyeHealthCoachRuleCheck"])
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", .upToNextMinor(from: "0.14.1")),
        // Apple Health exports are ZIP archives. Keep this as a reviewed, read-only parser
        // dependency; the app never writes back into the selected archive or uploads it.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.20"))
    ],
    targets: [
        .target(
            name: "YouyeHealthCoach",
            dependencies: [
                .product(
                    name: "CoreXLSX",
                    package: "CoreXLSX",
                    condition: .when(platforms: [.iOS, .macOS])
                ),
                .product(
                    name: "ZIPFoundation",
                    package: "ZIPFoundation",
                    condition: .when(platforms: [.iOS, .macOS])
                )
            ]
        ),
        .executableTarget(name: "YouyeHealthCoachRuleCheck", dependencies: ["YouyeHealthCoach"])
    ]
)
