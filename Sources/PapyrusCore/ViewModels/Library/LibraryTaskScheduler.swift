import Foundation

enum LibraryTaskKind: Hashable {
    case importPDF
    case refreshMetadata
}

actor LibraryTaskScheduler {
    private let limits: [LibraryTaskKind: Int]
    private var activeCounts: [LibraryTaskKind: Int] = [:]
    private var waiters: [LibraryTaskKind: [CheckedContinuation<Void, Never>]] = [:]

    init(limits: [LibraryTaskKind: Int]) {
        self.limits = limits
    }

    func run(
        kind: LibraryTaskKind,
        operation: @escaping @MainActor () async -> Void
    ) async {
        await acquire(kind: kind)
        defer { release(kind: kind) }
        await operation()
    }

    func runWithResult<T>(
        kind: LibraryTaskKind,
        operation: @escaping @MainActor () async throws -> T
    ) async rethrows -> T {
        await acquire(kind: kind)
        defer { release(kind: kind) }
        return try await operation()
    }

    private func acquire(kind: LibraryTaskKind) async {
        let limit = max(1, limits[kind] ?? 1)
        let active = activeCounts[kind, default: 0]
        if active < limit {
            activeCounts[kind] = active + 1
            return
        }

        await withCheckedContinuation { continuation in
            var queue = waiters[kind, default: []]
            queue.append(continuation)
            waiters[kind] = queue
        }
    }

    private func release(kind: LibraryTaskKind) {
        var queue = waiters[kind, default: []]
        if !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[kind] = queue
            next.resume()
            return
        }

        let current = activeCounts[kind, default: 0]
        activeCounts[kind] = max(0, current - 1)
    }
}
