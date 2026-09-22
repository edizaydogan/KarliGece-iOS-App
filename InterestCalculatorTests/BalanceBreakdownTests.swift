//
//  BalanceBreakdownTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Bakiye Kovaları")
struct BalanceBreakdownTests {

    private func condition(idle: IdleRequirement = .none,
                           min: Money? = nil,
                           cap: Money? = nil) -> BankCondition {
        BankCondition(name: "x", rateRule: .flat(.percent(45)),
                      idleRequirement: idle, minTotalBalance: min,
                      maxInterestBearingAmount: cap)
    }

    @Test("Yüzde şartının tabanı DAİMA toplam bakiye (dairesel değil)")
    func percentageBaseIsTotal() {
        let (b, _) = BalanceBreakdown.make(totalBalance: d("100000"),
                                           condition: condition(idle: .percentage(.percent(10))))
        #expect(b.idleAmount == d("10000"))          // 9.090,91 DEĞİL
        #expect(b.interestBearingBalance == d("90000"))
        #expect(b.excessAboveCap == 0)
    }

    @Test("Şart tüm bakiyeyi yutar: 3.000 / sabit 5.000 → faize giren 0 + tanılama")
    func requirementConsumesAll() {
        let (b, diag) = BalanceBreakdown.make(totalBalance: d("3000"),
                                              condition: condition(idle: .fixedAmount(d("5000"))))
        #expect(b.idleAmount == d("3000"))
        #expect(b.interestBearingBalance == 0)
        #expect(diag.contains(.requirementConsumesEntireBalance))
    }

    @Test("Cap: 400.000 / %10 / cap 250.000 → excess 110.000 + tanılama")
    func cappedInterestBearing() {
        let (b, diag) = BalanceBreakdown.make(totalBalance: d("400000"),
                                              condition: condition(idle: .percentage(.percent(10)),
                                                                    cap: d("250000")))
        #expect(b.idleAmount == d("40000"))
        #expect(b.interestBearingBalance == d("250000"))
        #expect(b.excessAboveCap == d("110000"))
        #expect(diag.contains(.cappedInterestBearingAmount))
    }

    @Test("En az bakiye altı: idle = total, faize giren 0 + tanılama")
    func belowMinimum() {
        let (b, diag) = BalanceBreakdown.make(totalBalance: d("99999"),
                                              condition: condition(min: d("100000")))
        #expect(b.idleAmount == d("99999"))
        #expect(b.interestBearingBalance == 0)
        #expect(b.excessAboveCap == 0)
        #expect(diag.contains(.belowMinimumBalance))
    }

    @Test("Kademeli şart: dışlayıcı seçim + appliedTier dolu")
    func tieredIdleAppliedTier() {
        let (b, _) = BalanceBreakdown.make(totalBalance: d("50000"),
                                           condition: condition(idle: .tiered(cliffIdleTable())))
        #expect(b.idleAmount == d("10000"))           // tam 50.000 → üst kademe
        #expect(b.appliedTier?.index == 1)
        #expect(b.appliedTier?.lowerBound == d("50000"))
        #expect(b.appliedTier?.upperBound == nil)
    }

    @Test("Değişmez idle+bearing+excess==total birçok girdide tutar", .tags(.invariant))
    func bucketInvariant() {
        let totals = [d("0"), d("1000.05"), d("50000"), d("99999"), d("400000")]
        for total in totals {
            let (b, _) = BalanceBreakdown.make(totalBalance: total,
                                               condition: condition(idle: .percentage(.percent(10)),
                                                                     cap: d("250000")))
            #expect(b.idleAmount + b.interestBearingBalance + b.excessAboveCap == total)
        }
    }
}
