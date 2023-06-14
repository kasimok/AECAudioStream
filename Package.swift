// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AECAudioStream",
  platforms: [
    .macOS(.v12),
    .iOS(.v15),
    .tvOS(.v15)
  ],
  products: [
    .library(
      name: "AECAudioStream",
      targets: ["AECAudioStream"]),
  ],
  targets: [
    .target(
      name: "AECAudioStream"),
    .testTarget(
      name: "AECAudioStreamTests",
      dependencies: ["AECAudioStream"]),
  ]
)
