//
//  NumberFormatting.swift
//  InterestCalculator
//
//  Gösterim biçimlendirme yardımcıları (Locale.current). Motor/Parsing bunları
//  KULLANMAZ; yalnız Presentation ve State (odak-kaybı normalizasyonu) içindir.
//

import Foundation

extension Decimal {
    /// Locale.current binlik gruplama + sabit ondalık hane.
    func grouped(fractionDigits: Int) -> String {
        formatted(.number.grouping(.automatic).precision(.fractionLength(fractionDigits)))
    }

    /// Locale.current binlik gruplama + değişken ondalık hane.
    func grouped(fractionDigits range: ClosedRange<Int>) -> String {
        formatted(.number.grouping(.automatic).precision(.fractionLength(range)))
    }
}
