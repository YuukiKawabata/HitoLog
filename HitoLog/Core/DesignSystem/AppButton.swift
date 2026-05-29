import SwiftUI
import UIKit

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
            .shadow(color: isEnabled ? AppColor.accent.opacity(configuration.isPressed ? 0.10 : 0.18) : .clear, radius: configuration.isPressed ? 6 : 10, y: configuration.isPressed ? 3 : 6)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 軽いスケールフィードバックを与える汎用ボタンスタイル。
/// アイコンボタンやカード状のタップ要素に使う。
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// フォロー状態を表す共通ピルボタン。
/// トグル時にアイコン（plus ⇄ checkmark）がモーフし、軽くバウンスする。
/// ユーザー・トピックルームのフォロー導線すべてで使う。
struct FollowPillButton: View {
    enum Size { case compact, prominent }

    let isFollowing: Bool
    var followText = "フォロー"
    var followingText = "フォロー中"
    var size: Size = .compact
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isFollowing)
                Text(isFollowing ? followingText : followText)
                    .lineLimit(1)
            }
            .font(font)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: size == .prominent ? 132 : nil)
            .foregroundStyle(isFollowing ? AppColor.textPrimary : AppColor.background)
            .background(
                isFollowing ? AppColor.surface : AppColor.accent,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isFollowing ? AppColor.border : AppColor.accent.opacity(0.3), lineWidth: 0.7)
            }
        }
        .buttonStyle(ScaleButtonStyle(scale: size == .prominent ? 0.97 : 0.92))
        .fixedSize(horizontal: size == .prominent, vertical: false)
        .animation(.snappy(duration: 0.28), value: isFollowing)
        .accessibilityLabel(isFollowing ? "\(followingText)。タップで解除" : followText)
    }

    private var font: Font {
        size == .prominent ? AppFont.button : .caption.weight(.semibold)
    }

    private var verticalPadding: CGFloat {
        size == .prominent ? AppSpacing.sm : AppSpacing.xs
    }

    private var horizontalPadding: CGFloat {
        size == .prominent ? AppSpacing.md : AppSpacing.sm
    }

    private var radius: CGFloat {
        size == .prominent ? AppRadius.md : AppRadius.sm
    }
}
