// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "project-template",
    products: [
        .library(
            name: "project-template",
            targets: ["project-template"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
    ],
    targets: [
        .target(
            name: "project-template",
            path: "Sources/project-template"),
        .executableTarget(
            name: "hello",
            dependencies: ["project-template"],
            path: "Sources/hello",
            resources: [.process("Resources")]),
        .testTarget(
            name: "project-templateTests",
            dependencies: [
                "project-template",
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Tests/project-templateTests"),
    ]
)
