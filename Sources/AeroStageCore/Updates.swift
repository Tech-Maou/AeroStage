import Foundation

/// A release version such as "1.2.0", "v1.3.0" or "0.21.3-stage.2", compared by its numbers in
/// order: "0.21.3-stage.2" < "0.21.3-stage.10" < "0.22.0-stage.1". Missing numbers count as 0.
public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    public let description: String
    public let numbers: [Int]

    public init(_ string: String) {
        description = string.hasPrefix("v") ? String(string.dropFirst()) : string
        numbers = description.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The parts of a GitHub release that the update check needs
/// (`GET /repos/{owner}/{repo}/releases/latest`).
public struct Release: Decodable, Sendable, Equatable {
    public let tagName: String
    public let htmlURL: URL
    public let body: String?

    public var version: ReleaseVersion { ReleaseVersion(tagName) }

    public init(tagName: String, htmlURL: URL, body: String?) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}

/// The two apps AeroStage checks for updates, with their GitHub repository and Homebrew cask.
public enum UpdateComponent: String, CaseIterable, Sendable {
    case aeroStage
    case windowManager

    public var title: String {
        switch self {
        case .aeroStage: "AeroStage"
        case .windowManager: "AeroStage WM"
        }
    }

    public var bundleID: String {
        switch self {
        case .aeroStage: "io.github.tech-maou.AeroStage"
        case .windowManager: "io.github.tech-maou.AeroStageWM"
        }
    }

    public var repository: String {
        switch self {
        case .aeroStage: "Tech-Maou/AeroStage"
        case .windowManager: "Tech-Maou/AeroStage-WM"
        }
    }

    public var cask: String {
        switch self {
        case .aeroStage: "tech-maou/tap/aerostage"
        case .windowManager: "tech-maou/tap/aerostage-wm"
        }
    }

    /// Name of the cask's folder in Homebrew's Caskroom.
    public var caskToken: String { String(cask.split(separator: "/").last ?? "") }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// The release to offer, or nil if `installed` is up to date or unknown.
    public static func update(installed: String?, latest: Release) -> Release? {
        guard let installed else { return nil }
        return ReleaseVersion(installed) < latest.version ? latest : nil
    }
}
