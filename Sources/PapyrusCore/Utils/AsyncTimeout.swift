import Foundation

enum AsyncTimeout {
    static func value<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        let timeoutNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)

        return await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                if timeoutNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    static func run(
        seconds: Double,
        operation: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await value(seconds: seconds) {
            await operation()
            return true
        } ?? false
    }
}
