// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ColorPicker",
    platforms: [.macOS(.v12)],
    // Only application targets link this product; shared libraries import its headers.
    products: [
        .library(name: "ColorPicker", type: .static, targets: ["ColorPicker"])
    ],
    targets: [
        .target(
            name: "ColorPicker",
            path: "ColorPicker",
            exclude: ["Info.plist", "Images/ColorPicker.sketch"],
            resources: [
                .process("colors.txt"),
                .process("Images/ActiveEscapeHatch/ActiveEscapeHatch.png"),
                .process("Images/ActiveEscapeHatch/ActiveEscapeHatch@2x.png"),
                .process("Images/ActiveEyedropper/ActiveEyedropper.png"),
                .process("Images/ActiveEyedropper/ActiveEyedropper@2x.png"),
                .process("Images/Add/Add.png"),
                .process("Images/Add/Add@2x.png"),
                .process("Images/EscapeHatch/EscapeHatch.png"),
                .process("Images/EscapeHatch/EscapeHatch@2x.png"),
                .process("Images/Eyedropper/Eyedropper.png"),
                .process("Images/Eyedropper/Eyedropper@2x.png"),
                .process("Images/HSB/HSB.png"),
                .process("Images/HSB/HSB@2x.png"),
                .process("Images/NoColor/NoColor.png"),
                .process("Images/NoColor/NoColor@2x.png"),
                .process("Images/RGB/RGB.png"),
                .process("Images/RGB/RGB@2x.png"),
                .process("Images/Remove/Remove.png"),
                .process("Images/Remove/Remove@2x.png"),
                .process("Images/SelectedAlphaIndicator/SelectionIndicator.png"),
                .process("Images/SelectedAlphaIndicator/SelectionIndicator@2x.png"),
                .process("Images/SelectedColorIndicator/SelectedColorIndicator.png"),
                .process("Images/SelectedColorIndicator/SelectedColorIndicator@2x.png"),
                .process("Images/SwatchCheckerboard/SwatchCheckerboard.png"),
                .process("Images/SwatchCheckerboard/SwatchCheckerboard@2x.png")
            ],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include/ColorPicker")]
        )
    ]
)
