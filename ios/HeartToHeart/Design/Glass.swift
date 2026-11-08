import SwiftUI

// Liquid Glass with a graceful fallback.
// Built with Xcode 26+ (Swift 6.2+) on iOS 26+: real Liquid Glass.
// Built with older Xcode or running on iOS 18–25: system materials.
// Standard SwiftUI containers (TabView, NavigationStack, toolbars, sheets) adopt
// Liquid Glass automatically when compiled with the iOS 26 SDK.

extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.liquidGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            fallbackGlass(in: shape, tint: tint)
        }
        #else
        fallbackGlass(in: shape, tint: tint)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func liquidGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif

    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(in: Capsule(), tint: tint, interactive: interactive)
    }

    private func fallbackGlass<S: Shape>(in shape: S, tint: Color?) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                if let tint { shape.fill(tint.opacity(0.35)) }
                shape.hairline(.white.opacity(0.18))
            }
        }
    }

    /// Groups adjacent glass shapes so they blend (iOS 26), no-op before.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 16) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private extension Shape {
    func hairline(_ color: Color) -> some View {
        stroke(color, lineWidth: 0.5)
    }
}

/// Soft, slowly shifting backdrop so glass has something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t / 6) * 0.08)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.5 - drift], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: scheme == .dark ? Self.dark : Self.light
            )
        }
        .ignoresSafeArea()
    }

    private static let light: [Color] = [
        Color(red: 1.00, green: 0.93, blue: 0.90), Color(red: 0.98, green: 0.90, blue: 0.95), Color(red: 0.90, green: 0.93, blue: 1.00),
        Color(red: 1.00, green: 0.96, blue: 0.92), Color(red: 0.97, green: 0.95, blue: 1.00), Color(red: 0.92, green: 0.97, blue: 1.00),
        Color(red: 1.00, green: 0.97, blue: 0.85), Color(red: 0.95, green: 0.97, blue: 0.98), Color(red: 0.88, green: 0.94, blue: 1.00),
    ]

    private static let dark: [Color] = [
        Color(red: 0.16, green: 0.07, blue: 0.12), Color(red: 0.10, green: 0.07, blue: 0.16), Color(red: 0.05, green: 0.08, blue: 0.18),
        Color(red: 0.12, green: 0.06, blue: 0.10), Color(red: 0.08, green: 0.07, blue: 0.14), Color(red: 0.04, green: 0.09, blue: 0.16),
        Color(red: 0.14, green: 0.10, blue: 0.05), Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.03, green: 0.07, blue: 0.14),
    ]
}

/// Round initials avatar.
struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(gradient))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var gradient: LinearGradient {
        // Stable across launches (hashValue is randomized per process).
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.55, brightness: 0.9), Color(hue: hue, saturation: 0.7, brightness: 0.65)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
