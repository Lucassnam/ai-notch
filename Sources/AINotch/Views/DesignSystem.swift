import SwiftUI

extension ProviderID {
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.91, green: 0.55, blue: 0.39)
        case .codex: Color(red: 0.33, green: 0.85, blue: 0.68)
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sun.max.fill"
        case .codex: "terminal.fill"
        }
    }
}

/// The whole type system. Six sizes, nothing smaller than 11pt.
///
/// The previous design used fifteen ad-hoc sizes ranging down to 7pt, most of
/// them set in letterspaced capitals at 34% opacity. Size, case, and contrast
/// were all working against legibility at once. Hierarchy here comes from
/// weight and colour so the smallest text can stay comfortably readable.
enum NotchType {
    // Standard SF throughout. The cards used the rounded face while the graph
    // and the menu-bar values used the standard one, so the same dollar figure
    // was set two ways depending on the tab. At 20pt and up SF switches to its
    // display cut and tightens its own tracking.
    static let display = Font.system(size: 30, weight: .semibold)
    /// The card figure when three rows share the page.
    static let displayShort = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static let value = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .medium)
    static let label = Font.system(size: 11, weight: .medium)
    /// Compact values mirror native menu-bar typography.
    ///
    /// Both slots share one face, one size and one weight. They previously
    /// differed by weight (medium vs semibold), which at 13pt reads as two
    /// different sizes sitting either side of the notch.
    ///
    /// Regular, because that is what the menu titles beside it use: measured
    /// on a 2x capture, "Help" and these figures share a 19px cap height but
    /// medium drew 4px stems against the menu's 3px, which read as bigger.
    static let compact = Font.system(size: NotchMetrics.compactFontSize, weight: .regular)
    static let compactLeading = compact
    static let compactTrailing = compact
    static let tab = Font.system(size: 13, weight: .medium)
}

enum NotchDesign {
    static let panel = Color.black
    static let card = Color.white.opacity(0.07)
    static let cardStrong = Color.white.opacity(0.14)
    /// Raised from 0.58/0.34. The old tertiary sat near 4:1 against black and
    /// carried the smallest text in the app; this lands nearer 7:1.
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.52)
    static let divider = Color.white.opacity(0.10)

    /// Every hairline that outlines a surface. Was written inline as 0.06 in
    /// five places and 0.08 in two more.
    static let stroke = Color.white.opacity(0.07)
    /// Resting and active fills for a control that is not a card.
    static let control = Color.white.opacity(0.08)
    static let controlPressed = Color.white.opacity(0.14)
    static let controlActive = Color.white.opacity(0.16)
    /// The "on" fill of a switch. Drawn by the app because the notch panel is
    /// never the key window, and AppKit greys out its own controls there.
    static let switchOn = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// System red in its dark-mode value, for the one destructive action.
    static let destructive = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// The selected segment of a segmented control.
    static let segmentSelected = Color.white.opacity(0.20)

    /// Where the panel's ground ends up at its bottom edge. The top has to be
    /// pure black to meet the hardware notch, so the metal is a ramp from
    /// black rather than a flat grey.
    static let graphite = Color(white: 0.115)

    /// A card is lit from above: brighter face at the top, and a top edge
    /// that catches the light. The gradient is the whole effect, so the card
    /// needs no shadow and no second colour.
    static let cardFace = LinearGradient(
        colors: [Color.white.opacity(0.105), Color.white.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let cardEdge = LinearGradient(
        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )
    /// The chart plot ground. Distinct from `card` so a chart never reads as
    /// a tappable surface.
    static let plot = Color.white.opacity(0.035)

    /// Two radii, not five. Cards and plot grounds use `cardRadius`; anything
    /// the pointer can hit uses `controlRadius`.
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    /// Inner padding for a metric card. A short card (three rows to a page)
    /// drops to 12pt top and bottom so the figure keeps its own line height.
    static let cardPadding: CGFloat = 14
}

/// Spacing follows the macOS HIG rather than per-view guesses. Apple recommends
/// about 12pt around bezeled controls and about 24pt around unbezeled visible
/// edges; the notch dashboard deliberately steps up to 32pt at window edges.
enum MacSpacing {
    static let compact: CGFloat = 4
    static let related: CGFloat = 8
    static let control: CGFloat = 12
    static let item: CGFloat = 16
    static let section: CGFloat = 24
    static let window: CGFloat = 32
}

// MARK: - Liquid Glass

/// Liquid Glass is macOS 26+. The deployment target stays at macOS 14, so every
/// call is availability-gated here and nowhere else; older systems fall back to
/// the material treatment the app already used.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = NotchDesign.cardRadius
    var enabled: Bool = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(
                    enabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(NotchDesign.card),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(NotchDesign.stroke, lineWidth: 1)
                }
        }
    }
}

/// Wraps sibling glass surfaces so they blend into one another instead of
/// stacking their own refraction. A no-op before macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Metal

/// Bead-blasted aluminium: a fine, even grain with no direction to it.
///
/// One 128px tile of seeded noise, drawn at 2x so a speck is one device pixel.
/// Seeded rather than random so two captures of the same screen are identical.
enum MetalGrain {
    static let tile: CGImage? = {
        let side = 128
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let roll = UInt8(truncatingIfNeeded: state >> 33)
            let isLight = (state >> 41) & 1 == 0
            // Premultiplied: a light speck carries its alpha in every channel,
            // a dark one only in the alpha channel.
            let alpha = UInt8(Int(roll) * 150 / 255)
            let channel: UInt8 = isLight ? alpha : 0
            pixels[index * 4] = channel
            pixels[index * 4 + 1] = channel
            pixels[index * 4 + 2] = channel
            pixels[index * 4 + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }()
}

struct GrainOverlay: View {
    var strength: Double = 0.12

