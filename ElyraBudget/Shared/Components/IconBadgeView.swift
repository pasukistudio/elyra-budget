import SwiftUI

struct IconBadgeView: View {
    let iconName: String
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.opacity(0.15))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(color)
            }
    }
}
