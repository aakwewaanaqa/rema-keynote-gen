// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BibleQueryApp",
    platforms: [.macOS(.v13)],
    targets: [
        // 查經文（search DSL、各聖經來源）、範本代換、Keynote（osascript）、歌詞解析——
        // 以前是 src/ 底下的 Ruby，App 透過 Process 呼叫 *_cli.rb；現在全部搬進這個 library，App 直接呼叫
        .target(
            name: "RemaCore",
            linkerSettings: [.linkedLibrary("xml2")]
        ),
        .executableTarget(
            name: "AdvancedBibleQueryApp",
            dependencies: ["RemaCore"]
        ),
        .testTarget(
            name: "RemaCoreTests",
            dependencies: ["RemaCore"]
        ),
    ]
)
