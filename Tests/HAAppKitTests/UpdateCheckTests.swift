import Foundation
import Testing
@testable import HAAppKit

@Test("Versions read with or without v, and missing parts count as 0", arguments: [
    ("1.2.0", "1.2"), ("v1.2.0", "1.2"), ("1", "1.0"), ("V2.0.1-beta", "2.0.1"), ("0.1", "0.1"),
])
func versionReads(text: String, expected: String) {
    #expect(AppVersion(text)?.description == expected)
}

@Test("Text that isn't a version is refused", arguments: ["", "v", "1..2", "abc", "1.-2", "1.2.3.4.5"])
func versionRefused(text: String) {
    #expect(AppVersion(text) == nil)
}

@Test("Versions compare part by part, not as text")
func versionOrder() throws {
    let v = { (s: String) in AppVersion(s)! }
    #expect(v("1.10") > v("1.9"))
    #expect(v("2.0") > v("1.99.99"))
    #expect(v("1.2") == v("1.2.0"))
    #expect(!(v("1.2.0") < v("1.2")))
}

@Test("A GitHub URL or slug gives owner/name", arguments: [
    ("https://github.com/krekas/HAApp.git", "krekas/HAApp"),
    ("git@github.com:krekas/HAApp.git", "krekas/HAApp"),
    ("https://github.com/krekas/HAApp/", "krekas/HAApp"),
    ("krekas/ha-app", "krekas/ha-app"),
])
func repoReads(text: String, expected: String) {
    #expect(UpdateCheck.repo(text) == expected)
}

@Test("Anything else gives no repo", arguments: ["", "__REPO__", "https://gitlab.com/a/b", "a/b/c", "a/"])
func repoRefused(text: String) {
    #expect(UpdateCheck.repo(text) == nil)
}

private let latest = Data(#"{"tag_name":"v1.3.0","html_url":"https://github.com/o/n/releases/tag/v1.3.0","draft":false}"#.utf8)

@Test("A newer release is offered, the same or older one isn't")
func outcomes() {
    let page = URL(string: "https://github.com/o/n/releases/tag/v1.3.0")!
    #expect(UpdateCheck.outcome(current: AppVersion("1.2.0")!, status: 200, body: latest, repo: "o/n")
            == .available(Release(version: AppVersion("1.3")!, page: page)))
    #expect(UpdateCheck.outcome(current: AppVersion("1.3")!, status: 200, body: latest, repo: "o/n")
            == .upToDate(AppVersion("1.3")!))
    #expect(UpdateCheck.outcome(current: AppVersion("2.0")!, status: 200, body: latest, repo: "o/n")
            == .upToDate(AppVersion("2.0")!))
}

@Test("No releases, a private repo, and rate limits say what happened")
func failures() {
    let current = AppVersion("1.0")!
    guard case .failed(let missing) = UpdateCheck.outcome(current: current, status: 404, body: Data(), repo: "o/n"),
          case .failed(let limited) = UpdateCheck.outcome(current: current, status: 403, body: Data(), repo: "o/n"),
          case .failed(let unreadable) = UpdateCheck.outcome(current: current, status: 200, body: Data("{}".utf8), repo: "o/n")
    else { Issue.record("expected failures"); return }
    #expect(missing.contains("github.com/o/n"))
    #expect(limited.contains("wait"))
    #expect(unreadable.contains("version"))
}

@Test("An automatic check runs once a day")
func due() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
    #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
    #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now)) // clock moved back
}