    var body: some View {
        if let tile = MetalGrain.tile {
            Rectangle()
                .fill(ImagePaint(image: Image(decorative: tile, scale: 2)))
                .opacity(strength)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// The one card surface of the opened panel.
    func metalCard(radius: CGFloat = NotchDesign.cardRadius) -> some View {
        self
            .background(
                NotchDesign.cardFace,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NotchDesign.cardEdge, lineWidth: 1)
            }
    }

    func glassSurface(radius: CGFloat = NotchDesign.cardRadius, enabled: Bool = true) -> some View {
        modifier(GlassSurface(radius: radius, enabled: enabled))
    }

    /// A plain card. Used where a surface needs to read as content rather than
    /// as a floating control, so it stays flat even on Liquid Glass systems.
    func cardSurface(padding: CGFloat = 12, radius: CGFloat = NotchDesign.cardRadius) -> some View {
        self
            .padding(padding)
            .background(NotchDesign.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(NotchDesign.stroke, lineWidth: 1)
            }
    }
}

// MARK: - Shapes

/// A top-attached panel whose shoulders curve inward from the screen edge.
/// The top is wider than the body, producing the inverse radius used by
/// physical notches instead of a detached rounded-rectangle corner.
struct TopConnectedNotchShape: Shape {
    let topShoulderRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let shoulder = min(
            max(0, topShoulderRadius),
            rect.height / 2,
            rect.width / 4
        )
        let bodyLeft = rect.minX + shoulder
        let bodyRight = rect.maxX - shoulder
        let bottom = min(
            max(0, bottomCornerRadius),
            rect.height - shoulder,
            (bodyRight - bodyLeft) / 2
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: bodyRight, y: rect.minY + shoulder),
            control1: CGPoint(x: rect.maxX - shoulder * 0.55, y: rect.minY),
            control2: CGPoint(x: bodyRight, y: rect.minY + shoulder * 0.45)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - bottom, y: rect.maxY),
            control: CGPoint(x: bodyRight, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyLeft + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyLeft, y: rect.maxY - bottom),
            control: CGPoint(x: bodyLeft, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyLeft, y: rect.minY + shoulder))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: bodyLeft, y: rect.minY + shoulder * 0.45),
            control2: CGPoint(x: rect.minX + shoulder * 0.55, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Shared components

/// A label above a value. Sentence case, not letterspaced capitals.
struct MetricLabel: View {
    let title: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    var tint: Color = .white

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(NotchType.label)
                .foregroundStyle(NotchDesign.tertiary)
            Text(value)
                .font(NotchType.value)
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// The headline figure on a page: caption, large number, supporting line.
struct PageHeadline: View {
    let caption: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption)
                .font(NotchType.label)
                .foregroundStyle(NotchDesign.tertiary)
            Text(value)
                .font(NotchType.display)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(NotchType.label)
                    .foregroundStyle(NotchDesign.secondary)
            }
        }
    }
}

/// A capsule segmented control: equal segments, and a selection that slides.
///
/// Used for the tab bar and for both graph selectors, so the panel has one
/// way of choosing between things. Replaces `Picker(.segmented)`, which
/// rendered as a light-mode control inside the dark panel and could not be
/// sized to fit alongside neighbouring content.
struct RangeSelector<Value: Hashable & Identifiable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    var height: CGFloat = 26
    var font: Font = NotchType.label
    /// Draws an SF Symbol instead of the title, which stays as the help text.
    var symbol: ((Value) -> String)? = nil
    @Namespace private var selectionSpace

    private let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.24)) { selection = option }
                } label: {
                    Group {
                        if let symbol {
                            Image(systemName: symbol(option))
                                .accessibilityLabel(title(option))
                        } else {
                            Text(title(option))
                        }
                    }
                        .font(font)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundStyle(isSelected ? Color.white : NotchDesign.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - inset * 2)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(NotchDesign.segmentSelected)
                                    .overlay {
                                        Capsule().strokeBorder(NotchDesign.cardEdge, lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(symbol == nil ? "" : title(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(inset)
        .background(NotchDesign.control, in: Capsule())
    }
}

/// A thin bar split into coloured shares of a whole.
///
/// On a spend card it shows how the figure divides between providers; on a
/// limit card, how much of the allowance is left. The unfilled remainder is
/// the track, so an empty bar means "nothing yet", not "broken".
struct ShareBar: View {
    struct Share: Identifiable {
        let id: Int
        let color: Color
        let fraction: Double
    }

    let shares: [Share]
    private let height: CGFloat = 3
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let visible = shares.filter { $0.fraction > 0 }
            let usable = max(0, proxy.size.width - gap * CGFloat(max(0, visible.count - 1)))
            ZStack(alignment: .leading) {
                Capsule().fill(NotchDesign.control)
                HStack(spacing: gap) {
                    ForEach(visible) { share in
                        Capsule()
                            .fill(share.color)
                            // Never thinner than its own height: a 1% share
                            // stays a dot instead of vanishing.
                            .frame(width: max(height, usable * min(1, share.fraction)))
                    }
                }
                .frame(maxWidth: proxy.size.width, alignment: .leading)
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
