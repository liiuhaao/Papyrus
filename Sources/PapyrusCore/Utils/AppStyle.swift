import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum AppAppearance: String {
    case system
    case light
    case dark

    static func parse(_ raw: String?) -> AppAppearance {
        guard let raw else { return .system }
        switch raw.lowercased() {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum RankSourceConfig {
    static func normalizedKeys(_ rawValues: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in rawValues {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(key)
        }

        return ordered
    }

    static func parseText(_ text: String) -> [String] {
        normalizedKeys(
            text
                .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        )
    }

    static func formatText(_ keys: [String]) -> String {
        normalizedKeys(keys).joined(separator: ", ")
    }

    static func displayName(for key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    static func displayLabel(for key: String, value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName(for: key)
        return trimmedValue.isEmpty ? name : "\(name) \(trimmedValue)"
    }
}

enum AppStyleConfig {
    static let fontScale: CGFloat = 1.0
    static let spacingScale: CGFloat = 1.0
}

enum AppTypography {
    private static func scaled(_ base: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        Font.system(size: base * AppStyleConfig.fontScale, weight: weight, design: design)
    }

    static var titleLarge: Font { scaled(20, weight: .semibold) }
    static var titleMedium: Font { scaled(17, weight: .semibold) }
    static var titleSmall: Font { scaled(15, weight: .semibold) }

    static var body: Font { scaled(13) }
    static var bodyStrong: Font { scaled(13, weight: .semibold) }
    static var bodySmall: Font { scaled(12) }
    static var bodySmallMedium: Font { scaled(12, weight: .medium) }

    static var label: Font { scaled(12) }
    static var labelMedium: Font { scaled(11, weight: .medium) }
    static var labelStrong: Font { scaled(11, weight: .semibold) }
    static var overline: Font { scaled(11, weight: .semibold) }

    static var mono: Font { scaled(12, design: .monospaced) }
    static var monoLabel: Font { scaled(11, weight: .medium, design: .monospaced) }
    static var monoSmall: Font { scaled(11, design: .monospaced) }
}

enum AppMetrics {
    private static func scaled(_ base: CGFloat) -> CGFloat {
        base * AppStyleConfig.spacingScale
    }

    static var sectionSpacing: CGFloat { scaled(28) }
    static var panelPadding: CGFloat { scaled(28) }
    static var cardPadding: CGFloat { scaled(14) }
    static var inlineRowVertical: CGFloat { scaled(4) }
    static var tabBarHorizontal: CGFloat { scaled(16) }
    static var tabBarTop: CGFloat { scaled(14) }
    static var tabBarBottom: CGFloat { scaled(10) }
    static var tabButtonWidth: CGFloat { scaled(96) }
    static var tabButtonHeight: CGFloat { scaled(54) }
    static var controlCornerRadius: CGFloat { scaled(10) }
    static var cardCornerRadius: CGFloat { scaled(10) }
    static var pillHorizontal: CGFloat { scaled(8) }
    static var pillVertical: CGFloat { scaled(3) }
    static var badgeHorizontal: CGFloat { scaled(6) }
    static var badgeVertical: CGFloat { scaled(1) }
}

enum AppEditorMetrics {
    static var compactIconSize: CGFloat { 12 * AppStyleConfig.fontScale }
    static var miniIconSize: CGFloat { 9 * AppStyleConfig.fontScale }
    static var compactTextSize: CGFloat { 11 * AppStyleConfig.fontScale }
    static var compactLabelSize: CGFloat { 10 * AppStyleConfig.fontScale }
    static var microSpacing: CGFloat { max(3, AppMetrics.badgeVertical + 2) }
    static var compactSpacing: CGFloat { max(6, AppMetrics.inlineRowVertical + 2) }
    static var sectionSpacing: CGFloat { max(10, AppMetrics.inlineRowVertical * 2.5) }
    static var fieldSpacing: CGFloat { max(10, 12 * AppStyleConfig.spacingScale) }
    static var doubleFieldSpacing: CGFloat { max(12, 14 * AppStyleConfig.spacingScale) }
    static var buttonGroupSpacing: CGFloat { max(8, 10 * AppStyleConfig.spacingScale) }
    static var footnoteSpacing: CGFloat { max(4, AppMetrics.badgeVertical + 3) }
    static var rowIconWidth: CGFloat { max(14, 14 * AppStyleConfig.spacingScale) }
    static var bodyBottomSpacing: CGFloat { max(8, 8 * AppStyleConfig.spacingScale) }
    static var chipRadius: CGFloat { max(5, AppMetrics.controlCornerRadius - 5) }
    static var chipSpacing: CGFloat { max(4, AppMetrics.badgeVertical + 3) }
    static var inputCornerRadius: CGFloat { max(8, AppMetrics.controlCornerRadius - 2) }
    static var fieldLabelWidth: CGFloat { 64 * AppStyleConfig.spacingScale }
    static var smallFieldLabelWidth: CGFloat { 40 * AppStyleConfig.spacingScale }
    static var wideFieldLabelWidth: CGFloat { 72 * AppStyleConfig.spacingScale }
    static var sectionHorizontalPadding: CGFloat { AppMetrics.panelPadding - 10 }
    static var sectionVerticalPadding: CGFloat { AppMetrics.cardPadding }
    static var headerHorizontalPadding: CGFloat { AppMetrics.panelPadding - 12 }
    static var tagInputHorizontalPadding: CGFloat { AppMetrics.pillHorizontal + 4 }
    static var tagInputVerticalPadding: CGFloat { AppMetrics.pillVertical + 4 }
    static var availableHeight: CGFloat { max(72, 72 * AppStyleConfig.spacingScale) }
}

// MARK: - App Colors

enum AppColors {
    enum RankValueKind {
        case rank
        case metric
        case category
    }

    // Tier colors: 1=red, 2=orange, 3=blue, 4=teal
    static func rankLevelColor(_ level: Int?) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .blue
        case 4: return .teal
        default: return .secondary
        }
    }

    static func rankValueKind(source: String, value: String) -> RankValueKind {
        let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawValue = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let metricSources: Set<String> = [
            "if", "sciif", "sciif5", "jci", "hindex", "citescore", "snip", "sjr"
        ]
        if metricSources.contains(sourceKey) {
            return .metric
        }

        if rawValue.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            return .metric
        }

        if rankLevel(source: source, value: value) != nil {
            return .rank
        }

        return .category
    }

    static func rankLevel(source: String, value: String) -> Int? {
        RankProfiles.rankLevel(source: source, raw: value)
    }

    static func rankColor(source: String, value: String) -> Color {
        switch rankValueKind(source: source, value: value) {
        case .rank:
            return rankLevelColor(rankLevel(source: source, value: value))
        case .metric, .category:
            return .secondary
        }
    }

    // Legacy helpers retained for existing call sites.
    // Semantic tokens
    static let citation: Color = .purple
    static let tag: Color = .brown
    static let star: Color = .orange
    static let error: Color = .red
    static let success: Color = .green

    private static let namespacePalette: [Color] = [
        .blue, .teal, .indigo, .mint, .pink, .cyan, .green, .red
    ]

    static func namespaceColor(_ namespace: String?) -> Color {
        guard let namespace, !namespace.isEmpty else { return tag }

        let configured = TagNamespaceSupport.normalizedNamespaces(TagNamespaceConfig.configuredNamespaces)
        if let index = configured.firstIndex(of: namespace.lowercased()) {
            return namespacePalette[index % namespacePalette.count]
        }

        let hash = namespace.lowercased().unicodeScalars.reduce(0) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
        return namespacePalette[abs(hash) % namespacePalette.count]
    }

    static func tagColor(_ tag: String) -> Color {
        if let namespace = TagNamespaceSupport.namespace(for: tag) {
            return namespaceColor(namespace)
        }
        return AppColors.tag
    }
}

// MARK: - App Status Style

enum AppStatusStyle {
    static func icon(for status: Paper.ReadingStatus) -> String {
        switch status {
        case .unread: return "circle"
        case .reading: return "clock"
        case .read: return "checkmark.circle.fill"
        }
    }

    static func tint(for status: Paper.ReadingStatus) -> Color {
        switch status {
        case .unread:   return .blue
        case .reading:  return .orange
        case .read: return .green
        }
    }
}

struct AppPillStyle: ViewModifier {
    let background: Color
    let foreground: Color
    var horizontal: CGFloat = AppMetrics.pillHorizontal
    var vertical: CGFloat = AppMetrics.pillVertical

    func body(content: Content) -> some View {
        content
            .font(AppTypography.labelStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(background)
            .clipShape(Capsule())
    }
}

extension View {
    func appPill(
        background: Color,
        foreground: Color = .primary,
        horizontal: CGFloat = AppMetrics.pillHorizontal,
        vertical: CGFloat = AppMetrics.pillVertical
    ) -> some View {
        modifier(
            AppPillStyle(
                background: background,
                foreground: foreground,
                horizontal: horizontal,
                vertical: vertical
            )
        )
    }

    /// Semantic badge pill — colour + standard opacity token
    func appBadgePill(
        _ color: Color,
        horizontal: CGFloat = AppMetrics.badgeHorizontal,
        vertical: CGFloat = AppMetrics.badgeVertical
    ) -> some View {
        appPill(
            background: color.opacity(AppPillStyle.badgeBackgroundOpacity),
            foreground: color,
            horizontal: horizontal,
            vertical: vertical
        )
    }

    func appCardSurface(
        fill: Color = Color.primary.opacity(0.03),
        stroke: Color = Color.primary.opacity(0.07),
        cornerRadius: CGFloat = AppMetrics.cardCornerRadius
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func appInsetInputSurface(
        fill: Color = Color.primary.opacity(0.05),
        stroke: Color = Color.clear,
        cornerRadius: CGFloat = AppMetrics.controlCornerRadius
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    func appSelectableRowSurface(
        selected: Bool,
        fill: Color = Color.primary.opacity(0.06)
    ) -> some View {
        background(selected ? fill : .clear)
    }
}

extension AppPillStyle {
    /// Single source of truth for badge background opacity
    static let badgeBackgroundOpacity: Double = 0.13
}

struct AppInlineValueRow<TrailingAction: View>: View {
    let symbol: String
    let value: String
    var isMonospaced: Bool = true
    var leadingImage: NSImage?
    @ViewBuilder let trailingAction: TrailingAction

    init(
        symbol: String,
        value: String,
        isMonospaced: Bool = true,
        leadingImage: NSImage? = nil,
        @ViewBuilder trailingAction: () -> TrailingAction = { EmptyView() }
    ) {
        self.symbol = symbol
        self.value = value
        self.isMonospaced = isMonospaced
        self.leadingImage = leadingImage
        self.trailingAction = trailingAction()
    }

    var body: some View {
        HStack(spacing: AppEditorMetrics.buttonGroupSpacing) {
            if let leadingImage {
                Image(nsImage: leadingImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: 16 * AppStyleConfig.spacingScale,
                        height: 16 * AppStyleConfig.spacingScale
                    )
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16 * AppStyleConfig.spacingScale)
            }
            Text(value)
                .font(isMonospaced ? AppTypography.monoSmall : AppTypography.bodySmall)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            trailingAction
        }
        .padding(.horizontal, 2)
        .padding(.vertical, AppMetrics.inlineRowVertical)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }
}

// MARK: - Search Highlight

func highlightedText(_ text: String, terms: [String]) -> AttributedString {
    var output = AttributedString(text)
    let loweredText = text.lowercased()
    let unique = Array(Set(terms.map { $0.lowercased() })).sorted { $0.count > $1.count }
    for term in unique where !term.isEmpty {
        var searchStart = loweredText.startIndex
        while let range = loweredText.range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<loweredText.endIndex
        ) {
            if let start = AttributedString.Index(range.lowerBound, within: output),
               let end = AttributedString.Index(range.upperBound, within: output) {
                let attrRange = start..<end
                output[attrRange].backgroundColor = Color.accentColor.opacity(0.18)
            }
            searchStart = range.upperBound
        }
    }
    return output
}

func highlightedSnippet(_ text: String, terms: [String], maxLength: Int = 96) -> AttributedString? {
    let condensed = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !condensed.isEmpty else { return nil }

    let normalizedTerms = Array(Set(
        terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    ))
    guard !normalizedTerms.isEmpty else { return nil }

    let nsText = condensed as NSString
    var matchRange = NSRange(location: NSNotFound, length: 0)
    for term in normalizedTerms {
        let range = nsText.range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        if range.location == NSNotFound { continue }
        if matchRange.location == NSNotFound || range.location < matchRange.location {
            matchRange = range
        }
    }
    guard matchRange.location != NSNotFound else { return nil }

    let snippetLimit = max(24, maxLength)
    var start = max(0, matchRange.location - snippetLimit / 3)
    let end = min(nsText.length, start + snippetLimit)
    if end - start < snippetLimit {
        start = max(0, end - snippetLimit)
    }

    let snippet = nsText.substring(with: NSRange(location: start, length: max(0, end - start)))
    let display = "\(start > 0 ? "…" : "")\(snippet)\(end < nsText.length ? "…" : "")"
    return highlightedText(display, terms: normalizedTerms)
}

struct AppEditorFieldRow<Field: View>: View {
    let label: String
    let labelWidth: CGFloat
    @ViewBuilder let field: Field

    init(
        label: String,
        labelWidth: CGFloat,
        @ViewBuilder field: () -> Field
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.field = field()
    }

    var body: some View {
        HStack(spacing: AppEditorMetrics.fieldSpacing) {
            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            field
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppEditorMetrics.compactSpacing)
    }
}

struct AppEditorDoubleFieldRow<LeftField: View, RightField: View>: View {
    let leftLabel: String
    let leftLabelWidth: CGFloat
    let rightLabel: String
    let rightLabelWidth: CGFloat
    @ViewBuilder let leftField: LeftField
    @ViewBuilder let rightField: RightField

    init(
        leftLabel: String,
        leftLabelWidth: CGFloat,
        rightLabel: String,
        rightLabelWidth: CGFloat,
        @ViewBuilder leftField: () -> LeftField,
        @ViewBuilder rightField: () -> RightField
    ) {
        self.leftLabel = leftLabel
        self.leftLabelWidth = leftLabelWidth
        self.rightLabel = rightLabel
        self.rightLabelWidth = rightLabelWidth
        self.leftField = leftField()
        self.rightField = rightField()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppEditorMetrics.doubleFieldSpacing) {
            AppEditorFieldRow(label: leftLabel, labelWidth: leftLabelWidth) {
                leftField
            }
            AppEditorFieldRow(label: rightLabel, labelWidth: rightLabelWidth) {
                rightField
            }
        }
    }
}

struct AppEditorHeader: View {
    let title: String?
    let subtitle: String?
    let confirmTitle: String
    var confirmDisabled: Bool = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(AppTypography.titleSmall)
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: AppEditorMetrics.buttonGroupSpacing) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(confirmDisabled)
            }
        }
        .padding(.horizontal, AppEditorMetrics.headerHorizontalPadding)
        .padding(.top, AppMetrics.cardPadding - 2)
        .padding(.bottom, AppMetrics.cardPadding - 4)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct AppEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppEditorMetrics.sectionSpacing) {
            Text(title)
                .font(AppTypography.labelStrong)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(.vertical, AppMetrics.cardPadding + 2)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
