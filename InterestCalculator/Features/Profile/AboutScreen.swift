//
//  AboutScreen.swift
//  InterestCalculator
//
//  Profil → Hakkında: sürüm, uygulamanın ne yaptığı, hesaplama kuralları ve
//  uyarılar. Kurallar README'deki "Hesaplama kuralları"nın kullanıcı özeti.
//

import SwiftUI

struct AboutScreen: View {
    @Environment(\.locale) private var locale

    private struct Rule: Identifiable {
        let systemImage: String
        let text: LocalizedStringKey
        var id: String { systemImage }
    }

    private var rules: [Rule] {
        let threshold = MaxPlanner.defaultMinimumProfit.grouped(fractionDigits: 0...2, locale: locale)
        return [
            Rule(systemImage: "stairs",
                 text: "Kademe sınırı dışlayıcıdır: bakiye üst sınırın altındaysa o kademe geçerlidir; tam sınır bir üst kademeye düşer."),
            Rule(systemImage: "calendar",
                 text: "Hafta içi kazanç ertesi gün 00:00'da bakiyeye eklenip bileşiklenir. Cuma–Pazar kazancı Pazartesi 00:00'da toplu eklenir. Tatil takvimi yoktur."),
            Rule(systemImage: "percent",
                 text: "Efektif oran, bankalar karşılaştırılabilsin diye her zaman 365 takvim günüyle hesaplanır."),
            Rule(systemImage: "gauge.with.dots.needle.100percent",
                 text: "Max planı kademeli bankada üst kademeye geçmez. EFT ücreti para ayrılan bankanın kazancından bir kez düşülür; kazancı \(threshold) ₺'yi geçmeyen bankaya para ayrılmaz."),
            Rule(systemImage: "banknote",
                 text: "Bakiyelerim, uygulama her açıldığında valörü gelen net faizi bağlı bankanın Düzenle'deki koşulları ve stopajla bakiyeye ekler. Hafta sonu faizi her kayıtta 1 gecelik (her gece) ya da 3 gecelik (Pazartesi toplu) seçilir; bugünün faizi kaçırıldıysa o gece ya da Cuma–Pazar'ın 3 gecesi atlanır."),
            Rule(systemImage: "lock",
                 text: "Tüm veriler yalnız bu cihazda saklanır."),
        ]
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.onAccent)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.glacier))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        // Marka adı, iki dilde de aynı.
                        Text(verbatim: "Karlı Gece")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.ink)
                        Text("Sürüm \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.slate)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                Text("TL vadesiz / gecelik mevduat hesapları için net faiz hesaplar. Banka koşullarını siz tanımlarsınız; hiçbir banka kuralı ya da vergi oranı uygulamaya gömülü değildir.")
                    .font(.subheadline)
                    .foregroundStyle(.ink)
            }
            .listRowBackground(Color.drift)

            Section("Hesaplama kuralları") {
                ForEach(rules) { rule in
                    Label {
                        Text(rule.text)
                            .font(.subheadline)
                            .foregroundStyle(.ink)
                    } icon: {
                        Image(systemName: rule.systemImage)
                            .foregroundStyle(.glacier)
                    }
                }
            }
            .listRowBackground(Color.drift)

            Section("Uyarı") {
                Text("Stopaj, Düzenle'de ön dolu gelir; bu oran temsilîdir. Kullanmadan önce yürürlükteki oranı kontrol edin.")
                    .font(.subheadline)
                    .foregroundStyle(.ink)
                Text(ResultMessages.disclaimer(locale))
                    .font(.subheadline)
                    .foregroundStyle(.slate)
            }
            .listRowBackground(Color.drift)
        }
        .scrollContentBackground(.hidden)
        .background(Color.snowfield)
        .accessibilityIdentifier("aboutRoot")
        .navigationTitle("Hakkında")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutScreen()
    }
}
