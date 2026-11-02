import CoreData
import CoreDataMapping

enum UniversityFixtureError: Error, Equatable {
    case missingReference(entity: String, id: Int64)
    case duplicateStudent(offeringID: Int64, studentID: Int64)
    case duplicateGrade(enrollmentID: Int64, assignmentID: Int64)
}

enum UniversityGraphWriter {
    // All global identities are fetched before mapping relationships. An offering
    // owns its assignments and enrollments; an enrollment owns its grades.
    static func write(_ graphs: [UniversityGraph], using storage: CoreDataStorage) throws {
        let faculties = try storage.upsert(
            ids: graphs.flatMap { $0.faculties.map(\.id) }, identifiedBy: UniFaculty.identity)
        let programs = try storage.upsert(
            ids: graphs.flatMap { $0.programs.map(\.id) }, identifiedBy: UniProgram.identity)
        let groups = try storage.upsert(
            ids: graphs.flatMap { $0.groups.map(\.id) }, identifiedBy: UniGroup.identity)
        let students = try storage.upsert(
            ids: graphs.flatMap { $0.students.map(\.id) }, identifiedBy: UniStudent.identity)
        let teachers = try storage.upsert(
            ids: graphs.flatMap { $0.teachers.map(\.id) }, identifiedBy: UniTeacher.identity)
        let rooms = try storage.upsert(
            ids: graphs.flatMap { $0.rooms.map(\.id) }, identifiedBy: UniRoom.identity)
        let courses = try storage.upsert(
            ids: graphs.flatMap { $0.courses.map(\.id) }, identifiedBy: UniCourse.identity)
        let semesters = try storage.upsert(
            ids: graphs.flatMap { $0.semesters.map(\.id) }, identifiedBy: UniSemester.identity)
        let offerings = try storage.upsert(
            ids: graphs.flatMap { $0.offerings.map(\.id) },
            identifiedBy: UniOffering.identity,
            prefetching: ["assignments", "enrollments", "enrollments.grades"])

        for graph in graphs {
            for value in graph.faculties {
                try required(faculties, id: value.id, entity: "UniFaculty").name = value.name
            }
            for value in graph.programs {
                let program = try required(programs, id: value.id, entity: "UniProgram")
                program.name = value.name
                program.faculty = try required(faculties, id: value.facultyID, entity: "UniFaculty")
            }
            for value in graph.groups {
                let group = try required(groups, id: value.id, entity: "UniGroup")
                group.name = value.name
                group.program = try required(programs, id: value.programID, entity: "UniProgram")
            }
            for value in graph.students {
                let student = try required(students, id: value.id, entity: "UniStudent")
                student.name = value.name
                student.program = try required(programs, id: value.programID, entity: "UniProgram")
                student.group = try required(groups, id: value.groupID, entity: "UniGroup")
            }
            for value in graph.teachers {
                try required(teachers, id: value.id, entity: "UniTeacher").name = value.name
            }
            for value in graph.rooms {
                try required(rooms, id: value.id, entity: "UniRoom").name = value.name
            }
            for value in graph.courses {
                let course = try required(courses, id: value.id, entity: "UniCourse")
                course.title = value.title
                course.program = try required(programs, id: value.programID, entity: "UniProgram")
            }
            for value in graph.semesters {
                try required(semesters, id: value.id, entity: "UniSemester").label = value.label
            }
            for value in graph.offerings {
                let offering = try required(offerings, id: value.id, entity: "UniOffering")
                offering.status = value.status
                offering.course = try required(courses, id: value.courseID, entity: "UniCourse")
                offering.semester = try required(semesters, id: value.semesterID, entity: "UniSemester")
                offering.teacher = try required(teachers, id: value.teacherID, entity: "UniTeacher")
                offering.room = try required(rooms, id: value.roomID, entity: "UniRoom")
                try write(value, to: offering, students: students, using: storage)
            }
        }
    }

    private static func write(
        _ value: OfferingValue, to offering: UniOffering,
        students: [Int64: UniStudent], using storage: CoreDataStorage
    ) throws {
        let assignments = try storage.reconcileOwned(
            value.assignments,
            current: try CoreDataStorage.ordered(offering.assignments, as: UniAssignment.self),
            dtoId: \AssignmentValue.localID, entityId: \UniAssignment.localID,
            create: { try storage.insert(UniAssignment.self) }
        ) { assignment, snapshot in
            assignment.localID = snapshot.localID
            assignment.title = snapshot.title
        }
        offering.assignments = try storage.replace(with: assignments)
        let assignmentsByID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.localID, $0) })

        var studentIDs: Set<Int64> = []
        for enrollment in value.enrollments {
            guard studentIDs.insert(enrollment.studentID).inserted else {
                throw UniversityFixtureError.duplicateStudent(
                    offeringID: value.id, studentID: enrollment.studentID)
            }
        }
        let enrollments = try storage.reconcileOwned(
            value.enrollments,
            current: try CoreDataStorage.ordered(offering.enrollments, as: UniEnrollment.self),
            dtoId: \EnrollmentValue.localID, entityId: \UniEnrollment.localID,
            create: { try storage.insert(UniEnrollment.self) }
        ) { enrollment, snapshot in
            enrollment.localID = snapshot.localID
            enrollment.status = snapshot.status
            enrollment.student = try required(
                students, id: snapshot.studentID, entity: "UniStudent")
            var assignmentIDs: Set<Int64> = []
            for grade in snapshot.grades {
                guard assignmentIDs.insert(grade.assignmentID).inserted else {
                    throw UniversityFixtureError.duplicateGrade(
                        enrollmentID: snapshot.localID, assignmentID: grade.assignmentID)
                }
            }
            let grades = try storage.reconcileOwned(
                snapshot.grades, current: try objects(enrollment.grades),
                dtoId: \GradeValue.localID, entityId: \UniGrade.localID,
                create: { try storage.insert(UniGrade.self) }
            ) { grade, gradeValue in
                grade.localID = gradeValue.localID
                grade.score = gradeValue.score
                grade.assignment = try required(
                    assignmentsByID, id: gradeValue.assignmentID, entity: "UniAssignment")
            }
            enrollment.grades = NSSet(array: grades)
        }
        offering.enrollments = try storage.replace(with: enrollments)
    }

    private static func objects<Entity: NSManagedObject>(_ set: NSSet?) throws -> [Entity] {
        guard let set else { return [] }
        guard let values = set.allObjects as? [Entity] else {
            throw CoreDataStorageError.unexpectedRelationshipEntityType(
                expectedType: String(describing: Entity.self))
        }
        return values
    }

    private static func required<Value>(
        _ values: [Int64: Value], id: Int64, entity: String
    ) throws -> Value {
        guard let value = values[id] else {
            throw UniversityFixtureError.missingReference(entity: entity, id: id)
        }
        return value
    }
}
