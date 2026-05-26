import SwiftUI

struct BrandIconView: View {
    let size: CGFloat
    var showsShadow = true

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(AppColor.border.opacity(0.74), lineWidth: 0.6)
            }
            .shadow(color: showsShadow ? AppColor.shadow : .clear, radius: 14, y: 8)
    }
}
