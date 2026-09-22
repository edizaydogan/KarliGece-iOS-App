//
//  PercentageTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Yüzde Tipi")
struct PercentageTests {

    @Test("percent(_:) kesir ve yüzde değerini doğru kurar")
    func percentFactory() {
        #expect(Percentage.percent(45).fraction == d("0.45"))
        #expect(Percentage.percent(45).percentValue == 45)
        #expect(Percentage.zero.fraction == 0)
        #expect(Percentage.percent(0) == Percentage.zero)
    }

    @Test("applied(to:) YUVARLAMA YAPMAZ (kuruş altı korunur)")
    func appliedDoesNotRound() {
        // %10 × 1000,05 = 100,005 — kuruş altı basamak korunmalı
        #expect(Percentage.percent(10).applied(to: d("1000.05")) == d("100.005"))
    }

    @Test("İki kırpma ayrı davranır: [0,100] ve yalnız-negatif")
    func clamps() {
        #expect(Percentage.percent(-5).clampedToZeroThroughOneHundred() == .zero)
        #expect(Percentage.percent(150).clampedToZeroThroughOneHundred() == .percent(100))
        #expect(Percentage.percent(45).clampedToZeroThroughOneHundred() == .percent(45))
        // Oran için: negatif → 0, ama %100 ÜSTÜ KORUNUR (kampanya/kriz oranı)
        #expect(Percentage.percent(-5).clampedToNonNegative() == .zero)
        #expect(Percentage.percent(250).clampedToNonNegative() == .percent(250))
    }

    @Test("Comparable fraction'a göre")
    func comparable() {
        #expect(Percentage.percent(10) < Percentage.percent(20))
        #expect(!(Percentage.percent(20) < Percentage.percent(20)))
    }
}
