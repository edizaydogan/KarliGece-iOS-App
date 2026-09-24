//
//  CompoundingEngine.swift
//  InterestCalculator
//
//  Valör (değer tarihi) kurallı BİLEŞİK işletme. Saf, deterministik, TOPLAM
//  fonksiyon — Date/Locale/String kullanmaz; yalnız Weekday + Int gün sayısıyla
//  çalışır. Gerçek takvim eşlemesi State katmanının (AccrualCalendar) işidir.
//
//  Kural (kullanıcı tanımı):
//   • Hafta içi (Pzt→Per): bir gecelik net faiz ERTESİ GÜN 00:00'da bakiyeye
//     eklenir → sonraki gece büyümüş bakiye üzerinden işler (günlük bileşik).
//   • Hafta sonu (Cuma+Cmt+Paz): üç gecelik net faiz aynı (Cuma açılış) bakiyesi
//     üzerinden hesaplanıp PAZARTESİ 00:00'da toplu eklenir (kendi içinde
//     bileşiklenmez — "ertesi gün = ilk iş günü" kuralının doğal sonucu).
//

import Foundation

nonisolated enum CompoundingEngine {

    /// Efektif oranda DAİMA 365 takvim günü (bankalar arası karşılaştırılabilirlik).
    private static let calendarDaysInYear: Decimal = 365

    /// `startWeekday` gününden başlayarak `nights` gece boyunca bakiyeyi valör
    /// kuralıyla bileşikler. Her gecenin faizi mevcut motor (`InterestEngine`)
    /// ile hesaplanır — tek gecelik matematik (oran tabanı, stopaj, kova ayrışımı)
    /// için TEK doğruluk kaynağı korunur.
    ///
    /// Dönen `InterestResult`:
    ///  • `breakdown` — GÖSTERİLEN ayrışım ANAPARANINDIR (ilk gece).
    ///  • `totalGrossInterest` / `totalDeductions` / `netInterest` — N gece TOPLAMI.
    ///  • Değişmez: vade sonu bakiyesi == `breakdown.totalBalance + netInterest`.
    static func project(
        initialBalance: Money,
        startWeekday: Weekday,
        nights: Int,
        condition: BankCondition,
        withholding: WithholdingRule
    ) -> InterestResult {
        let n = max(0, nights)

        // Gece yoksa: tek-atış motoruna 0 geceyle düş — tutarlı sıfır sonuç
        // (breakdown + .zeroNights tanılaması dahil).
        if n == 0 {
            return InterestEngine.calculate(
                InterestInput(totalBalance: initialBalance, nights: 0,
                              condition: condition, withholding: withholding)
            )
        }

        var runningBalance = max(0, initialBalance)   // valörlenmiş cari bakiye
        var pendingNet: Money = 0                      // valörü gelmemiş net faiz

        var totalGrossBearing: Money = 0
        var totalGrossIdle: Money = 0
        var totalGross: Money = 0
        var totalDeductions: Money = 0
        var totalNet: Money = 0

        // İlk gecede doldurulur (n >= 1 garanti); derleyiciyi tatmin için yer tutucu.
        var breakdown = BalanceBreakdown(totalBalance: runningBalance, idleAmount: runningBalance,
                                         interestBearingBalance: 0, excessAboveCap: 0, appliedTier: nil)
        var diagnostics: [CalculationDiagnostic] = []

        var weekday = startWeekday
        for index in 0..<n {
            // Gecelik faiz DAİMA cari (valörlenmiş) bakiye üzerinden.
            let night = InterestEngine.calculate(
                InterestInput(totalBalance: runningBalance, nights: 1,
                              condition: condition, withholding: withholding)
            )
            if index == 0 {
                breakdown = night.breakdown
                diagnostics = night.diagnostics
            }

            totalGrossBearing += night.grossInterestOnBearing
            totalGrossIdle += night.grossInterestOnIdle
            totalGross += night.totalGrossInterest
            totalDeductions += night.totalDeductions
            totalNet += night.netInterest
            pendingNet += night.netInterest

            // Valör: ertesi gün İŞ GÜNÜYSE birikmiş kazanç hemen yazılır; hafta
            // sonuysa (Cuma/Cmt sonrası) birikir, ilk iş gününde (Pazartesi) yazılır.
            if weekday.next.isBusinessDay {
                runningBalance += pendingNet
                pendingNet = 0
            }
            weekday = weekday.next
        }
        // Vade sonu 00:00'da kalan birikim yazılır. Bitiş DAİMA iş günüdür
        // (State katmanı hafta sonunu Pazartesi'ye çeker), bu yüzden bu adım
        // yalnız bir güvenlik ağıdır ve toplamı değiştirmez.
        runningBalance += pendingNet

        // Efektif oran — TOPLAM (anapara) bakiye üzerinden, N gece, daima 365 gün.
        let grossEffective: Percentage?
        let netEffective: Percentage?
        let annualBase = breakdown.totalBalance * Decimal(n)
        if breakdown.totalBalance > 0 && annualBase > 0 {
            grossEffective = .percent(totalGross * calendarDaysInYear * 100 / annualBase)
            netEffective = .percent(totalNet * calendarDaysInYear * 100 / annualBase)
        } else {
            grossEffective = nil
            netEffective = nil
        }

        return InterestResult(
            breakdown: breakdown,
            grossInterestOnBearing: totalGrossBearing,
            grossInterestOnIdle: totalGrossIdle,
            totalGrossInterest: totalGross,
            totalDeductions: totalDeductions,
            netInterest: totalNet,
            grossEffectiveAnnualRate: grossEffective,
            netEffectiveAnnualRate: netEffective,
            diagnostics: diagnostics
        )
    }
}
