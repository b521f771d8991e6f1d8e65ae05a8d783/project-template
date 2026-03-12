// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "project-template",
    products: [
        .library(
            name: "project-template",
            targets: ["project-template"]),
    ],
    targets: [
        .target(
            name: "project-template",
            path: "swift/Sources/project-template"),
        .testTarget(
            name: "project-templateTests",
            dependencies: ["project-template"],
            path: "swift/Tests/project-templateTests"),
    ]
)
