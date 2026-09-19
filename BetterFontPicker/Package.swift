// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BetterFontPicker",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "BetterFontPicker", type: .dynamic, targets: ["BetterFontPicker"])
    ],
    targets: [
        .target(
            name: "BetterFontPicker",
            path: "BetterFontPicker",
            exclude: [
                "Info.plist", "BetterFontPicker.h", "Icons.sketch", "Icons2.sketch",
                "StatusBarIconNoBattery.png", "StatusBarIconNoBattery@2x.png"
            ],
            resources: [
                .process("MainViewController.xib"),
                .process("EmptyStar.png"),
                .process("EmptyStar@2x.png"),
                .process("FilledStar.png"),
                .process("FilledStar@2x.png"),
                .process("HorizontalSpacingIcon.png"),
                .process("HorizontalSpacingIcon@2x.png"),
                .process("VerticalSpacingIcon.png"),
                .process("VerticalSpacingIcon@2x.png")
            ]
        )
    ]
)
