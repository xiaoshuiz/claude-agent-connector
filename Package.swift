// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeAgentConnector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeAgentConnector", targets: ["ClaudeAgentConnector"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAgentConnector",
            path: "Sources/ClaudeAgentConnector"
        )
    ]
)
