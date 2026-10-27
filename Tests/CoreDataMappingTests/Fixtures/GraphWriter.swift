import CoreData
import CoreDataMapping

protocol SectionContainer: AnyObject {
    var id: Int64 { get set }
    var title: String? { get set }
    var sections: NSOrderedSet? { get set }
}

extension Document: SectionContainer {}
extension Folder: SectionContainer {}
extension Dashboard: SectionContainer {}
extension Board: SectionContainer {}
extension Workspace: SectionContainer {}

nonisolated enum RootKind: Int, CaseIterable, Sendable {
    case document, folder, dashboard, board, workspace
}

nonisolated struct EntrySnapshot: Sendable {
    let position: Int64
    let text: String
}

nonisolated struct SectionSnapshot: Sendable {
    let id: Int64
    let title: String
    let entries: [EntrySnapshot]
}

nonisolated struct RootSnapshot: Sendable {
    let kind: RootKind
    let id: Int64
    let title: String
    let resourceIDs: [Int64]
    let sections: [SectionSnapshot]
}

nonisolated enum GraphCases {
    static func root(_ kind: RootKind, id: Int64, revision: Int = 0) -> RootSnapshot {
        RootSnapshot(
            kind: kind, id: id, title: "\(kind)-\(id)-v\(revision)",
            resourceIDs: [3, 1, 2],
            sections: (1...3).map { section in
                SectionSnapshot(
                    id: Int64(section), title: "\(kind)-\(id)-\(section)-v\(revision)",
                    entries: (1...2).map { entry in
                        EntrySnapshot(position: Int64(entry), text: "\(id)-\(section)-\(entry)-v\(revision)")
                    }
                )
            }
        )
    }

    static func roots(perKind: Int) -> [RootSnapshot] {
        RootKind.allCases.flatMap { kind in
            (1...perKind).map { root(kind, id: Int64($0)) }
        }
    }
}

nonisolated enum GraphWriter {
    // Rule: prepare every global identity in the batch before connecting any
    // relationship. Section IDs belong to one root; resources outlive links.
    static func write(_ inputs: [RootSnapshot], using storage: CoreDataStorage) throws {
        let resources = try storage.upsert(
            ids: inputs.flatMap(\.resourceIDs), identifiedBy: Resource.identity
        )
        for (id, resource) in resources { resource.label = "resource-\(id)" }
        let documents = try storage.upsert(ids: ids(.document, in: inputs), identifiedBy: Document.identity,
                                           prefetching: ["sections", "sections.entries"])
        let folders = try storage.upsert(ids: ids(.folder, in: inputs), identifiedBy: Folder.identity,
                                         prefetching: ["sections", "sections.entries"])
        let dashboards = try storage.upsert(ids: ids(.dashboard, in: inputs), identifiedBy: Dashboard.identity,
                                            prefetching: ["sections", "sections.entries"])
        let boards = try storage.upsert(ids: ids(.board, in: inputs), identifiedBy: Board.identity,
                                        prefetching: ["sections", "sections.entries"])
        let workspaces = try storage.upsert(ids: ids(.workspace, in: inputs), identifiedBy: Workspace.identity,
                                            prefetching: ["sections", "sections.entries"])

        for input in inputs {
            let root: any SectionContainer
            switch input.kind {
            case .document: root = documents[input.id]!
            case .folder: root = folders[input.id]!
            case .dashboard: root = dashboards[input.id]!
            case .board: root = boards[input.id]!
            case .workspace: root = workspaces[input.id]!
            }
            root.title = input.title
            let linkedResources = input.resourceIDs.map { resources[$0]! }
            switch input.kind {
            case .document: (root as! Document).resources = try storage.replace(with: linkedResources)
            case .folder: (root as! Folder).resources = try NSSet(array: Array(storage.replaceUnordered(with: linkedResources)))
            case .dashboard: (root as! Dashboard).featuredResource = linkedResources.first
            case .board: (root as! Board).resources = try storage.replace(with: linkedResources)
            case .workspace: (root as! Workspace).resources = try NSSet(array: Array(storage.replaceUnordered(with: linkedResources)))
            }
            let sections = try storage.reconcileOwned(
                input.sections,
                current: CoreDataStorage.ordered(root.sections, as: Section.self),
                dtoId: \SectionSnapshot.id, entityId: \Section.localID,
                create: { try storage.insert(Section.self) }
            ) { section, snapshot in
                section.localID = snapshot.id
                section.title = snapshot.title
                let entries = try storage.reconcileOwned(
                    snapshot.entries,
                    current: CoreDataStorage.ordered(section.entries, as: Entry.self),
                    dtoId: \EntrySnapshot.position, entityId: \Entry.position,
                    create: { try storage.insert(Entry.self) }
                ) { entry, snapshot in
                    entry.position = snapshot.position
                    entry.text = snapshot.text
                }
                section.entries = try storage.replace(with: entries)
            }
            root.sections = try storage.replace(with: sections)
        }
    }

    private static func ids(_ kind: RootKind, in inputs: [RootSnapshot]) -> [Int64] {
        inputs.filter { $0.kind == kind }.map(\.id)
    }
}
