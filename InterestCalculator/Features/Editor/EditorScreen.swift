//
//  EditorScreen.swift
//  InterestCalculator
//
//  Adım 5b iskeleti — Form, bölümler, kademe listesi ve giriş mekaniği Adım 6'da.
//

import SwiftUI

struct EditorScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            Color.snowfield.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Düzenle")
                    .font(.headline)
                    .foregroundStyle(.ink)
                Text("Form ve kural düzenleme Adım 6'da")
                    .font(.subheadline)
                    .foregroundStyle(.slate)
            }
        }
        .accessibilityIdentifier("editorRoot")
    }
}

#Preview {
    EditorScreen()
        .environment(AppState.preview)
}
