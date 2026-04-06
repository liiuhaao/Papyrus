import Foundation

enum PaperWorkflowPhase: String, CaseIterable {
    case idle
    case queued
    case running
    case done
    case failed
    case skipped

    var isVisible: Bool {
        self != .idle
    }

    var isInFlight: Bool {
        self == .queued || self == .running
    }
}

struct PaperWorkflowStatus: Equatable {
    var fetch: PaperWorkflowPhase

    init(fetch: PaperWorkflowPhase = .idle) {
        self.fetch = fetch
    }

    init?(encoded: String?) {
        guard let encoded,
              !encoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var fetch: PaperWorkflowPhase = .idle

        for token in encoded.split(separator: ";") {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "fetch":
                if let phase = PaperWorkflowPhase(rawValue: parts[1]) {
                    fetch = phase
                }
            default:
                continue
            }
        }

        self.init(fetch: fetch)
    }

    var encoded: String {
        "fetch=\(fetch.rawValue)"
    }

    var hasVisiblePhases: Bool {
        fetch.isVisible
    }

    var hasPersistedPhases: Bool {
        fetch != .idle
    }

    var hasInFlightPhases: Bool {
        fetch.isInFlight
    }

    var shouldAutoClear: Bool {
        hasPersistedPhases && !hasInFlightPhases
    }
}

extension Paper {
    var workflowStatus: PaperWorkflowStatus? {
        get { PaperWorkflowStatus(encoded: enrichStatus) }
        set { enrichStatus = newValue?.hasPersistedPhases == true ? newValue?.encoded : nil }
    }
}
