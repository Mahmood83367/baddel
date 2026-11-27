import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A semantic version: `MAJOR.MINOR.PATCH` with an optional pre-release part.
public struct SemanticVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    /// Accepts `1.2.3`, `1.2.3-preview.1`, and the same with a leading `v`.
    public init?(_ text: String) {
        var body = Substring(text)
        if body.hasPrefix("v") { body = body.dropFirst() }
        if let plus = body.firstIndex(of: "+") { body = body[..<plus] }
        let parts = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Self.number(numbers[0]), let minor = Self.number(numbers[1]), let patch = Self.number(numbers[2])
        else { return nil }
        var prerelease: [String] = []
        if parts.count == 2 {
            prerelease = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let allowed = Set("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-")
            guard !prerelease.isEmpty, prerelease.allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed.contains) }) else { return nil }
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 9, text.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int(text)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        // A version with a pre-release part comes before the same version without one.
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            default: return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}

/// Which releases a user wants to hear about.
public enum UpdateChannel: String, Codable, Sendable, CaseIterable {
    /// Full releases only.
    case stable
    /// Full releases and previews (GitHub "pre-release").
    case preview
}

/// One published release, as listed by the GitHub releases API.
public struct PublishedRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let prerelease: Bool
    public let draft: Bool
    public let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", prerelease, draft, htmlUrl = "html_url"
    }
}

public struct UpdateCheckResult: Equatable, Sendable {
    public let current: String
    public let channel: UpdateChannel
    /// The newest release on the channel, if the channel has any.
    public let latest: String?
    /// Where to read about and download it; always an official release page.
    public let releasePage: String?
    public let updateAvailable: Bool
}

public enum UpdateCheck {
    /// Only pages and files of the official repository's releases are accepted.
    public static let officialReleasePrefix = "https://github.com/Mahmood83367/baddel/releases/"
    public static let releasesAPI = "https://api.github.com/repos/Mahmood83367/baddel/releases?per_page=30"

    /// Picks the newest release of a channel from the API response. Drafts,
    /// tags that are not versions, and anything not hosted on the official
    /// releases page are ignored.
    public static func evaluate(releasesJSON: Data, current: String, channel: UpdateChannel) -> UpdateCheckResult? {
        guard let currentVersion = SemanticVersion(current),
              let releases = try? JSONDecoder().decode([PublishedRelease].self, from: releasesJSON) else { return nil }
        let candidates = releases.compactMap { release -> (SemanticVersion, PublishedRelease)? in
            guard !release.draft, release.htmlUrl.hasPrefix(officialReleasePrefix),
                  let version = SemanticVersion(release.tagName) else { return nil }
            let preview = release.prerelease || version.isPrerelease
            return channel == .stable && preview ? nil : (version, release)
        }
        guard let newest = candidates.max(by: { $0.0 < $1.0 }) else {
            return UpdateCheckResult(current: current, channel: channel, latest: nil, releasePage: nil, updateAvailable: false)
        }
        return UpdateCheckResult(
            current: current, channel: channel, latest: newest.0.description, releasePage: newest.1.htmlUrl,
            updateAvailable: currentVersion < newest.0)
    }
}

/// A signed description of one release, the basis for installing an update.
///
/// Nothing installs updates yet. This type exists so that the checks an
/// installer must make are written and tested first: the manifest is only
/// accepted with a valid signature from a key compiled into the app, and a
/// package is only accepted from the official release assets with a matching
/// SHA-256.
public struct UpdateManifest: Decodable, Equatable, Sendable {
    public struct Package: Decodable, Equatable, Sendable {
        public let platform: String
        public let arch: String
        public let minOS: String
        public let url: String
        public let sha256: String
        public let size: Int
    }

    public let schema: Int
    public let channel: UpdateChannel
    public let version: String
    public let packages: [Package]

    public enum Failure: String, Error, Equatable, Sendable {
        case noTrustedKey
        case badSignature
        case malformed
        case unsupportedSchema
        case wrongChannel
        case notNewer
        case noPackageForThisSystem
        case untrustedLocation
        case hashMismatch
    }

    /// Keys allowed to sign update manifests, as DER SubjectPublicKeyInfo
    /// (ECDSA P-256). **Empty: no update signing key has been established, so
    /// no manifest can be trusted and automatic installation is impossible.**
    public static let trustedKeys: [Data] = []

    public static var automaticInstallationPossible: Bool { !trustedKeys.isEmpty }

    /// Verifies the signature over the exact manifest bytes, then parses and
    /// checks the manifest. Verification comes first: unsigned or wrongly
    /// signed data is never interpreted.
    public static func verified(
        manifest data: Data, signatureDER: Data, trustedKeys: [Data], channel: UpdateChannel, current: String
    ) -> Result<UpdateManifest, Failure> {
        guard !trustedKeys.isEmpty else { return .failure(.noTrustedKey) }
        guard trustedKeys.contains(where: { isValid(signatureDER: signatureDER, over: data, publicKeyDER: $0) }) else {
            return .failure(.badSignature)
        }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
              let version = SemanticVersion(manifest.version), let currentVersion = SemanticVersion(current) else {
            return .failure(.malformed)
        }
        guard manifest.schema == 1 else { return .failure(.unsupportedSchema) }
        guard manifest.channel == channel else { return .failure(.wrongChannel) }
        guard currentVersion < version else { return .failure(.notNewer) }
        for package in manifest.packages {
            guard package.url.hasPrefix(UpdateCheck.officialReleasePrefix + "download/"),
                  package.sha256.count == 64, package.sha256.allSatisfy({ $0.isHexDigit }), package.size > 0 else {
                return .failure(.untrustedLocation)
            }
        }
        return .success(manifest)
    }

    static func isValid(signatureDER: Data, over data: Data, publicKeyDER: Data) -> Bool {
        #if canImport(CryptoKit)
        guard let key = try? P256.Signing.PublicKey(derRepresentation: publicKeyDER),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER) else { return false }
        return key.isValidSignature(signature, for: data)
        #else
        return false
        #endif
    }

    /// The package for a system, or a failure if there is none that fits.
    public func package(platform: String, arch: String, osVersion: String) -> Result<Package, Failure> {
        func parts(_ text: String) -> [Int] { text.split(separator: ".").map { Int($0) ?? 0 } }
        func atLeast(_ have: String, _ need: String) -> Bool {
            let a = parts(have), b = parts(need)
            for index in 0..<max(a.count, b.count) {
                let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
                if x != y { return x > y }
            }
            return true
        }
        let match = packages.first {
            $0.platform == platform && ($0.arch == arch || $0.arch == "universal") && atLeast(osVersion, $0.minOS)
        }
        return match.map(Result.success) ?? .failure(.noPackageForThisSystem)
    }

    /// Whether a downloaded file is exactly the package the manifest describes.
    public static func matches(_ package: Package, fileData: Data) -> Bool {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
        return fileData.count == package.size && digest == package.sha256.lowercased()
        #else
        return false
        #endif
    }
}
