import SwiftUI
import UIKit

enum AppColor {
    static let background = Color(lightHex: "#FFFDF8", darkHex: "#1A1712")
    static let groupedBackground = Color(lightHex: "#F4EDE1", darkHex: "#100F0C")
    static let surface = Color(lightHex: "#F8F1E6", darkHex: "#221E18")
    static let elevatedSurface = Color(lightHex: "#FFF9EF", darkHex: "#2A251D")
    static let subBackground = Color(lightHex: "#EFE4D4", darkHex: "#181511")
    static let border = Color(lightHex: "#D8CBB8", darkHex: "#4B4236")
    static let ruleLine = Color(lightHex: "#E9DDCA", darkHex: "#302A22")
    static let textPrimary = Color(lightHex: "#201C16", darkHex: "#F7EFE2")
    static let textSecondary = Color(lightHex: "#685F51", darkHex: "#B9AD9B")
    static let textTertiary = Color(lightHex: "#9A8E7C", darkHex: "#7F7465")
    static let placeholder = Color(lightHex: "#A29582", darkHex: "#8F8373")
    static let accent = Color(lightHex: "#0E6D62", darkHex: "#77C6BC")
    static let accentSoft = Color(lightHex: "#DCEEE9", darkHex: "#163A36")
    static let inkBlue = Color(lightHex: "#315C7D", darkHex: "#94BFE3")
    static let stamp = Color(lightHex: "#9E3F32", darkHex: "#DE8D7F")
    static let warning = Color(lightHex: "#B76538", darkHex: "#E2A174")
    static let shadow = Color.black.opacity(0.08)
}

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 16
}

struct PaperCanvas: View {
    var body: some View {
        ZStack {
            AppColor.groupedBackground

            LinearGradient(
                colors: [
                    AppColor.background.opacity(0.82),
                    AppColor.groupedBackground,
                    AppColor.subBackground.opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PaperRulePattern()
                .opacity(0.58)
        }
        .ignoresSafeArea()
    }
}

private struct PaperRulePattern: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 28
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 34
                }
            }
            .stroke(AppColor.ruleLine, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct InkDivider: View {
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Capsule()
                .fill(AppColor.stamp)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(AppColor.border)
                .frame(height: 0.5)
        }
    }
}

struct SectionKicker: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }

            Text(text)
                .font(AppFont.kicker)
        }
        .foregroundStyle(AppColor.stamp)
        .textCase(.uppercase)
        .tracking(0.6)
    }
}

struct PaperMetricTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint = AppColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.sm)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border.opacity(0.76), lineWidth: 0.5)
        }
    }
}

struct HumanSignalStrip: View {
    let title: String
    let detail: String
    var systemImage = "checkmark.seal.fill"
    var tint = AppColor.accent

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 0.5)
        }
    }
}

extension Color {
    init(lightHex: String, darkHex: String) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: darkHex) : UIColor(hex: lightHex)
        })
    }

    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension View {
    func paperSurface(cornerRadius: CGFloat = AppRadius.lg, shadow: Bool = true) -> some View {
        background(AppColor.background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }
            .shadow(color: shadow ? AppColor.shadow : .clear, radius: 14, x: 0, y: 8)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleaned.count {
        case 3:
            red = Double((value >> 8) & 0xF) / 15.0
            green = Double((value >> 4) & 0xF) / 15.0
            blue = Double(value & 0xF) / 15.0
            alpha = 1.0
        case 6:
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
            alpha = 1.0
        case 8:
            red = Double((value >> 24) & 0xFF) / 255.0
            green = Double((value >> 16) & 0xFF) / 255.0
            blue = Double((value >> 8) & 0xFF) / 255.0
            alpha = Double(value & 0xFF) / 255.0
        default:
            red = 0.0
            green = 0.0
            blue = 0.0
            alpha = 1.0
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
