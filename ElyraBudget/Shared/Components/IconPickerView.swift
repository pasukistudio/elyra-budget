import SwiftUI

struct IconPickerView: View {

    // MARK: - Environment

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.locale)
    private var locale

    // MARK: - Auswahl

    @Binding var selectedIcon: String

    // MARK: - Suche

    @State private var searchText = ""

    // MARK: - Layout

    private let columns = [
        GridItem(
            .adaptive(minimum: 52),
            spacing: 12
        )
    ]

    // MARK: - Icons

    private let availableIcons =
        CategoryIconLibrary.all

    // MARK: - Gefilterte Icons

    private var filteredIcons: [CategoryIconOption] {
        availableIcons.filter {
            $0.matches(
                searchText,
                locale: locale
            )
        }
    }

    // MARK: - Ansicht

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: columns,
                    spacing: 12
                ) {
                    ForEach(filteredIcons) { icon in
                        iconButton(
                            icon.systemName
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Icon auswählen")

#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif

            .searchable(
                text: $searchText,
                prompt: "Icons durchsuchen"
            )
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Icon-Button

    private func iconButton(
        _ iconName: String
    ) -> some View {
        let isSelected =
            selectedIcon == iconName

        return Button {
            selectedIcon = iconName
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12
                )
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.08)
                )
                .frame(
                    width: 48,
                    height: 48
                )

                Image(systemName: iconName)
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : .secondary
                    )

                if isSelected {
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                    .stroke(
                        Color.accentColor,
                        lineWidth: 2
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(iconName)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }
}
