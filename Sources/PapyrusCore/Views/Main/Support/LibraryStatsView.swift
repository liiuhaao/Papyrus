import SwiftUI

@MainActor
final class LibraryStatsModel: ObservableObject {
    @Published var total = 0
    @Published var unread = 0
    @Published var reading = 0
    @Published var read = 0
    @Published var storage = "—"

    private var observers: [Any] = []
    private var scheduledRefreshTask: Task<Void, Never>?

    init() {
        refresh()
        let nc = NotificationCenter.default
        observers.append(
            nc.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: PersistenceController.shared.container.viewContext,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefresh()
                }
            }
        )
        observers.append(
            nc.addObserver(forName: .libraryDidSwitch, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefresh()
                }
            }
        )
    }

    deinit {
        scheduledRefreshTask?.cancel()
        let nc = NotificationCenter.default
        for observer in observers {
            nc.removeObserver(observer)
        }
    }

    func refresh() {
        let ctx = PersistenceController.shared.container.viewContext
        guard let papers = try? ctx.fetch(NSFetchRequest<Paper>(entityName: "Paper")) else { return }

        let nextTotal = papers.count
        let nextUnread = papers.filter { $0.currentReadingStatus == .unread }.count
        let nextReading = papers.filter { $0.currentReadingStatus == .reading }.count
        let nextRead = papers.filter { $0.currentReadingStatus == .read }.count

        let bytes: Int64 = papers.compactMap { paper -> Int64? in
            guard let path = paper.filePath else { return nil }
            return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64)
        }
        .reduce(0, +)

        let nextStorage = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)

        if total != nextTotal {
            total = nextTotal
        }
        if unread != nextUnread {
            unread = nextUnread
        }
        if reading != nextReading {
            reading = nextReading
        }
        if read != nextRead {
            read = nextRead
        }
        if storage != nextStorage {
            storage = nextStorage
        }
    }

    private func scheduleRefresh(delayNanoseconds: UInt64 = 250_000_000) {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

struct LibraryStatsView: View {
    @StateObject private var stats = LibraryStatsModel()

    var body: some View {
        HStack(spacing: 0) {
            statCard(value: "\(stats.total)", label: "Total", color: .primary)
            divider
            statCard(value: "\(stats.unread)", label: "Unread", color: AppStatusStyle.tint(for: .unread))
            divider
            statCard(value: "\(stats.reading)", label: "Reading", color: AppStatusStyle.tint(for: .reading))
            divider
            statCard(value: "\(stats.read)", label: "Read", color: AppStatusStyle.tint(for: .read))
            divider
            statCard(value: stats.storage, label: "Storage", color: .secondary)
        }
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.controlCornerRadius)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 6)
    }
}
