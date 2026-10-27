import Foundation
import Testing

@MainActor
@Suite("Medical congress · cancellation rollback")
struct CancellationRollbackTests {
    @Test("Cancellation rolls back the active batch and retains the prior save")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = GraphCases.congress()
        try await stack.write(original)

        var changed = original
        changed.events[0].title = "This update must roll back"
        let importer = stack.importer
        let mapped = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await importer.write([changed]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                mapped.signal()
                release.wait()
            }
        }
        let entered = await Task.detached {
            waitForMapping(mapped)
        }.value
        #expect(entered)
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        try GraphAssertions.matches(original, in: stack)
    }
}

private func waitForMapping(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 5) == .success
}
