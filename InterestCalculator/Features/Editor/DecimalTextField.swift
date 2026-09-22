//
//  DecimalTextField.swift
//  InterestCalculator
//
//  Ondalık giriş alanı. Canlı biçimlendirme YOK (imleç zıplatır, "1,0" yazmayı
//  imkânsızlaştırır); yalnız ODAK KAYBINDA normalize eder. Para simgesi / %
//  alanın DIŞINDA statik etikettir.
//

import SwiftUI

struct DecimalTextField: View {
    enum Kind {
        case money   // 1.234,56 — grouping + tam 2 hane
        case rate    // 45 / 45,5 — grouping + 0..2 hane

        func normalized(_ value: Decimal) -> String {
            switch self {
            case .money: return value.grouped(fractionDigits: 2)
            case .rate:  return value.grouped(fractionDigits: 0...2)
            }
        }
    }

    let unit: String
    @Binding var text: String
    let field: EditorField
    @FocusState.Binding var focused: EditorField?
    let kind: Kind
    var placeholder: String = "0"

    var body: some View {
        HStack(spacing: 4) {
            Text(unit).foregroundStyle(.slate)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(.ink)
                .focused($focused, equals: field)
                .onChange(of: focused) { previous, current in
                    // Bu alandan çıkıldığında normalize et.
                    if previous == field && current != field { normalize() }
                }
        }
    }

    private func normalize() {
        guard let value = DecimalInputParser.parse(text) else { return }
        text = kind.normalized(value)
    }
}
