//
//  MaxPlan.swift
//  InterestCalculator
//
//  Max planlayıcının sonucu ve geçmiş kaydı. Yalnız düz değerler taşır (motor
//  tipi yok), bu yüzden Codable'dır: geçmiş, planı hesaplandığı andaki haliyle
//  saklar — bankalar ya da stopaj sonradan değişse de kayıt değişmez.
//

import Foundation

/// Bir "Maksimize Et" hesabının sonucu.
///
/// Değişmez: yatırılanlar toplamı + `unallocated` == `amount`.
nonisolated struct MaxPlan: Hashable, Sendable, Codable {

    /// Yatırılan tutara uygulanan vadesiz şartı.
    nonisolated enum IdleRule: Hashable, Sendable, Codable {
        case none
        /// Yüzde değeri: 10 → %10 (toplam bakiye üzerinden).
        case percentage(Decimal)
        case fixedAmount(Money)
    }

    /// Kademeli bankada tutarın bulunduğu kademe.
    nonisolated struct Tier: Hashable, Sendable, Codable {
        var index: Int
        /// Bir önceki kademenin üst sınırı; ilk kademede nil.
        var lowerBound: Money?
        /// DIŞLAYICI üst sınır; son (sınırsız) kademede nil.
        var upperBound: Money?
    }

    /// Bir bankaya yatırılacak tutar ve N günlük sonucu (motordan).
    nonisolated struct Allocation: Hashable, Sendable, Codable, Identifiable {
        var bankID: UUID
        var bankName: String
        /// İlan edilen yıllık oran (yüzde değeri) ve tabanı.
        var annualRatePercent: Decimal
        var rateIsNet: Bool
        var idleRule: IdleRule
        /// Yalnız kademeli bankada dolu.
        var tier: Tier?
        var deposit: Money
        /// Başlangıç dağılımı (ilk gece).
        var idleAmount: Money
        var interestBearing: Money
        var excessAboveCap: Money
        /// N gün toplamı.
        var grossInterest: Money
        var deductions: Money
        var netInterest: Money
        /// Sınırlı kademede: üst sınıra kalan (sınır − vade sonu bakiyesi).
        var headroom: Money?
        /// Sınırlı kademede: vade sonu bakiyesinin 1 günlük net faizi (payın tabanı).
        var oneDayNet: Money?

        var id: UUID { bankID }
        /// Vade sonu bakiyesi = yatırılan + net kazanç.
        var finalBalance: Money { deposit + netInterest }
    }

    /// Plana para ayrılmayan banka.
    nonisolated struct BankRef: Hashable, Sendable, Codable, Identifiable {
        var id: UUID
        var name: String
        var annualRatePercent: Decimal
        var rateIsNet: Bool
    }

    /// Aynı kurallarla tek bir bankaya yatırılabilecek en iyi seçenek. Plan en az
    /// bunun kadar kazandırır; fark, parayı bölmenin getirisidir.
    nonisolated struct Baseline: Hashable, Sendable, Codable {
        var bankName: String
        var deposit: Money
        var netInterest: Money
    }

    var amount: Money
    var nights: Int
    /// Kademe payı: vade sonu bakiyesindeki 1 günlük net faizin yüzde kaçı
    /// (hesap anındaki değer; ayar sonradan değişse de kayıt doğru kalır).
    var bufferPercent: Decimal
    /// Hesapta kullanılan toplam stopaj (yüzde değeri).
    var withholdingPercent: Decimal
    /// Para ayrılan bankalar, Düzenle'deki sırayla.
    var allocations: [Allocation]
    var unusedBanks: [BankRef]
    /// Hiçbir bankaya kazancı artırarak eklenemeyen tutar.
    var unallocated: Money
    var bestSingleBank: Baseline?

    var totalDeposited: Money { allocations.reduce(0) { $0 + $1.deposit } }
    var totalGross: Money { allocations.reduce(0) { $0 + $1.grossInterest } }
    var totalDeductions: Money { allocations.reduce(0) { $0 + $1.deductions } }
    var totalNet: Money { allocations.reduce(0) { $0 + $1.netInterest } }
}

/// Max geçmişinin bir satırı: hesap anı + planın kendisi.
nonisolated struct MaxPlanRecord: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    /// Hesabın yapıldığı an (listede tarih ve saatiyle görünür).
    var createdAt: Date
    /// Planın başladığı gün (00:00). Bitiş = başlangıç + `plan.nights`.
    var startDate: Date
    var plan: MaxPlan
}
