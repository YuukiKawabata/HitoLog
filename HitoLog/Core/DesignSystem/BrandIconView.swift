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
            .shadow(color: .black.opacity(showsShadow ? 0.12 : 0), radius: 14, y: 8)
    }
}
