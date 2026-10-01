// swift-tools-version:5.9
import PackageDescription

// The scanning, knowledge base and safety logic lives in DataExplorerCore so it can be
// unit tested on its own. The SwiftUI app target is only available when building on macOS.
var products: [Product] = [
    .library(name: "DataExplorerCore", targets: ["DataExplorerCore"]),
]

var targets: [Target] = [
    .target(
        name: "DataExplorerCore",
        path: "Sources/DataExplorerCore"
    ),
    .testTarget(
        name: "DataExplorerCoreTests",
        dependencies: ["DataExplorerCore"],
        path: "Tests/DataExplorerCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "DataExplorer", targets: ["DataExplorer"]))
targets.append(
    .executableTarget(
        name: "DataExplorer",
        dependencies: ["DataExplorerCore"],
        path: "Sources/DataExplorer"
    )
)
#endif

let package = Package(
    name: "DataExplorer",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
