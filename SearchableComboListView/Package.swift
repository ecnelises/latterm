// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SearchableComboListView",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "SearchableComboListView", type: .dynamic, targets: ["SearchableComboListView"])
    ],
    targets: [
        .target(
            name: "SearchableComboListView",
            path: "SearchableComboView",
            exclude: ["Info.plist", "SearchableComboListView.h"],
            resources: [.process("SearchableComboView.xib")]
        )
    ]
)
