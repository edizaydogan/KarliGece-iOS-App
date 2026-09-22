//
//  BankCondition.swift
//  InterestCalculator
//
//  Bir bankanın gecelik faiz koşulu. Hiçbir banka kuralı koda gömülmez —
//  tüm alanlar kullanıcı tarafından tanımlanır.
//

import Foundation

/// Bir bankanın (kullanıcının tanımladığı) gecelik faiz koşulu.
///
/// `idleAnnualRate` ve `dayCountBasis` v1 UI'da görünmez ama modelde durur;
/// genişletilebilirlik kontrol akışında değil veri modelinde tutulur.
nonisolated struct BankCondition: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rateRule: RateRule
    /// İlan edilen oranın brüt/net tabanı.
    var rateBasis: RateBasis
    /// Vadesiz tutma şartı.
    var idleRequirement: IdleRequirement
    /// Ürünün gerektirdiği en az toplam bakiye (altındaysa faiz işlemez).
    var minTotalBalance: Money?
    /// Faize tabi tutulabilecek en yüksek bakiye (üstü faizsiz kalır).
    var maxInterestBearingAmount: Money?
    /// Vadesiz kısma ödenen yıllık oran. v1 UI'da yok; varsayılan %0.
    var idleAnnualRate: Percentage
    /// Gün sayımı tabanı. v1 UI'da yok; varsayılan ACT/365.
    var dayCountBasis: DayCountBasis

    init(
        id: UUID = UUID(),
        name: String,
        rateRule: RateRule,
        rateBasis: RateBasis = .gross,
        idleRequirement: IdleRequirement = .none,
        minTotalBalance: Money? = nil,
        maxInterestBearingAmount: Money? = nil,
        idleAnnualRate: Percentage = .zero,
        dayCountBasis: DayCountBasis = .actual365
    ) {
        self.id = id
        self.name = name
        self.rateRule = rateRule
        self.rateBasis = rateBasis
        self.idleRequirement = idleRequirement
        self.minTotalBalance = minTotalBalance
        self.maxInterestBearingAmount = maxInterestBearingAmount
        self.idleAnnualRate = idleAnnualRate
        self.dayCountBasis = dayCountBasis
    }
}
