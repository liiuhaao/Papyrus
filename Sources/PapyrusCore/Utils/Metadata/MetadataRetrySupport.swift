import Foundation

enum MetadataRetrySupport {
    static func performRequest<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var delayNanoseconds: UInt64 = 250_000_000
        var lastError: Error = MetadataError.networkError

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, shouldRetry(error) else { throw error }
            }

            let jitter = UInt64.random(in: 0...120_000_000)
            try await Task.sleep(nanoseconds: delayNanoseconds + jitter)
            delayNanoseconds = min(delayNanoseconds * 2, 600_000_000)
        }

        throw lastError
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        if let metadataError = error as? MetadataError {
            return metadataError == .networkError
        }

        return false
    }
}
