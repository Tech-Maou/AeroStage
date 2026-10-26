import AeroStageCore
import CoreGraphics

/// Sizes of the sidebar's cards, shared by the layout (cards shrink when there are many)
/// and the stage limit (how many cards fit on the current monitor).
struct CardMetrics {
    static let outerPadding: CGFloat = 6
    static let spacing: CGFloat = 6
    static let cardPadding: CGFloat = 6
    static let headerGap: CGFloat = 5
    static let newStageHeight: CGFloat = 30
    /// Previews may shrink to this share of their natural height before a stage no longer fits.
    static let minimumScale: CGFloat = 0.7

    var panelSize: CGSize
    var style: CardStyle
    var titleSize: CGFloat
    var iconScale: CGFloat
    /// Width / height of the area AeroSpace lays windows out in (for the layout view).
    var canvasAspect: CGFloat

    var headerHeight: CGFloat { ((titleSize + 3) * 1.3).rounded(.up) }
    var chrome: CGFloat { headerHeight + Self.headerGap + 2 * Self.cardPadding }
    var contentWidth: CGFloat { panelSize.width - 2 * Self.outerPadding - 2 * Self.cardPadding }

    var naturalContentHeight: CGFloat {
        switch style {
        case .thumbnails: contentWidth / 1.25
        case .layout: contentWidth / max(canvasAspect, 0.5)
        // Two rows of icons; the icon grid does not shrink.
        case .icons: 2 * 44 * iconScale + 6
        }
    }

    var minimumContentHeight: CGFloat {
        style == .icons ? naturalContentHeight : naturalContentHeight * Self.minimumScale
    }

    /// Height for the cards alone: panel minus padding and the "New Stage" area.
    var availableHeight: CGFloat {
        panelSize.height - 2 * Self.outerPadding - Self.newStageHeight - Self.spacing
    }

    var capacity: Int {
        StageCapacity.count(availableHeight: availableHeight, cardChrome: chrome,
                            minContentHeight: minimumContentHeight, spacing: Self.spacing)
    }

    func contentHeight(forCount count: Int) -> CGFloat {
        StageCapacity.contentHeight(availableHeight: availableHeight, count: count, cardChrome: chrome,
                                    naturalContentHeight: naturalContentHeight, spacing: Self.spacing)
    }
}
