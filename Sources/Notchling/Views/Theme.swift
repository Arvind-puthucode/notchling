import SwiftUI

/// Design tokens. Colors derive from `.primary`, so the light and dark looks share one code path.
enum Tok {
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let done = Color(red: 0.36, green: 0.84, blue: 0.52)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let star = Color(red: 1.0, green: 0.82, blue: 0.3)
    static let radius: CGFloat = 12
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)

    static func fill(_ o: Double = 0.07) -> Color { Color.primary.opacity(o) }
    static func ink(_ o: Double) -> Color { Color.primary.opacity(o) }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View {
        content.font(.system(size: (size * scale).rounded(), weight: weight, design: design))
    }
}

extension View {
    /// System font scaled by the "Text size" setting.
    func nfont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    func card(_ padding: CGFloat = 10, opacity: Double = 0.06) -> some View {
        self.padding(padding).background(Tok.fill(opacity), in: RoundedRectangle(cornerRadius: Tok.radius, style: .continuous))
    }
}

/// Background of the open notch for the chosen look.
struct NotchBackground {
    static func color(light: Bool) -> Color { light ? Color(white: 0.965) : .black }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let base = tint ?? .primary
        configuration.label
            .nfont(12, .semibold)
            .lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(
                Capsule().fill(prominent ? base : base.opacity(configuration.isPressed ? 0.28 : hovering ? 0.2 : 0.13)))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : (tint ?? .primary))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ tint: Color, prominent: Bool = false) -> PillButtonStyle { PillButtonStyle(tint: tint, prominent: prominent) }
}

/// Small borderless icon button with a hover circle.
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color? = nil
    var size: CGFloat = 12
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .nfont(size, .semibold)
                .foregroundStyle(tint ?? Tok.ink(hovering ? 0.95 : 0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Tok.fill(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .nfont(10, .bold)
            .tracking(0.6)
            .foregroundStyle(Tok.ink(0.42))
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).nfont(22, .light).foregroundStyle(Tok.ink(0.3))
            Text(title).nfont(13, .medium).foregroundStyle(Tok.ink(0.6))
            if !subtitle.isEmpty {
                Text(subtitle).nfont(11).foregroundStyle(Tok.ink(0.4)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Circular progress used by Today and Focus.
struct Ring: View {
    var progress: Double
    var lineWidth: CGFloat = 3
    var tint: Color = Tok.done
    var body: some View {
        ZStack {
            Circle().stroke(Tok.fill(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Tok.spring, value: progress)
        }
    }
}
