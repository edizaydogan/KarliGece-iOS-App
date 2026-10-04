//
//  NumberFormatting.swift
//  InterestCalculator
//
//  Gösterim biçimlendirme yardımcıları. Yerel ayar dışarıdan gelir (seçilen dil
//  + cihaz bölgesi, bkz. `AppLanguage.locale`); görünümler onu `\.locale`
//  ortamından alır. Motor/Parsing bunları KULLANMAZ; yalnız Presentation ve
//  State (odak-kaybı normalizasyonu) içindir.
//

import Foundation

extension Decimal {
    /// Binlik gruplama + sabit ondalık hane.
    func grouped(fractionDigits: Int, locale: Locale) -> String {
        formatted(.number.grouping(.automatic).precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// Binlik gruplama + değişken ondalık hane.
    func grouped(fractionDigits range: ClosedRange<Int>, locale: Locale) -> String {
        formatted(.number.grouping(.automatic).precision(.fractionLength(range)).locale(locale))
    }

    /// Yüzde değeri (45 → "%45"); işaretin yeri yerel ayara göre (en_US'te "45%").
    func percentText(fractionDigits range: ClosedRange<Int>, locale: Locale) -> String {
        (self / 100).formatted(.percent.precision(.fractionLength(range)).locale(locale))
    }
}
