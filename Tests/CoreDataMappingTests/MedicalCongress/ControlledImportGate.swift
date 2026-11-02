import Foundation

/// Coordinates test writers at the point after graph mapping and before importer save.
/// Timeouts only fail a stalled test; signals determine the operation order.
final class ControlledImportGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let mapped = DispatchSemaphore(value: 0)
    private let releaseMapping = DispatchSemaphore(value: 0)

    enum GateError: Error {
        case timedOut
    }

    func signalStarted() {
        started.signal()
    }

    func waitUntilStarted() async throws {
        let didStart = await Task.detached { [started] in
            Self.waitForSignal(started)
        }.value
        guard didStart else { throw GateError.timedOut }
    }

    func pauseAfterMapping() throws {
        mapped.signal()
        guard releaseMapping.wait(timeout: .now() + 30) == .success else {
            throw GateError.timedOut
        }
    }

    func waitUntilMapped() async throws {
        let didMap = await Task.detached { [mapped] in
            Self.waitForSignal(mapped)
        }.value
        guard didMap else { throw GateError.timedOut }
    }

    func release() {
        releaseMapping.signal()
    }

    private static func waitForSignal(_ signal: DispatchSemaphore) -> Bool {
        signal.wait(timeout: .now() + 30) == .success
    }
}
