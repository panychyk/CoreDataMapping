import CoreData
import CoreDataMapping
import Testing

@MainActor
enum UniversityGraphAssertions {
    static func offering(_ id: Int64, in stack: UniversityTestStack) throws -> UniOffering {
        try #require(stack.fetch(UniOffering.self).first { $0.id == id })
    }

    static func matches(_ graph: UniversityGraph, in stack: UniversityTestStack) throws {
        stack.resetViewContext()
        let faculties = try stack.fetch(UniFaculty.self)
        let programs = try stack.fetch(UniProgram.self)
        let groups = try stack.fetch(UniGroup.self)
        let students = try stack.fetch(UniStudent.self)
        let teachers = try stack.fetch(UniTeacher.self)
        let rooms = try stack.fetch(UniRoom.self)
        let courses = try stack.fetch(UniCourse.self)
        let semesters = try stack.fetch(UniSemester.self)
        let offerings = try stack.fetch(UniOffering.self)
        #expect(faculties.count == graph.faculties.count)
        #expect(programs.count == graph.programs.count)
        #expect(groups.count == graph.groups.count)
        #expect(students.count == graph.students.count)
        #expect(teachers.count == graph.teachers.count)
        #expect(rooms.count == graph.rooms.count)
        #expect(courses.count == graph.courses.count)
        #expect(semesters.count == graph.semesters.count)
        #expect(offerings.count == graph.offerings.count)
        for value in graph.faculties {
            #expect(faculties.first { $0.id == value.id }?.name == value.name)
        }
        for value in graph.programs {
            let object = try #require(programs.first { $0.id == value.id })
            #expect(object.name == value.name)
            #expect(object.faculty?.id == value.facultyID)
        }
        for value in graph.groups {
            let object = try #require(groups.first { $0.id == value.id })
            #expect(object.name == value.name)
            #expect(object.program?.id == value.programID)
        }
        for value in graph.students {
            let object = try #require(students.first { $0.id == value.id })
            #expect(object.name == value.name)
            #expect(object.program?.id == value.programID)
            #expect(object.group?.id == value.groupID)
        }
        for value in graph.teachers {
            #expect(teachers.first { $0.id == value.id }?.name == value.name)
        }
        for value in graph.rooms {
            #expect(rooms.first { $0.id == value.id }?.name == value.name)
        }
        for value in graph.courses {
            let object = try #require(courses.first { $0.id == value.id })
            #expect(object.title == value.title)
            #expect(object.program?.id == value.programID)
        }
        for value in graph.semesters {
            #expect(semesters.first { $0.id == value.id }?.label == value.label)
        }
        for value in graph.offerings {
            let object = try #require(offerings.first { $0.id == value.id })
            #expect(object.status == value.status)
            #expect(object.course?.id == value.courseID)
            #expect(object.semester?.id == value.semesterID)
            #expect(object.teacher?.id == value.teacherID)
            #expect(object.room?.id == value.roomID)
            let assignments = try CoreDataStorage.ordered(
                object.assignments, as: UniAssignment.self)
            #expect(assignments.map(\.localID) == value.assignments.map(\.localID))
            for (assignment, snapshot) in zip(assignments, value.assignments) {
                #expect(assignment.title == snapshot.title)
                #expect(assignment.offering === object)
            }
            let enrollments = try CoreDataStorage.ordered(
                object.enrollments, as: UniEnrollment.self)
            #expect(enrollments.map(\.localID) == value.enrollments.map(\.localID))
            for (enrollment, snapshot) in zip(enrollments, value.enrollments) {
                #expect(enrollment.offering === object)
                #expect(enrollment.student?.id == snapshot.studentID)
                #expect(enrollment.status == snapshot.status)
                let grades = enrollment.grades?.allObjects as? [UniGrade] ?? []
                #expect(grades.count == snapshot.grades.count)
                #expect(Set(grades.map(\.localID)) == Set(snapshot.grades.map(\.localID)))
                for grade in grades {
                    let wanted = try #require(snapshot.grades.first { $0.localID == grade.localID })
                    #expect(grade.enrollment === enrollment)
                    #expect(grade.assignment?.localID == wanted.assignmentID)
                    #expect(grade.assignment?.offering === object)
                    #expect(grade.score == wanted.score)
                }
            }
        }
        #expect(try stack.count(UniAssignment.self) == graph.offerings.reduce(0) { $0 + $1.assignments.count })
        #expect(try stack.count(UniEnrollment.self) == graph.offerings.reduce(0) { $0 + $1.enrollments.count })
        #expect(try stack.count(UniGrade.self) == graph.offerings.reduce(0) { total, offering in
            total + offering.enrollments.reduce(0) { $0 + $1.grades.count }
        })
        #expect(try stack.fetch(UniGrade.self).allSatisfy {
            $0.assignment?.offering === $0.enrollment?.offering
        })
    }
}
