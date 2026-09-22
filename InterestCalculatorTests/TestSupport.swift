//
//  TestSupport.swift
//  InterestCalculatorTests
//
//  Ortak yardımcılar. Testler @MainActor İŞARETLENMEZ — saf fonksiyon main
//  actor'a ait değildir; motor tipleri nonisolated olduğu için izolasyon sınırı
//  gerçektir.
//

import Testing
import Foundation
@testable import InterestCalculator

// Etiketler — Xcode Test Plan filtreleme içindir (CLI'da isim-regex kullanılır;
// `swift test --filter-tag` diye bir bayrak YOKTUR).
extension Tag {
    @Tag static var golden: Self
    @Tag static var edgeCase: Self
    @Tag static var rounding: Self
    @Tag static var invariant: Self
    @Tag static var boundary: Self
}

/// Decimal ASLA Double'dan kurulmaz. `StaticString` zorunlu → yalnız derleme-anı
/// literalleri geçer, hesaplanmış `String` kazayla giremez.
func d(_ s: StaticString) -> Decimal {
    Decimal(string: "\(s)", locale: Locale(identifier: "en_US_POSIX"))!
}

/// Yuvarlanmamış oran karşılaştırması (periyodik ondalıklar için tolerans).
/// İLK SATIR NaN reddi — bu olmadan yardımcı NaN'i SESSİZCE geçirir.
func expectClose(
    _ actual: Decimal,
    _ expected: Decimal,
    tolerance: Decimal = d("0.000000001"),
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard !actual.isNaN, !expected.isNaN else {
        Issue.record("NaN karşılaştırması", sourceLocation: sourceLocation)
        return
    }
    #expect(abs(actual - expected) <= tolerance, sourceLocation: sourceLocation)
}

/// Her sonuçta istisnasız tutması gereken beş değişmez.
func assertInvariants(_ r: InterestResult, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.idleAmount + r.interestBearingBalance + r.excessAboveCap == r.totalBalance,
            "değişmez 1: kovalar toplamı", sourceLocation: sourceLocation)
    #expect(r.netInterest + r.totalDeductions == r.totalGrossInterest,
            "değişmez 2: net + kesinti == brüt", sourceLocation: sourceLocation)
    for value in [r.idleAmount, r.interestBearingBalance, r.excessAboveCap,
                  r.totalGrossInterest, r.totalDeductions, r.netInterest] {
        #expect(value >= 0, "değişmez 3: tutar >= 0", sourceLocation: sourceLocation)
        #expect(!value.isNaN, "değişmez 5: NaN yok", sourceLocation: sourceLocation)
    }
    #expect(r.interestBearingBalance <= r.totalBalance,
            "değişmez 4: bearing <= total", sourceLocation: sourceLocation)
    #expect(!(r.grossEffectiveAnnualRate?.fraction.isNaN ?? false), sourceLocation: sourceLocation)
    #expect(!(r.netEffectiveAnnualRate?.fraction.isNaN ?? false), sourceLocation: sourceLocation)
}

/// Efektif oranı 2 haneye yuvarlayıp gösterim değeriyle karşılaştırmak için.
func displayPercent(_ p: Percentage?) -> Decimal? {
    p.map { RoundingPolicy.halfUp.round2($0.percentValue) }
}

/// Kademe uçurumu tablosu: <50.000 → 5.000 vadesiz, ≥50.000 → 10.000 vadesiz.
func cliffIdleTable() -> TierTable<TierRequirement> {
    TierTable<TierRequirement>(normalizing: [
        .init(upperBound: d("50000"), value: .fixedAmount(d("5000"))),
        .init(upperBound: nil, value: .fixedAmount(d("10000"))),
    ], fallback: .fixedAmount(0))
}

/// Golden testleri için standart girdi kurucu (tek satır stopaj).
func makeInput(
    total: Decimal,
    nights: Int,
    condition: BankCondition,
    withholdingPercent: Decimal
) -> InterestInput {
    InterestInput(
        totalBalance: total,
        nights: nights,
        condition: condition,
        withholding: .single(.percent(withholdingPercent))
    )
}
