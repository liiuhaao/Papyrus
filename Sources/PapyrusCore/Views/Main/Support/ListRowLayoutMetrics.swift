import SwiftUI

enum ListRowLayoutMetrics {
    static var stackSpacing: CGFloat { max(6, AppMetrics.inlineRowVertical * 2) }
    static var metaSpacing: CGFloat { max(8, AppMetrics.inlineRowVertical * 2.25) }
    static var verticalPadding: CGFloat { max(10, AppMetrics.inlineRowVertical * 2.75) }
    static var horizontalPadding: CGFloat { 12 }
    static var dividerInset: CGFloat { horizontalPadding + 4 }
    static var dividerOpacity: CGFloat { 0.12 }
    static var statusSlotHeight: CGFloat { max(18, 18 * AppStyleConfig.spacingScale) }
}
