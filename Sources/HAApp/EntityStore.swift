import Foundation
import Observation
import HAAppKit

/// The saved list of Home Assistant entities (Settings > Entities). A scan
/// replaces it; a failed scan keeps the last one. Saved as JSON next to the
/// database, so it is there at launch without asking the server.
@Observable
final class EntityStore {
    private(set) var catalog: EntityCatalog?
    private(set) var isScanning = false
    /// Why the last scan failed, until the next one succeeds.
    private(set) var scanError: String?

    /// How the Entities page groups the list. Remembered outside test runs.
    var grouping: EntityGrouping = EntityGrouping(rawValue: UserDefaults.standard.string(forKey: "entities.grouping") ?? "") ?? .device {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(grouping.rawValue, forKey: "entities.grouping") } }
    }

    /// Open sections on the Entities page, per grouping, for this session.
    private var expanded: [EntityGrouping: Set<String>] = [:]
    /// The sections the Entities page shows now, for Expand All.
    var visibleSections: [String] = []

    func isExpanded(_ section: String) -> Bool {
        expanded[grouping, default: []].contains(section)
    }

    func setExpanded(_ section: String, _ open: Bool) {
        if open { expanded[grouping, default: []].insert(section) } else { expanded[grouping]?.remove(section) }
    }

    func expandAll() { expanded[grouping] = Set(visibleSections) }
    func collapseAll() { expanded[grouping] = [] }

    let url: URL

    init(url: URL) {
        self.url = url
        catalog = EntityCatalog.load(from: url)
    }

    /// True when there's no list yet, or it came from another server.
    func needsScan(for server: ServerURL) -> Bool {
        catalog?.server != server.description
    }

    func scan(server: ServerURL, token: String) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let fresh = try await EntityScan.run(server: server, token: token)
            replace(with: fresh)
        } catch {
            scanError = error.message(server: server)
        }
    }

    /// Saves a new list and clears the last error. Seed data and the self-test use it too.
    func replace(with fresh: EntityCatalog) {
        catalog = fresh
        scanError = nil
        try? fresh.save(to: url)
    }
}
