import Combine
import Testing
@testable import PapyrusCore

@MainActor
struct AppConfigObservationTests {
    @Test
    func publishesChangesWhenSettingsUpdate() async throws {
        let config = AppConfig()
        let nextAppearance: AppAppearance = config.appearance == .dark ? .light : .dark
        var changes = 0
        let cancellable = config.objectWillChange.sink { _ in
            changes += 1
        }

        try config.setAppearance(nextAppearance)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(config.appearance == nextAppearance)
        #expect(changes > 0)
        _ = cancellable
    }
}
