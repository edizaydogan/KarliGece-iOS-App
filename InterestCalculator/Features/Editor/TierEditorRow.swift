//
//  TierEditorRow.swift
//  InterestCalculator
//
//  Kademe satırı. "ve üzeri" yakalayıcının üst sınır alanı RENDER EDİLMEZ.
//  Aktif kademe canlı vurgulanır (kademeli kuralı anlaşılır kılan tek şey).
//

import SwiftUI

struct TierEditorRow: View {
    @Binding var tier: BankConditionDraft.TierDraft
    let isCatchAll: Bool
    let isActive: Bool
    @FocusState.Binding var focused: EditorField?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCatchAll {
                Text("Bu tutar ve üzeri")
                    .font(.subheadline)
                    .foregroundStyle(.slate)
            } else {
                HStack {
                    Text("Üst sınır").font(.subheadline).foregroundStyle(.slate)
                    Spacer()
                    DecimalTextField(unit: "₺", text: $tier.upperBoundText,
                                     field: .tierUpperBound(tier.id), focused: $focused, kind: .money)
                }
            }
            HStack {
                Text("Vadesiz").font(.subheadline).foregroundStyle(.slate)
                Spacer()
                DecimalTextField(unit: "₺", text: $tier.amountText,
                                 field: .tierAmount(tier.id), focused: $focused, kind: .money)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.frost : Color.drift)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
