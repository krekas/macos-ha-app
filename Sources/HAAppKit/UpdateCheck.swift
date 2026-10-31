import Foundation

/// A release version like `1.2.0`. Reads `v1.2`, `1.2.0`, and `1.2.0-beta`
/// (the suffix is ignored). Missing parts count as 0, so `1.2` equals `1.2.0`.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4, numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        var parts = numbers.compactMap { $0 }
        while parts.count > 1 && parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    public var description: String { parts.count == 1 ? "\(parts[0]).0" : parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

/// A published GitHub Release: its version and the page to download it from.
public struct Release: Equatable, Sendable {
    public let version: AppVersion
    public let page: URL

    public init(version: AppVersion, page: URL) {
        self.version = version
        self.page = page
    }

    /// Reads the JSON of `GET /repos/<owner>/<name>/releases/latest`.
    public static func decode(_ data: Data) -> Release? {
        struct JSON: Decodable { let tag_name: String; let html_url: URL }
        guard let json = try? JSONDecoder().decode(JSON.self, from: data),
              let version = AppVersion(json.tag_name)
        else { return nil }
        return Release(version: version, page: json.html_url)
    }
}

/// Asks GitHub for the latest release of HAApp and compares it with the running version.
public enum UpdateCheck {
    public enum Outcome: Equatable, Sendable {
        case available(Release)
        case upToDate(AppVersion)
        case failed(String)
    }

    /// `owner/name`, from a GitHub URL or the slug itself: `https://github.com/o/n.git`,
    /// `git@github.com:o/n.git`, or `o/n`. Nil for anything else, including an empty string.
    public static func repo(_ text: String) -> String? {
        var slug = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/"] where slug.hasPrefix(prefix) {
            slug.removeFirst(prefix.count)
        }
        if slug.hasSuffix(".git") { slug.removeLast(4) }
        while slug.hasSuffix("/") { slug.removeLast() }
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return slug
    }

    public static func latestURL(repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    public static func releasesPage(repo: String) -> URL {
        URL(string: "https://github.com/\(repo)/releases")!
    }

    /// What a GitHub reply means for someone running `current`.
    public static func outcome(current: AppVersion, status: Int, body: Data, repo: String) -> Outcome {
        switch status {
        case 200:
            guard let release = Release.decode(body) else {
                return .failed("The latest release on GitHub has no version number HAApp can read.")
            }
            return release.version > current ? .available(release) : .upToDate(current)
        case 404:
            // Also what a private repo answers without a login.
            return .failed("There are no published releases at github.com/\(repo), or the repository is private.")
        case 403, 429:
            return .failed("GitHub asked HAApp to wait before checking again. Try again in an hour.")
        default:
            return .failed("GitHub answered with an error (\(status)). Try again later.")
        }
    }

    public static func check(current: AppVersion, repo: String, session: URLSession = .shared) async -> Outcome {
        var request = URLRequest(url: latestURL(repo: repo), timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return outcome(current: current, status: status, body: data, repo: repo)
        } catch {
            return .failed("Can't reach GitHub. Check your internet connection.")
        }
    }

    /// An automatic check runs at most once a day.
    public static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= 24 * 60 * 60 || now < lastCheck
    }
}
