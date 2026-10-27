nonisolated protocol ProgramRepository: Sendable {
    func getTracks() async throws -> [Track]
    func getSchedule() async throws -> [ScheduleEvent]
    func getElectives() async throws -> [Elective]
}
