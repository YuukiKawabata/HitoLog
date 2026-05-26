import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, AppSpacing.md)
            .foregroundStyle(isEnabled ? AppColor.background : AppColor.textSecondary)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.textPrimary.opacity(isEnabled ? 0.12 : 0.04), lineWidth: 0.7)
            }
            .shadow(color: isEnabled ? AppColor.accent.opacity(0.18) : .clear, radius: 10, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return AppColor.surface }
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
            .background(AppColor.background.opacity(configuration.isPressed ? 0.74 : 1.0), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
