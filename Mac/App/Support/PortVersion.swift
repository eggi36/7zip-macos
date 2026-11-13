// PortVersion.swift -- the port's version as the user sees it (pub3, ai/reports/pub3.md).
//
// Two numbers: the 7-Zip engine the app is built on (upstream, "26.03", C/7zVersion.h) and the
// macOS port's own semantic version ("1.0.0", Mac/VERSION -> MARKETING_VERSION ->
// CFBundleShortVersionString). Together: "7-Zip 26.03 for macOS 1.0.0", the name in the About box,
// the disk image and the release notes.

import Foundation
import SevenZipKit

enum PortVersion {

    /// The port's version, CFBundleShortVersionString ("1.0.0").
    static var port: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The build number, CFBundleVersion (the commit count the release was built from).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// What makes this build unique: when it was built and from which commit ("2026-11-13
    /// 21:50:07 1faab4b0c2", "+" for uncommitted changes), written by the app target's "Build
    /// stamp" phase (Mac/project.yml). Empty in a copy built without it (the test hosts).
    static var buildStamp: String {
        Bundle.main.object(forInfoDictionaryKey: "SZBuildStamp") as? String ?? ""
    }

    /// The About box's build line: "Build 402 (2026-11-13 21:50:07 1faab4b0c2)".
    static func buildLine(build: String = build, stamp: String = buildStamp) -> String {
        stamp.isEmpty ? "Build \(build)" : "Build \(build) (\(stamp))"
    }

    /// The engine's version, MY_VERSION of C/7zVersion.h ("26.03").
    static var upstream: String { SZEngineVersionString() }

    /// "7-Zip 26.03 for macOS 1.0.0".
    static func displayName(upstream: String = upstream, port: String = port) -> String {
        "7-Zip \(upstream) for macOS \(port)"
    }

    static var displayName: String { displayName() }
}
