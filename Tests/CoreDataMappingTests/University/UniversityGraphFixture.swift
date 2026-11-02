struct UniversityGraph: Sendable {
    var faculties: [FacultyValue]
    var programs: [ProgramValue]
    var groups: [GroupValue]
    var students: [StudentValue]
    var teachers: [NamedValue]
    var rooms: [NamedValue]
    var courses: [CourseValue]
    var semesters: [SemesterValue]
    var offerings: [OfferingValue]
}

struct NamedValue: Sendable { var id: Int64; var name: String }
struct FacultyValue: Sendable { var id: Int64; var name: String }
struct ProgramValue: Sendable { var id: Int64; var name: String; var facultyID: Int64 }
struct GroupValue: Sendable { var id: Int64; var name: String; var programID: Int64 }
struct StudentValue: Sendable {
    var id: Int64; var name: String; var programID: Int64; var groupID: Int64
}
struct CourseValue: Sendable { var id: Int64; var title: String; var programID: Int64 }
struct SemesterValue: Sendable { var id: Int64; var label: String }
struct OfferingValue: Sendable {
    var id: Int64
    var courseID: Int64
    var semesterID: Int64
    var teacherID: Int64
    var roomID: Int64
    var status: String
    var assignments: [AssignmentValue]
    var enrollments: [EnrollmentValue]
}
struct AssignmentValue: Sendable { var localID: Int64; var title: String }
struct EnrollmentValue: Sendable {
    var localID: Int64
    var studentID: Int64
    var status: String
    var grades: [GradeValue]
}
struct GradeValue: Sendable { var localID: Int64; var assignmentID: Int64; var score: Int64 }

enum UniversityGraphFixture {
    static func university() -> UniversityGraph {
        .init(
            faculties: [.init(id: 1, name: "Engineering"), .init(id: 2, name: "Arts")],
            programs: [
                .init(id: 10, name: "Computer Science", facultyID: 1),
                .init(id: 11, name: "Design", facultyID: 2),
            ],
            groups: [
                .init(id: 20, name: "CS-A", programID: 10),
                .init(id: 21, name: "CS-B", programID: 10),
                .init(id: 22, name: "DS-A", programID: 11),
            ],
            students: [
                .init(id: 30, name: "Ada", programID: 10, groupID: 20),
                .init(id: 31, name: "Bohdan", programID: 10, groupID: 21),
                .init(id: 32, name: "Clara", programID: 11, groupID: 22),
            ],
            teachers: [.init(id: 40, name: "Professor Kim"), .init(id: 41, name: "Professor Li")],
            rooms: [.init(id: 50, name: "Lab A"), .init(id: 51, name: "Hall B")],
            courses: [
                .init(id: 60, title: "Algorithms", programID: 10),
                .init(id: 61, title: "Visual Systems", programID: 11),
            ],
            semesters: [.init(id: 70, label: "Autumn"), .init(id: 71, label: "Spring")],
            offerings: [
                .init(id: 100, courseID: 60, semesterID: 70, teacherID: 40, roomID: 50,
                      status: "open",
                      assignments: [.init(localID: 1, title: "Proof"), .init(localID: 2, title: "Project")],
                      enrollments: [
                        .init(localID: 1, studentID: 30, status: "active", grades: [
                            .init(localID: 1, assignmentID: 1, score: 85),
                            .init(localID: 2, assignmentID: 2, score: 91),
                        ]),
                        .init(localID: 2, studentID: 31, status: "active", grades: [
                            .init(localID: 1, assignmentID: 1, score: 78),
                        ]),
                      ]),
                .init(id: 101, courseID: 60, semesterID: 71, teacherID: 40, roomID: 51,
                      status: "planned",
                      assignments: [.init(localID: 1, title: "Proof revised")],
                      enrollments: [
                        .init(localID: 1, studentID: 30, status: "active", grades: [
                            .init(localID: 1, assignmentID: 1, score: 88),
                        ]),
                      ]),
                .init(id: 102, courseID: 61, semesterID: 70, teacherID: 41, roomID: 50,
                      status: "open",
                      assignments: [.init(localID: 1, title: "Portfolio")],
                      enrollments: [
                        .init(localID: 1, studentID: 30, status: "active", grades: []),
                        .init(localID: 2, studentID: 32, status: "active", grades: [
                            .init(localID: 1, assignmentID: 1, score: 94),
                        ]),
                      ]),
            ]
        )
    }
}
