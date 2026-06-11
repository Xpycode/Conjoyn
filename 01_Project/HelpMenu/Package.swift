// swift-tools-version: 5.9
import PackageDescription

// HelpMenu — vendored into Conjoyn from 1-macOS/AppHelp (v1, 2026-06-11).
// Engine only: help window, sidebar, search, markdown renderer. Conjoyn owns
// the content (Conjoyn/Help/). Re-copy Sources/ from AppHelp to pick up fixes.
// Only external dependency is swift-markdown-ui (markdown rendering).
let package = Package(
    name: "HelpMenu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HelpMenu", targets: ["HelpMenu"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "HelpMenu",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        )
    ]
)
