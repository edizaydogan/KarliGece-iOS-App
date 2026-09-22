//
//  TierTableTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Kademe Tablosu")
struct TierTableTests {

    @Test("Üst sınır DIŞLAYICI: tam sınır üst kademeye düşer", .tags(.boundary))
    func exclusiveResolve() {
        let table = cliffIdleTable()
        // upperBound DISLAYICI: 50.000,00 üst kademededir
        #expect(table.resolve(for: d("49999.99")).index == 0)
        #expect(table.resolve(for: d("50000")).index == 1)
        #expect(table.resolve(for: d("50000.01")).index == 1)
        #expect(table.resolve(for: 0).index == 0)
    }

    @Test("Boş liste tek fallback kademesine düşer + tanılama")
    func emptyReplacedWithFallback() {
        let table = TierTable<TierRequirement>(normalizing: [], fallback: .fixedAmount(d("999")))
        #expect(table.tiers.count == 1)
        #expect(table.tiers[0].upperBound == nil)
        #expect(table.tiers[0].value == .fixedAmount(d("999")))
        #expect(table.normalizationDiagnostics.contains(.emptyTierTableReplacedWithFallback))
    }

    @Test("Negatif üst sınır 0'a çekilir + tanılama")
    func negativeBoundClamped() {
        let table = TierTable<TierRequirement>(normalizing: [
            .init(upperBound: d("-10"), value: .fixedAmount(d("1"))),
            .init(upperBound: nil, value: .fixedAmount(d("2"))),
        ], fallback: .fixedAmount(0))
        #expect(table.normalizationDiagnostics.contains(.tierBoundBelowZeroClamped))
        #expect(table.tiers.first?.upperBound == 0)
    }

    @Test("Aynı üst sınır: sonuncusu kazanır + tanılama")
    func duplicateBoundMerged() {
        let table = TierTable<TierRequirement>(normalizing: [
            .init(upperBound: d("100"), value: .fixedAmount(d("1"))),
            .init(upperBound: d("100"), value: .fixedAmount(d("2"))),
            .init(upperBound: nil, value: .fixedAmount(d("3"))),
        ], fallback: .fixedAmount(0))
        #expect(table.normalizationDiagnostics.contains(.duplicateTierBoundMerged))
        #expect(table.resolve(for: d("50")).tier.value == .fixedAmount(d("2")))
    }

    @Test("Son kademe sınırsız değilse nil'e zorlanır + tanılama")
    func lastForcedUnbounded() {
        let table = TierTable<TierRequirement>(normalizing: [
            .init(upperBound: d("100"), value: .fixedAmount(d("1"))),
            .init(upperBound: d("200"), value: .fixedAmount(d("2"))),
        ], fallback: .fixedAmount(0))
        #expect(table.tiers.last?.upperBound == nil)
        #expect(table.normalizationDiagnostics.contains(.lastTierForcedUnbounded))
    }

    @Test("Sıralanmamış girdi artan sıralanır, nil sona")
    func sortsAscendingNilLast() {
        let table = TierTable<TierRequirement>(normalizing: [
            .init(upperBound: nil, value: .fixedAmount(d("9"))),
            .init(upperBound: d("200"), value: .fixedAmount(d("2"))),
            .init(upperBound: d("100"), value: .fixedAmount(d("1"))),
        ], fallback: .fixedAmount(0))
        #expect(table.tiers.map(\.upperBound) == [d("100"), d("200"), nil])
    }
}
