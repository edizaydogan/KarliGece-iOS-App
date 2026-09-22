//
//  CompareScreen.swift
//  InterestCalculator
//
//  v1: yer tutucu — ama başlık ve ikon şimdiden NİHAİ ("Karşılaştır"), böylece
//  gelecek adım kimlik değiştirmez. Özel boş-durum view'ı YAZILMAZ:
//  ContentUnavailableView Dynamic Type, VoiceOver, ortalama ve iPad genişliğini
//  bedava getirir. Düz snowfield — gradyan/filigran/animasyon yok.
//

import SwiftUI

struct CompareScreen: View {
    var body: some View {
        ContentUnavailableView(
            "Yakında",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("Tanımladığınız bankaları aynı tutar için yan yana karşılaştırma burada olacak.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.snowfield.ignoresSafeArea())
        .accessibilityIdentifier("compareRoot")
    }
}

#Preview {
    CompareScreen()
}
