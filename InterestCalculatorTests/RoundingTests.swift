//
//  RoundingTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Yuvarlama ve Kuruş", .tags(.rounding))
struct RoundingTests {

    @Test("Yuvarlama modunu ayırt eden tek vaka: 0,005")
    func modeDistinguishingCase() {
        // Golden'ların hepsi iki modda aynı; farkı YALNIZ bu ortaya koyar.
        #expect(RoundingPolicy.halfUp.round2(d("0.005")) == d("0.01"))
        #expect(RoundingPolicy.bankers.round2(d("0.005")) == d("0.00"))
        #expect(RoundingPolicy.standard.round2(d("0.005")) == d("0.01"))   // standard = halfUp
    }

    @Test("round2 bilinen değerler")
    func round2Known() {
        #expect(RoundingPolicy.halfUp.round2(d("16.644")) == d("16.64"))
        #expect(RoundingPolicy.halfUp.round2(d("16.875")) == d("16.88"))
        #expect(RoundingPolicy.halfUp.round2(d("110.9589041")) == d("110.96"))
    }

    // Tek yuvarlama kararı (gece başına DEĞİL). Biri gece başına yuvarlamaya
    // geçerse bu vektörler DERHAL kırılır — silinmemeli.
    @Test("Çok geceli TEK yuvarlama vektörleri")
    func singleRoundingVectors() {
        func gross(_ bearing: Decimal, nights: Int) -> Decimal {
            InterestEngine.calculate(makeInput(total: bearing, nights: nights,
                condition: BankCondition(name: "r", rateRule: .flat(.percent(45))),
                withholdingPercent: 0)).totalGrossInterest
        }
        #expect(gross(d("90000"), nights: 3) == d("332.88"))    // tesadüfen her iki yöntemde aynı
        #expect(gross(d("90000"), nights: 7) == d("776.71"))    // gece başına 776,72 olurdu
        #expect(gross(d("90000"), nights: 30) == d("3328.77"))  // gece başına 3.328,80

        let r50 = InterestEngine.calculate(makeInput(total: d("50000"), nights: 30,
            condition: BankCondition(name: "r", rateRule: .flat(.percent(50))),
            withholdingPercent: 0))
        #expect(r50.totalGrossInterest == d("2054.79"))          // gece başına 2.054,70

        #expect(gross(d("1000"), nights: 2) == d("2.47"))        // gece başına 2,46
    }

    @Test("Türetme kuralı: idle yuvarlanır, bearing fark olarak türetilir")
    func derivationRule() {
        // total 1000,05 × %10 → idleRequired 100,005 → round2 100,01; bearing = fark
        let (b, _) = BalanceBreakdown.make(totalBalance: d("1000.05"),
            condition: BankCondition(name: "x", rateRule: .flat(.percent(45)),
                                     idleRequirement: .percentage(.percent(10))))
        #expect(b.idleAmount == d("100.01"))
        #expect(b.interestBearingBalance == d("900.04"))
        #expect(b.idleAmount + b.interestBearingBalance == d("1000.05"))
    }

    @Test("Double'dan Decimal para tutarlarında bozulur (karakterizasyon)")
    func documentsDoubleInitPitfall() {
        // Uzun para tutarında Double YANLIŞ: Decimal(1234.56) = 1234.5599999999997952
        #expect(Decimal(1234.56) != d("1234.56"))
        // Bizim yol her zaman doğru:
        #expect(d("1234.56") == d("1234.56"))
    }
}
