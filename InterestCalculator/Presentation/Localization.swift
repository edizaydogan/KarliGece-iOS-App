//
//  Localization.swift
//  InterestCalculator
//
//  Uygulama içi dil seçimi. SwiftUI'ye literal verilen metinler (Text("…"),
//  Button("…"), Section("…") …) çeviriyi kendiliğinden `\.locale` ortamının
//  dilinde bulur; kök görünüm bu ortamı `AppState.language`'dan verir. Kodda
//  `String` olarak kurulan metinler ise `String(localized:)` ile çözülemez: o,
//  dili cihazın dil tercihinden seçer, uygulamadaki seçimi bilmez. Bu metinler
//  burada, seçilen dilin .lproj klasöründen çözülür.
//

import Foundation

extension Locale {
    /// `key`'in bu yerel ayarın dilindeki karşılığı; araya giren sayılar da bu
    /// yerel ayarla biçimlenir. Çevirisi olmayan metin Türkçe (kaynak) kalır.
    func localized(_ key: String.LocalizationValue) -> String {
        guard let code = language.languageCode?.identifier, let bundle = Self.lprojBundles[code] else {
            // Kaynak dil (Türkçe) için derlemede .lproj üretilmez; metnin kendisi
            // kaynaktır. Var olmayan tablo aramayı bu kaynak metne düşürür. Ana
            // pakete bakmak cihazın dilini (ör. İngilizceyi) getirirdi.
            return String(localized: key, table: Self.sourceOnlyTable, locale: self)
        }
        return String(localized: key, bundle: bundle, locale: self)
    }

    /// Hiçbir dilde bulunmayan tablo adı (bkz. `localized`).
    private static let sourceOnlyTable = "SourceLanguageOnly"

    /// Uygulamanın dil klasörleri (ör. en.lproj), dil koduyla.
    private static let lprojBundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for code in Bundle.main.localizations {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundles[code] = bundle
            }
        }
        return bundles
    }()
}
