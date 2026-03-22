import AppKit
import CoreGraphics
import SwiftUI

enum BrandPalette {
    static let logoBackground = NSColor(srgbRed: 0.16, green: 0.22, blue: 0.19, alpha: 1.0)
    static let logoForeground = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.93, alpha: 1.0)
    static let logoAccent = NSColor(srgbRed: 0.76, green: 0.63, blue: 0.28, alpha: 1.0)
    static let watermarkText = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.93, alpha: 1.0)
    static let watermarkBackground = NSColor.black.withAlphaComponent(0.44)
    static let watermarkBorder = NSColor.white.withAlphaComponent(0.18)
}

struct BrandMarkView: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(nsColor: BrandPalette.logoBackground))

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                Path { path in
                    path.move(to: CGPoint(x: w * 0.18, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.43))
                    path.addLine(to: CGPoint(x: w * 0.63, y: h * 0.80))
                    path.closeSubpath()
                }
                .stroke(Color(nsColor: BrandPalette.logoForeground), style: StrokeStyle(lineWidth: max(1.6, w * 0.07), lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.18, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.80))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.43))
                }
                .stroke(Color(nsColor: BrandPalette.logoAccent), style: StrokeStyle(lineWidth: max(1.4, w * 0.055), lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Color(nsColor: BrandPalette.logoAccent))
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.80, y: h * 0.43)
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

struct BrandWatermarkView: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMarkView(size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("PlotMeasure Pro")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("Developed by Tanik")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .allowsHitTesting(false)
    }
}

enum BrandRenderer {
    static func drawWatermark(in context: CGContext, pageBounds: CGRect) {
        let container = CGRect(
            x: pageBounds.minX + 24,
            y: pageBounds.minY + 22,
            width: 178,
            height: 36
        )

        context.saveGState()
        let background = CGPath(
            roundedRect: container,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        context.addPath(background)
        context.setFillColor(BrandPalette.watermarkBackground.cgColor)
        context.fillPath()

        context.addPath(background)
        context.setStrokeColor(BrandPalette.watermarkBorder.cgColor)
        context.setLineWidth(1)
        context.strokePath()

        drawLogo(in: context, rect: CGRect(x: container.minX + 8, y: container.minY + 6, width: 24, height: 24))

        drawText(
            "PlotMeasure Pro",
            font: .systemFont(ofSize: 11, weight: .bold),
            color: BrandPalette.watermarkText,
            at: CGPoint(x: container.minX + 40, y: container.minY + 18),
            in: context
        )
        drawText(
            "Developed by Tanik",
            font: .systemFont(ofSize: 9.5, weight: .medium),
            color: BrandPalette.watermarkText.withAlphaComponent(0.88),
            at: CGPoint(x: container.minX + 40, y: container.minY + 6),
            in: context
        )
        context.restoreGState()
    }

    static func drawLogo(in context: CGContext, rect: CGRect) {
        context.saveGState()
        let background = CGPath(
            roundedRect: rect,
            cornerWidth: rect.width * 0.24,
            cornerHeight: rect.height * 0.24,
            transform: nil
        )
        context.addPath(background)
        context.setFillColor(BrandPalette.logoBackground.cgColor)
        context.fillPath()

        context.setLineJoin(.round)
        context.setLineCap(.round)

        let whitePath = CGMutablePath()
        whitePath.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.72))
        whitePath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.28))
        whitePath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.43))
        whitePath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.80))
        whitePath.closeSubpath()

        context.addPath(whitePath)
        context.setStrokeColor(BrandPalette.logoForeground.cgColor)
        context.setLineWidth(max(1.3, rect.width * 0.07))
        context.strokePath()

        let accentPath = CGMutablePath()
        accentPath.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.72))
        accentPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.80))
        accentPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.43))

        context.addPath(accentPath)
        context.setStrokeColor(BrandPalette.logoAccent.cgColor)
        context.setLineWidth(max(1.1, rect.width * 0.055))
        context.strokePath()

        let dotRect = CGRect(
            x: rect.minX + rect.width * 0.73,
            y: rect.minY + rect.height * 0.36,
            width: rect.width * 0.14,
            height: rect.height * 0.14
        )
        context.setFillColor(BrandPalette.logoAccent.cgColor)
        context.fillEllipse(in: dotRect)
        context.restoreGState()
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        attributed.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }
}
