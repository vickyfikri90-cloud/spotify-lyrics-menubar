// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LyricsMenuBar",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "YTMusicLyrics"),
        .executableTarget(name: "LyricsMenuBar", dependencies: ["YTMusicLyrics"]),
        .testTarget(name: "YTMusicLyricsTests", dependencies: ["YTMusicLyrics"]),
        .testTarget(name: "LyricsMenuBarTests", dependencies: ["LyricsMenuBar"])
    ]
)
