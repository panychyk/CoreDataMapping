import CoreData

@objc(Section)
final class Section: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var title: String?
    @NSManaged var document: Document?
    @NSManaged var folder: Folder?
    @NSManaged var dashboard: Dashboard?
    @NSManaged var board: Board?
    @NSManaged var workspace: Workspace?
    @NSManaged var entries: NSOrderedSet?
}
