// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacMfile",
    defaultLocalization: "vi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacMfile", targets: ["MacMfile"])
    ],
    targets: [
        // Phần lõi không phụ thuộc AppKit: định dạng, đường dẫn, sắp xếp, ngôn ngữ.
        .target(name: "MfileCore"),
        // Ứng dụng AppKit.
        .executableTarget(name: "MacMfile", dependencies: ["MfileCore"]),
        .testTarget(name: "MfileCoreTests", dependencies: ["MfileCore"])
    ]
)
