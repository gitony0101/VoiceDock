//
//  FrontmostApplicationProviding.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit

/// Protocol for providing information about the frontmost application.
///
/// This abstraction enables testing of terminal-detection logic without
/// requiring actual app-switching or Accessibility permissions.
public protocol FrontmostApplicationProviding {
    /// The bundle identifier of the currently frontmost application.
    ///
    /// Returns nil if the bundle identifier cannot be determined.
    var frontmostBundleIdentifier: String? { get }
}

/// Production implementation using NSWorkspace.
public struct NSWorkspaceFrontmostAppProvider: FrontmostApplicationProviding {
    public init() {}

    public var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

/// Test implementation for unit tests.
public struct MockFrontmostAppProvider: FrontmostApplicationProviding {
    public var frontmostBundleIdentifier: String?

    public init(bundleId: String? = nil) {
        self.frontmostBundleIdentifier = bundleId
    }
}