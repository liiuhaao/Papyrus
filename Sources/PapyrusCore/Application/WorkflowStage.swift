import Foundation

package enum WorkflowStage: Equatable {
    case checking
    case extracting
    case queued
    case fetching
    case saving
    case done
    case downloading
    case failed(String)

    package var label: String {
        switch self {
        case .checking: return "Checking duplicates..."
        case .extracting: return "Extracting metadata..."
        case .queued: return "Queued metadata..."
        case .fetching: return "Fetching from web..."
        case .saving: return "Saving..."
        case .done: return "Done"
        case .downloading: return "Downloading PDF..."
        case .failed(let message): return message
        }
    }

    package var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    package var isFinished: Bool {
        switch self {
        case .done, .failed:
            return true
        default:
            return false
        }
    }
}
