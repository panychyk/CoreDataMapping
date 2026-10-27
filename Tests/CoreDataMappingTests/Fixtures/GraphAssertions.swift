import CoreData
import CoreDataMapping
import Testing

@MainActor
enum GraphAssertions {
    static func matches(_ inputs: [RootSnapshot], in stack: CoreDataTestStack, resourceCount: Int = 3) throws {
        stack.viewContext.reset()
        let context = stack.viewContext
        let documents = try fetch(Document.self, in: context)
        let folders = try fetch(Folder.self, in: context)
        let dashboards = try fetch(Dashboard.self, in: context)
        let boards = try fetch(Board.self, in: context)
        let workspaces = try fetch(Workspace.self, in: context)
        let resources = try fetch(Resource.self, in: context)
        let sections = try fetch(Section.self, in: context)
        let entries = try fetch(Entry.self, in: context)

        let groups: [[any SectionContainer]] = [documents, folders, dashboards, boards, workspaces]
        for kind in RootKind.allCases {
            let expected = inputs.filter { $0.kind == kind }
            let roots = groups[kind.rawValue]
            #expect(roots.count == expected.count)
            #expect(Set(roots.map(\.id)).count == expected.count)
            let byID = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
            for snapshot in expected {
                let root = try #require(byID[snapshot.id])
                #expect(root.title == snapshot.title)
                let storedSections = try CoreDataStorage.ordered(root.sections, as: Section.self)
                #expect(storedSections.map(\.localID) == snapshot.sections.map(\.id))
                for (stored, wanted) in zip(storedSections, snapshot.sections) {
                    #expect(stored.title == wanted.title)
                    let storedEntries = try CoreDataStorage.ordered(stored.entries, as: Entry.self)
                    #expect(storedEntries.map(\.position) == wanted.entries.map(\.position))
                    #expect(storedEntries.map(\.text) == wanted.entries.map(\.text))
                }
                switch kind {
                case .document:
                    #expect((root as! Document).resources?.array.compactMap { ($0 as? Resource)?.id } == snapshot.resourceIDs)
                case .folder:
                    #expect(Set(((root as! Folder).resources?.allObjects as? [Resource] ?? []).map(\.id)) == Set(snapshot.resourceIDs))
                case .dashboard:
                    #expect((root as! Dashboard).featuredResource?.id == snapshot.resourceIDs.first)
                case .board:
                    #expect((root as! Board).resources?.array.compactMap { ($0 as? Resource)?.id } == snapshot.resourceIDs)
                case .workspace:
                    #expect(Set(((root as! Workspace).resources?.allObjects as? [Resource] ?? []).map(\.id)) == Set(snapshot.resourceIDs))
                }
            }
        }

        #expect(resources.count == resourceCount)
        #expect(Set(resources.map(\.id)).count == resourceCount)
        #expect(resources.allSatisfy { $0.label == "resource-\($0.id)" })
        #expect(sections.count == inputs.reduce(0) { $0 + $1.sections.count })
        #expect(entries.count == inputs.reduce(0) { $0 + $1.sections.reduce(0) { $0 + $1.entries.count } })
        #expect(sections.allSatisfy {
            [$0.document != nil, $0.folder != nil, $0.dashboard != nil,
             $0.board != nil, $0.workspace != nil].filter { $0 }.count == 1
        })
        #expect(entries.allSatisfy { $0.section != nil })
    }

    private static func fetch<Entity: NSManagedObject>(_ type: Entity.Type, in context: NSManagedObjectContext) throws -> [Entity] {
        try context.fetch(NSFetchRequest<Entity>(entityName: String(describing: type)))
    }
}
