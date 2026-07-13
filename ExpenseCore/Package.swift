// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExpenseCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ExpenseCore",
            targets: ["ExpenseCore"]
        )
    ],
    targets: [
        .target(
            name: "ExpenseCore"
        ),
        .testTarget(
            name: "ExpenseCoreTests",
            dependencies: ["ExpenseCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
