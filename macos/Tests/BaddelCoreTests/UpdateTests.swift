import XCTest
@testable import BaddelCore

/// Runs `shared/fixtures/updates.json`, which the C# implementation runs too.
final class UpdateTests: XCTestCase {
    private struct Fixture: Decodable {
        struct ReleaseCheck: Decodable {
            let name: String, current: String, channel: UpdateChannel, latest: String?, updateAvailable: Bool
        }
        struct Manifest: Decodable {
            let file: String, signatureBase64: String, publicKeyBase64: String, otherPublicKeyBase64: String
            let channel: UpdateChannel, version: String, packageBytesUtf8: String
        }
        let versionOrder: [String], invalidVersions: [String], equalVersions: [[String]]
        let releaseChecks: [ReleaseCheck]
        let manifest: Manifest
    }

    private let directory = Shared.directory.appendingPathComponent("fixtures")
    private lazy var raw = try! Data(contentsOf: directory.appendingPathComponent("updates.json"))
    private lazy var fixture = try! JSONDecoder().decode(Fixture.self, from: raw)

    func testVersionOrdering() {
        let versions = fixture.versionOrder.map { SemanticVersion($0)! }
        for (index, version) in versions.enumerated() {
            XCTAssertEqual(version.description, fixture.versionOrder[index])
            for later in versions[(index + 1)...] {
                XCTAssertTrue(version < later, "\(version) < \(later)")
                XCTAssertFalse(later < version, "\(later) < \(version)")
            }
            XCTAssertFalse(version < version)
        }
        for text in fixture.invalidVersions { XCTAssertNil(SemanticVersion(text), text) }
        for pair in fixture.equalVersions { XCTAssertEqual(SemanticVersion(pair[0]), SemanticVersion(pair[1])) }
    }

    func testChannelSelection() throws {
        let cases = (try JSONSerialization.jsonObject(with: raw) as! [String: Any])["releaseChecks"] as! [[String: Any]]
        XCTAssertGreaterThan(cases.count, 8)
        for (index, expected) in fixture.releaseChecks.enumerated() {
            let releases = try JSONSerialization.data(withJSONObject: cases[index]["releases"]!)
            let result = UpdateCheck.evaluate(releasesJSON: releases, current: expected.current, channel: expected.channel)
            XCTAssertEqual(result?.latest, expected.latest, expected.name)
            XCTAssertEqual(result?.updateAvailable, expected.updateAvailable, expected.name)
            if let page = result?.releasePage { XCTAssertTrue(page.hasPrefix(UpdateCheck.officialReleasePrefix), expected.name) }
        }
        XCTAssertNil(UpdateCheck.evaluate(releasesJSON: Data("not json".utf8), current: "0.1.0", channel: .stable))
        XCTAssertNil(UpdateCheck.evaluate(releasesJSON: Data("[]".utf8), current: "garbage", channel: .stable))
    }

    func testSignedManifest() throws {
        let m = fixture.manifest
        let data = try Data(contentsOf: directory.appendingPathComponent(m.file))
        let signature = Data(base64Encoded: m.signatureBase64)!
        let key = Data(base64Encoded: m.publicKeyBase64)!
        let other = Data(base64Encoded: m.otherPublicKeyBase64)!
        func verify(_ data: Data, _ signature: Data, _ keys: [Data], channel: UpdateChannel = .preview, current: String = "0.2.0")
            -> Result<UpdateManifest, UpdateManifest.Failure> {
            UpdateManifest.verified(manifest: data, signatureDER: signature, trustedKeys: keys, channel: channel, current: current)
        }

        let manifest = try verify(data, signature, [other, key]).get()
        XCTAssertEqual(manifest.version, m.version)

        // No trusted key, a different key, a changed byte, a damaged signature: all refused.
        XCTAssertEqual(verify(data, signature, []), .failure(.noTrustedKey))
        XCTAssertEqual(verify(data, signature, [other]), .failure(.badSignature))
        var tampered = data
        tampered[tampered.count / 2] ^= 0x01
        XCTAssertEqual(verify(tampered, signature, [key]), .failure(.badSignature))
        var damaged = signature
        damaged[damaged.count - 1] ^= 0x01
        XCTAssertEqual(verify(data, damaged, [key]), .failure(.badSignature))
        XCTAssertEqual(verify(data, Data(), [key]), .failure(.badSignature))
        // Correctly signed, but for another channel or not newer.
        XCTAssertEqual(verify(data, signature, [key], channel: .stable), .failure(.wrongChannel))
        XCTAssertEqual(verify(data, signature, [key], current: "10.0.0"), .failure(.notNewer))

        let package = try manifest.package(platform: "macos", arch: "arm64", osVersion: "14.2").get()
        XCTAssertTrue(package.url.hasPrefix(UpdateCheck.officialReleasePrefix + "download/"))
        XCTAssertEqual(manifest.package(platform: "macos", arch: "arm64", osVersion: "12.6"), .failure(.noPackageForThisSystem))
        XCTAssertEqual(manifest.package(platform: "linux", arch: "x64", osVersion: "6.0"), .failure(.noPackageForThisSystem))
        XCTAssertEqual(try manifest.package(platform: "windows", arch: "x64", osVersion: "10.0.26200").get().platform, "windows")

        XCTAssertTrue(UpdateManifest.matches(package, fileData: Data(m.packageBytesUtf8.utf8)))
        XCTAssertFalse(UpdateManifest.matches(package, fileData: Data("abd".utf8)))
        XCTAssertFalse(UpdateManifest.matches(package, fileData: Data("abcd".utf8)))
    }

    func testNoUpdateKeyIsTrustedYet() {
        // Until a real update signing key exists, nothing can be installed automatically.
        XCTAssertTrue(UpdateManifest.trustedKeys.isEmpty)
        XCTAssertFalse(UpdateManifest.automaticInstallationPossible)
    }
}
