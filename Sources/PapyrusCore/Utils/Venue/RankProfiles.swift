import Foundation

enum RankProfiles {
    struct Resolved {
        let key: String
        let value: String
        let rank: Int?
    }

    typealias Resolver = (String) -> Resolved?

    private static let orderedProfiles: [(String, Resolver)] = [
        ("ccf", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A", "T1": rank = 1
            case "B", "T2": rank = 2
            case "C", "T3": rank = 3
            default: rank = nil
            }
            return Resolved(key: "CCF", value: value, rank: rank)
        }),
        ("sci", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "Q1": rank = 1
            case "Q2": rank = 2
            case "Q3": rank = 3
            case "Q4": rank = 4
            default: rank = nil
            }
            return Resolved(key: "SCI", value: value, rank: rank)
        }),
        ("jcr", { raw in
            resolve(source: "sci", raw: raw)
        }),
        ("sciup", { raw in
            resolveZoneLike(key: "SCI升级版", raw: raw)
        }),
        ("scibase", { raw in
            resolveZoneLike(key: "SCI基础版", raw: raw)
        }),
        ("ssci", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "Q1": rank = 1
            case "Q2": rank = 2
            case "Q3": rank = 3
            case "Q4": rank = 4
            case "SSCI": rank = 5
            default: rank = nil
            }
            return Resolved(key: "SSCI", value: value, rank: rank)
        }),
        ("ahci", { _ in
            Resolved(key: "A&HCI 检索", value: "", rank: 2)
        }),
        ("eii", { _ in
            Resolved(key: "EI检索", value: "", rank: 2)
        }),
        ("sciif", { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Double(trimmed)
            let rank: Int?
            switch number {
            case let x? where x >= 10: rank = 1
            case let x? where x >= 4: rank = 2
            case let x? where x >= 2: rank = 3
            case let x? where x >= 1: rank = 4
            case let x? where x >= 0: rank = 5
            default: rank = nil
            }
            return Resolved(key: "SCIIF", value: trimmed, rank: rank)
        }),
        ("sciif5", { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Double(trimmed)
            let rank: Int?
            switch number {
            case let x? where x >= 10: rank = 1
            case let x? where x >= 4: rank = 2
            case let x? where x >= 2: rank = 3
            case let x? where x >= 1: rank = 4
            case let x? where x >= 0: rank = 5
            default: rank = nil
            }
            return Resolved(key: "SCIIF(5)", value: trimmed, rank: rank)
        }),
        ("jci", { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Double(trimmed)
            let rank: Int?
            switch number {
            case let x? where x >= 3: rank = 1
            case let x? where x >= 1: rank = 2
            case let x? where x >= 0.5: rank = 3
            case let x? where x >= 0: rank = 4
            default: rank = nil
            }
            return Resolved(key: "JCI", value: trimmed, rank: rank)
        }),
        ("cssci", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "CSSCI": rank = 1
            case "CSSCI扩展版": rank = 2
            default: rank = nil
            }
            return Resolved(key: value.isEmpty ? "CSSCI" : value, value: "", rank: rank)
        }),
        ("pku", { _ in
            Resolved(key: "北大中文核心", value: "", rank: 1)
        }),
        ("cscd", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "核心库": rank = 2
            case "扩展库": rank = 3
            default: rank = nil
            }
            return Resolved(key: "CSCD", value: value, rank: rank)
        }),
        ("nju", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "超一流期刊", "学科群一流期刊": rank = 1
            case "A": rank = 2
            case "B": rank = 3
            default: rank = nil
            }
            return Resolved(key: "NJU", value: value, rank: rank)
        }),
        ("cufe", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "AAA": rank = 2
            case "AA": rank = 3
            case "A": rank = 4
            default: rank = nil
            }
            return Resolved(key: "CUFE", value: value, rank: rank)
        }),
        ("swjtu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A++": rank = 1
            case "A+": rank = 2
            case "A": rank = 3
            case "B+": rank = 4
            case "B", "C": rank = 5
            default: rank = nil
            }
            return Resolved(key: "SWJTU", value: value, rank: rank)
        }),
        ("ruc", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A+": rank = 1
            case "A": rank = 2
            case "A-": rank = 3
            case "B": rank = 4
            default: rank = nil
            }
            return Resolved(key: "RUC", value: value, rank: rank)
        }),
        ("uibe", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A": rank = 1
            case "A-": rank = 2
            case "B": rank = 3
            default: rank = nil
            }
            return Resolved(key: "UIBE", value: value, rank: rank)
        }),
        ("sdufe", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "特类期刊": rank = 1
            case "A1": rank = 2
            case "A2": rank = 3
            case "B": rank = 4
            case "C": rank = 5
            default: rank = nil
            }
            return Resolved(key: "SDUFE", value: value, rank: rank)
        }),
        ("cug", { raw in
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(original.suffix(2)).uppercased()
            let rank: Int?
            switch tail {
            case "T1": rank = 1
            case "T2": rank = 2
            case "T3": rank = 3
            case "T4": rank = 4
            case "T5": rank = 5
            default: rank = nil
            }
            return Resolved(key: "CUG", value: original, rank: rank)
        }),
        ("xju", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "一区": rank = 1
            case "二区": rank = 2
            case "三区": rank = 3
            case "四区": rank = 4
            case "五区": rank = 5
            default: rank = nil
            }
            return Resolved(key: "XJU", value: value, rank: rank)
        }),
        ("xdu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "1类贡献度": rank = 1
            case "2类贡献度": rank = 2
            default: rank = nil
            }
            return Resolved(key: "XDU", value: value, rank: rank)
        }),
        ("hhu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "A类": rank = 1
            case "B类": rank = 2
            case "C类", "c类": rank = 3
            default: rank = nil
            }
            return Resolved(key: "HHU", value: value, rank: rank)
        }),
        ("fdu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A": rank = 2
            case "B": rank = 3
            default: rank = nil
            }
            return Resolved(key: "FDU", value: value, rank: rank)
        }),
        ("sjtu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A": rank = 2
            case "B": rank = 3
            default: rank = nil
            }
            return Resolved(key: "SJTU", value: value, rank: rank)
        }),
        ("fms", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let rank: Int?
            switch value {
            case "A", "T1": rank = 1
            case "B", "T2": rank = 2
            case "C": rank = 3
            case "D": rank = 4
            default: rank = nil
            }
            return Resolved(key: "FMS", value: value, rank: rank)
        }),
        ("scu", { raw in
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(original.suffix(1)).uppercased()
            let rank: Int?
            switch tail {
            case "A": rank = 1
            case "-": rank = 2
            case "B": rank = 3
            case "C": rank = 4
            case "D", "E": rank = 5
            default: rank = nil
            }
            return Resolved(key: "SCU", value: original, rank: rank)
        }),
        ("zju", { raw in
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized: String
            switch original {
            case "国内一级学术期刊": normalized = "国内一级"
            case "国内核心期刊": normalized = "国内核心"
            default: normalized = original
            }
            let rank: Int?
            switch normalized {
            case "国内一级": rank = 1
            case "国内核心": rank = 2
            default: rank = nil
            }
            return Resolved(key: "ZJU", value: normalized, rank: rank)
        }),
        ("cju", { raw in
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = String(original.prefix(2)).uppercased()
            let rank: Int?
            switch prefix {
            case "T1": rank = 1
            case "T2": rank = 2
            case "T3": rank = 3
            default: rank = nil
            }
            return Resolved(key: "YangtzeU", value: original, rank: rank)
        }),
        ("cqu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "A", "权威期刊": rank = 2
            case "B", "重要期刊": rank = 3
            case "C": rank = 4
            default: rank = nil
            }
            return Resolved(key: "CQU", value: value, rank: rank)
        }),
        ("cpu", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "一流": rank = 1
            case "权威": rank = 2
            case "学科顶尖": rank = 3
            case "学科一流": rank = 4
            case "学科重要": rank = 5
            default: rank = nil
            }
            return Resolved(key: "CPU", value: value, rank: rank)
        }),
        ("ajg", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank: Int?
            switch value {
            case "4*": rank = 1
            case "4": rank = 2
            case "3": rank = 3
            case "2": rank = 4
            case "1": rank = 5
            default: rank = nil
            }
            return Resolved(key: "AJG", value: value, rank: rank)
        }),
        ("ft50", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank = value == "FT50" ? 1 : nil
            return Resolved(key: "FT50", value: value == "FT50" ? "" : value, rank: rank)
        }),
        ("utd24", { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank = value == "UTD24" ? 1 : nil
            return Resolved(key: "UTD24", value: value == "UTD24" ? "" : value, rank: rank)
        }),
        ("sciwarn", { raw in
            Resolved(key: "SCIWARN", value: raw.trimmingCharacters(in: .whitespacesAndNewlines), rank: 1)
        })
    ]

    private static let profiles = Dictionary(uniqueKeysWithValues: orderedProfiles)

    static func resolve(source: String, raw: String) -> Resolved? {
        profiles[normalizeSource(source)]?(raw)
    }

    static func normalizeSource(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func sourceSortKey(_ source: String) -> Int {
        let key = normalizeSource(source)
        return orderedProfiles.firstIndex { $0.0 == key } ?? Int.max
    }

    static func rankLevel(source: String, raw: String) -> Int? {
        let compactValue = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")

        if let resolved = resolve(source: source, raw: raw), let rank = resolved.rank {
            return rank
        }

        return heuristicRankLevel(for: compactValue)
    }

    static func rankSortKey(source: String, raw: String) -> Int {
        rankLevel(source: source, raw: raw) ?? Int.max
    }

    static func compareSources(_ lhs: String, _ rhs: String) -> Bool {
        let lhsOrder = sourceSortKey(lhs)
        let rhsOrder = sourceSortKey(rhs)
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        return normalizeSource(lhs) < normalizeSource(rhs)
    }

    static func sortEntries(_ entries: [(String, String)]) -> [(String, String)] {
        entries.sorted { lhs, rhs in
            if compareSources(lhs.0, rhs.0) != compareSources(rhs.0, lhs.0) {
                return compareSources(lhs.0, rhs.0)
            }

            let lhsRank = rankSortKey(source: lhs.0, raw: lhs.1)
            let rhsRank = rankSortKey(source: rhs.0, raw: rhs.1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            return lhs.1.localizedCaseInsensitiveCompare(rhs.1) == .orderedAscending
        }
    }

    private static func resolveZoneLike(key: String, raw: String) -> Resolved {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(original.suffix(2))
        let rank: Int?
        switch suffix {
        case "1区": rank = 1
        case "2区": rank = 2
        case "3区": rank = 3
        case "4区": rank = 4
        default: rank = nil
        }
        return Resolved(key: key, value: original, rank: rank)
    }

    private static func heuristicRankLevel(for value: String) -> Int? {
        let normalized = value
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")

        let level1Tokens = [
            "AAA", "A++", "TOP", "T1", "1区", "一区", "特类", "特级", "甲类", "A+"
        ]
        if level1Tokens.contains(where: normalized.contains) {
            return 1
        }

        let level2Tokens = [
            "AA", "T2", "2区", "二区", "A类"
        ]
        if level2Tokens.contains(where: normalized.contains) {
            return 2
        }

        let level3Tokens = [
            "T3", "3区", "三区", "B+", "B类"
        ]
        if level3Tokens.contains(where: normalized.contains) {
            return 3
        }

        let level4Tokens = [
            "T4", "4区", "四区", "C+", "C类"
        ]
        if level4Tokens.contains(where: normalized.contains) {
            return 4
        }

        if normalized == "A" || normalized.hasSuffix("A") {
            return 3
        }
        if normalized == "B" || normalized.hasSuffix("B") {
            return 4
        }
        if normalized == "C" || normalized.hasSuffix("C") {
            return 4
        }

        return nil
    }
}
