import SwiftUI

/// Shared color selector used by editable entities throughout the app.
/// Presets are available to every user; arbitrary colors are a Pro feature.
struct PresetColorSelectionView: View {
    @Environment(ProAccessManager.self) private var proAccess

    @Binding var selection: String
    var title: LocalizedStringResource = "Icon-Farbe"
    var onSelectionChanged: ((String) -> Void)? = nil
    var columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 5
    )

    @State private var showingProUpgrade = false

    private var selectedColor: Color {
        Color(hexString: selection)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { newColor in
                if let hex = newColor.toHex() {
                    selection = hex
                    onSelectionChanged?(hex)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ColorPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            Divider()
                .padding(.vertical, 4)

            if proAccess.hasPro {
                ColorPicker(
                    selection: customColorBinding,
                    supportsOpacity: false
                ) {
                    Label("Eigene Farbe", systemImage: "paintpalette")
                }
                .padding(.trailing, 17)
            } else {
                Button {
                    showingProUpgrade = true
                } label: {
                    HStack(spacing: 10) {
                        Label("Eigene Farbe", systemImage: "paintpalette")
                        Spacer()
                        Text("PRO")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.15), in: Capsule())
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.trailing, 17)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView(feature: "Eigene Farben")
        }
    }

    private func presetButton(_ preset: ColorPreset) -> some View {
        let isSelected = selection.caseInsensitiveCompare(preset.hex) == .orderedSame

        return Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selection = preset.hex
                    onSelectionChanged?(preset.hex)
                }
        } label: {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(width: 36, height: 36)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
