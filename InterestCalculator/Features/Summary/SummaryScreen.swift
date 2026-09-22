//
//  SummaryScreen.swift
//  InterestCalculator
//
//  Adım 5b iskeleti — nihai tasarım (hero, şelale, oran satırı) Adım 7'de.
//

import SwiftUI

struct SummaryScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            Rectangle().fill(.nightSky).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Özet")
                    .font(.headline)
                    .foregroundStyle(.ink)

                if let result = state.result {
                    Text(result.netInterest, format: .currency(code: "TRY"))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundStyle(.aurora)
                        .monospacedDigit()
                    Text("Net gecelik kazanç")
                        .font(.subheadline)
                        .foregroundStyle(.slate)
                } else {
                    Text("Başlamak için bakiyenizi ve bir banka kuralı girin")
                        .font(.subheadline)
                        .foregroundStyle(.slate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .accessibilityIdentifier("summaryRoot")
    }
}

#Preview {
    SummaryScreen()
        .environment(AppState.preview)
}
