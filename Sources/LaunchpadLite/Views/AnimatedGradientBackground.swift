import SwiftUI

/// Soft pastel mesh that drifts slowly, in the spirit of the Tool Platform
/// login screen. Static when the system asks for reduced motion.
///
/// The blobs are smooth gradients, so the mesh is drawn into a small canvas and
/// scaled up. That is visually identical but keeps the whole-screen animation
/// inexpensive.
struct AnimatedGradientBackground: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let renderScale: CGFloat = 0.28
    private static let frameInterval: Double = 1.0 / 30.0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(
                .animation(minimumInterval: Self.frameInterval, paused: reduceMotion || !isActive)
            ) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
                .frame(
                    width: proxy.size.width * Self.renderScale,
                    height: proxy.size.height * Self.renderScale,
                    alignment: .topLeading
                )
                .scaleEffect(1 / Self.renderScale, anchor: .topLeading)
            }
        }
        .background(Self.baseColor)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Self.baseColor)
        )

        for blob in Self.blobs {
            let center = blob.center(in: size, at: time)
            let radius = blob.radius(in: size, at: time)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: blob.color.opacity(blob.opacity), location: 0),
                        .init(color: blob.color.opacity(blob.opacity * 0.45), location: 0.55),
                        .init(color: blob.color.opacity(0), location: 1)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    private struct Blob {
        let color: Color
        /// Resting position and drift, both as fractions of the canvas size.
        let anchor: CGPoint
        let drift: CGVector
        /// Radius as a fraction of the canvas' longest side.
        let radiusFraction: CGFloat
        /// How much the radius breathes, as a fraction of the radius.
        let breathFraction: CGFloat
        let opacity: Double
        let period: Double
        let phase: Double

        func center(in size: CGSize, at time: TimeInterval) -> CGPoint {
            let angle = (time / period) * 2 * .pi + phase
            return CGPoint(
                x: (anchor.x + cos(angle) * drift.dx) * size.width,
                y: (anchor.y + sin(angle * 0.8) * drift.dy) * size.height
            )
        }

        func radius(in size: CGSize, at time: TimeInterval) -> CGFloat {
            let base = max(size.width, size.height) * radiusFraction
            // Breathing runs slower than the drift so it reads as a slow swell
            // rather than a pulse.
            let breath = sin((time / (period * 1.3)) * 2 * .pi + phase) * breathFraction
            return base * (1 + breath)
        }
    }

    private static let baseColor = Color(red: 0.972, green: 0.973, blue: 0.986)

    private static let blobs: [Blob] = [
        Blob(
            color: Color(red: 0.98, green: 0.72, blue: 0.88),
            anchor: CGPoint(x: 0.17, y: 0.22),
            drift: CGVector(dx: 0.19, dy: 0.18),
            radiusFraction: 0.48,
            breathFraction: 0.16,
            opacity: 0.92,
            period: 9,
            phase: 0.0
        ),
        Blob(
            color: Color(red: 0.73, green: 0.75, blue: 0.98),
            anchor: CGPoint(x: 0.83, y: 0.24),
            drift: CGVector(dx: 0.20, dy: 0.17),
            radiusFraction: 0.52,
            breathFraction: 0.18,
            opacity: 0.92,
            period: 11.5,
            phase: 1.2
        ),
        Blob(
            color: Color(red: 0.68, green: 0.94, blue: 0.82),
            anchor: CGPoint(x: 0.78, y: 0.82),
            drift: CGVector(dx: 0.18, dy: 0.19),
            radiusFraction: 0.46,
            breathFraction: 0.17,
            opacity: 0.88,
            period: 10,
            phase: 2.6
        ),
        Blob(
            color: Color(red: 0.69, green: 0.86, blue: 0.99),
            anchor: CGPoint(x: 0.20, y: 0.80),
            drift: CGVector(dx: 0.19, dy: 0.17),
            radiusFraction: 0.50,
            breathFraction: 0.17,
            opacity: 0.90,
            period: 12.5,
            phase: 4.1
        ),
        Blob(
            color: Color(red: 0.99, green: 0.80, blue: 0.70),
            anchor: CGPoint(x: 0.46, y: 0.92),
            drift: CGVector(dx: 0.22, dy: 0.14),
            radiusFraction: 0.36,
            breathFraction: 0.20,
            opacity: 0.72,
            period: 8,
            phase: 5.3
        ),
        Blob(
            color: Color(red: 0.98, green: 0.93, blue: 0.70),
            anchor: CGPoint(x: 0.54, y: 0.08),
            drift: CGVector(dx: 0.21, dy: 0.13),
            radiusFraction: 0.34,
            breathFraction: 0.20,
            opacity: 0.68,
            period: 8.5,
            phase: 3.4
        )
    ]
}
