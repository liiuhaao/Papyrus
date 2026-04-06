import Foundation

enum TagNamespaceSupport {
    static let fallbackNamespaces = ["proj", "topic", "method", "task"]

    static func normalizedNamespaces(_ rawValues: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in rawValues {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, isValidNamespace(trimmed), !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }

        return ordered
    }

    static func parseText(_ text: String) -> [String] {
        normalizedNamespaces(
            text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        )
    }

    static func formatText(_ namespaces: [String]) -> String {
        normalizedNamespaces(namespaces).joined(separator: ", ")
    }

    static func namespace(for tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = trimmed.firstIndex(of: ":"),
              colonIndex > trimmed.startIndex else { return nil }

        let prefix = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, isValidNamespace(String(prefix)) else { return nil }
        return prefix.lowercased()
    }

    static func namespaces(in tags: [String]) -> [String] {
        let seen = Set(tags.compactMap(namespace(for:)))
        let configured = configuredNamespaces()
        let orderedDefaults = configured.filter(seen.contains)
        let custom = seen.subtracting(configured).sorted()
        return orderedDefaults + custom
    }

    static func sortTags(_ tags: [String]) -> [String] {
        tags.sorted { lhs, rhs in
            let lhsNamespace = namespace(for: lhs)
            let rhsNamespace = namespace(for: rhs)

            if lhsNamespace != rhsNamespace {
                switch (lhsNamespace, rhsNamespace) {
                case let (left?, right?):
                    let namespaces = namespaces(in: [lhs, rhs])
                    let leftIndex = namespaces.firstIndex(of: left) ?? Int.max
                    let rightIndex = namespaces.firstIndex(of: right) ?? Int.max
                    if leftIndex != rightIndex { return leftIndex < rightIndex }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }

            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static func groupedTagCounts(_ items: [(tag: String, count: Int)]) -> [TagNamespaceGroup] {
        let namespaces = namespaces(in: items.map(\.tag))
        var groups: [TagNamespaceGroup] = []

        for namespace in namespaces {
            let matches = items
                .filter { self.namespace(for: $0.tag) == namespace }
                .sorted(by: tagCountComparator)
                .map { ($0.tag, $0.count) }
            if !matches.isEmpty {
                groups.append(
                    TagNamespaceGroup(namespace: namespace, label: namespace.uppercased(), items: matches)
                )
            }
        }

        let other = items
            .filter { namespace(for: $0.tag) == nil }
            .sorted(by: tagCountComparator)
            .map { ($0.tag, $0.count) }
        if !other.isEmpty {
            groups.append(TagNamespaceGroup(namespace: nil, label: "OTHER", items: other))
        }

        return groups
    }

    static func namespaceChips(from tags: [String]) -> [String] {
        let observed = namespaces(in: tags)
        let all = Array(NSOrderedSet(array: observed + configuredNamespaces())) as? [String] ?? fallbackNamespaces
        return all.map { "\($0):" }
    }

    static func applyingNamespaceChip(_ chip: String, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix(chip) else { return trimmed }
        if trimmed.isEmpty { return chip }
        return chip + trimmed
    }

    private static func tagCountComparator(_ lhs: (tag: String, count: Int), _ rhs: (tag: String, count: Int)) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.tag.localizedCaseInsensitiveCompare(rhs.tag) == .orderedAscending
    }

    private static func configuredNamespaces() -> [String] {
        normalizedNamespaces(TagNamespaceConfig.configuredNamespaces)
    }

    private static func isValidNamespace(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

struct TagNamespaceGroup: Identifiable {
    let namespace: String?
    let label: String
    let items: [(String, Int)]

    var id: String { namespace ?? "__other__" }
}
