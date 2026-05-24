import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, AppSpacing.md)
            .foregroundStyle(Color.white)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return AppColor.textTertiary }
        return AppColor.accent.opacity(isPressed ? 0.82 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .padding(.vertical, 10)
            .padding(.horizontal, AppSpacing.md)
            .foregroundStyle(AppColor.textPrimary)
            .background(AppColor.surface.opacity(configuration.isPressed ? 0.7 : 1.0), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
