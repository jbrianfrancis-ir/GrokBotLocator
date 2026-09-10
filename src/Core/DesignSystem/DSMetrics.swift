import CoreGraphics

/// Spacing, tap-target, and radius tokens from DESIGN.md. Type tokens are DSTypography (01-02).
enum DSMetrics {
    /// 8pt base spacing unit.
    static let spacingBase: CGFloat = 8
    /// Spacing between grouped controls.
    static let groupGap: CGFloat = 24
    /// Minimum screen margin.
    static let screenMargin: CGFloat = 16
    /// Minimum tap target size (above Apple's 44pt floor).
    static let minTapTarget: CGFloat = 60
    /// Primary action minimum height.
    static let primaryActionHeight: CGFloat = 88
    /// Corner radius for cards and buttons.
    static let cornerRadius: CGFloat = 16
    /// Corner radius for the primary action.
    static let primaryActionRadius: CGFloat = 28
}
