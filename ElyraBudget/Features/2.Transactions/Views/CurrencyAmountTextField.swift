import SwiftUI

#if os(iOS)
import UIKit

struct CurrencyAmountTextField: UIViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let decimalSeparator: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, decimalSeparator: decimalSeparator)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .label
        field.tintColor = .systemBlue
        field.placeholder = "0\(decimalSeparator)00"
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 22
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.text = text
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = .label

        guard field.text != text, !context.coordinator.isEditing else { return }
        field.text = text
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>
        private let decimalSeparator: String
        var isEditing = false
        private var shouldReplaceExistingValue = false

        init(text: Binding<String>, decimalSeparator: String) {
            self.text = text
            self.decimalSeparator = decimalSeparator
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            isEditing = true
            field.placeholder = nil
            if field.text?.isEmpty == false {
                field.text = normalizedIntegerPart(of: field.text ?? "0")
                updateBinding(from: field)
                shouldReplaceExistingValue = true
            } else {
                shouldReplaceExistingValue = false
            }
            setCursor(in: field, offset: 0)
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.isEditing else { return }
                self.setCursor(in: field, offset: 0)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            isEditing = false
            field.placeholder = "0\(decimalSeparator)00"
            updateBinding(from: field)
        }

        func textField(
            _ field: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString replacement: String
            ) -> Bool {
            let wasEmpty = field.text?.isEmpty != false
            let current = wasEmpty
                ? "0\(decimalSeparator)00"
                : (field.text ?? "0\(decimalSeparator)00")
            let effectiveRange = wasEmpty && range.length == 0
                ? NSRange(location: 0, length: 1)
                : range
            guard let swiftRange = Range(effectiveRange, in: current) else { return false }

            if replacement == decimalSeparator || replacement == "," || replacement == "." {
                shouldReplaceExistingValue = false
                if field.text?.isEmpty != false {
                    field.text = "0\(decimalSeparator)00"
                    text.wrappedValue = field.text ?? ""
                }
                moveCursorToFractionStart(in: field, text: current)
                return false
            }

            if replacement.isEmpty {
                return delete(in: field, range: swiftRange, current: current)
            }

            guard replacement.allSatisfy(\.isNumber) else { return false }
            return insert(
                replacement,
                in: field,
                range: swiftRange,
                current: current
            )
        }

        private func insert(
            _ replacement: String,
            in field: UITextField,
            range: Range<String.Index>,
            current: String
        ) -> Bool {
            let separatorIndex = current.firstIndex(of: Character(decimalSeparator)) ?? current.endIndex
            let cursorOffset = field.offset(
                from: field.beginningOfDocument,
                to: field.selectedTextRange?.start ?? field.endOfDocument
            )

            if current.distance(from: current.startIndex, to: range.lowerBound) <=
                current.distance(from: current.startIndex, to: separatorIndex) {
                if shouldReplaceExistingValue {
                    shouldReplaceExistingValue = false
                    let normalized = replacement + "\(decimalSeparator)00"
                    set(field, text: normalized, cursor: replacement.count)
                    return false
                }

                let integerPart = String(current[..<separatorIndex])
                if integerPart == "0" {
                    let normalized = replacement + "\(decimalSeparator)00"
                    set(field, text: normalized, cursor: replacement.count)
                    return false
                }

                let updated = current.replacingCharacters(in: range, with: replacement)
                let normalized = normalizedIntegerPart(of: updated)
                let cursor = normalized.firstIndex(of: Character(decimalSeparator)).map {
                    normalized.distance(from: normalized.startIndex, to: $0)
                } ?? normalized.count
                set(field, text: normalized, cursor: cursor)
                return false
            }

            let decimalStart = current.index(after: separatorIndex)
            var decimals = Array(current[decimalStart...])
            let decimalPosition = max(0, cursorOffset - current.distance(from: current.startIndex, to: decimalStart))
            if decimalPosition < 2 {
                decimals[decimalPosition] = Character(String(replacement.prefix(1)))
                set(field, text: String(current[..<decimalStart]) + String(decimals), cursor: cursorOffset + 1)
            }
            return false
        }

        private func delete(
            in field: UITextField,
            range: Range<String.Index>,
            current: String
        ) -> Bool {
            let cursor = current.distance(from: current.startIndex, to: range.lowerBound)
            let updated = current.replacingCharacters(in: range, with: "")

            let separator = Character(decimalSeparator)
            if current.contains(separator), !updated.contains(separator) {
                guard let separatorIndex = current.firstIndex(of: separator) else {
                    return false
                }
                let integer = String(current[..<separatorIndex])
                let shortened = integer.dropLast()
                let normalizedInteger = shortened.isEmpty ? "0" : String(shortened)
                set(
                    field,
                    text: normalizedInteger + "\(decimalSeparator)00",
                    cursor: max(1, cursor - 1)
                )
                return false
            }

            let normalized = normalizedIntegerPart(of: updated)
            set(field, text: normalized, cursor: min(cursor, normalized.count))
            return false
        }

        private func normalizedIntegerPart(of value: String) -> String {
            let alternateSeparator = decimalSeparator == "," ? "." : ","
            let localizedValue = value.replacingOccurrences(of: alternateSeparator, with: decimalSeparator)
            let parts = localizedValue.split(separator: Character(decimalSeparator), omittingEmptySubsequences: false)
            let integer = parts.first.map(String.init) ?? "0"
            let decimals = String((parts.dropFirst().first ?? "00")).padding(toLength: 2, withPad: "0", startingAt: 0)
            var normalizedInteger = integer.isEmpty ? "0" : integer
            while normalizedInteger.count > 1, normalizedInteger.first == "0" {
                normalizedInteger.removeFirst()
            }
            return normalizedInteger + decimalSeparator + decimals
        }

        private func moveCursorToIntegerEnd(in field: UITextField) {
            guard let currentText = field.text else {
                setCursor(in: field, offset: 0)
                return
            }
            let separator = currentText.firstIndex(of: Character(decimalSeparator))
            let offset = separator.map { currentText.distance(from: currentText.startIndex, to: $0) } ?? currentText.count
            setCursor(in: field, offset: offset)
        }

        private func moveCursorToFractionStart(in field: UITextField, text: String) {
            let offset = (text.firstIndex(of: Character(decimalSeparator)).map { text.distance(from: text.startIndex, to: $0) } ?? text.count) + 1
            setCursor(in: field, offset: offset)
        }

        private func set(_ field: UITextField, text: String, cursor: Int) {
            field.text = text
            self.text.wrappedValue = text
            setCursor(in: field, offset: cursor)
        }

        private func setCursor(in field: UITextField, offset: Int) {
            guard let position = field.position(from: field.beginningOfDocument, offset: max(0, offset)) else { return }
            field.selectedTextRange = field.textRange(from: position, to: position)
        }

        private func updateBinding(from field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}
#else
struct CurrencyAmountTextField: View {
    @Binding var text: String
    let fontSize: CGFloat
    let decimalSeparator: String

    var body: some View {
        TextField("0\(decimalSeparator)00", text: $text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
    }
}
#endif
