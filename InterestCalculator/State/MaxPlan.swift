//
//  MaxPlan.swift
//  InterestCalculator
//
//  Max planlayıcının sonucu ve geçmiş kaydı. Yalnız düz değerler taşır (motor
//  tipi yok), bu yüzden Codable'dır: geçmiş, planı hesaplandığı andaki haliyle
//  saklar — bankalar ya da stopaj sonradan değişse de kayıt değişmez.
//  Sonradan eklenen alanlar opsiyoneldir: eski kayıtlar (ve onlarla birlikte
//  tüm oturum) çözülmeye devam etsin.
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
        /// Bankanın EFT ücreti (hesap anındaki); kazançtan bir kez düşülür.
        /// nil: EFT ücreti eklenmeden önce kaydedilmiş plan, 0 sayılır.
        var eftFee: Money?
        /// Sınırlı kademede: üst sınıra kalan (sınır − vade sonu bakiyesi).
        var headroom: Money?
        /// Sınırlı kademede: vade sonu bakiyesinin 1 günlük net faizi (payın tabanı).
        var oneDayNet: Money?

        var id: UUID { bankID }
        /// Vade sonu bakiyesi = yatırılan + net kazanç (bankadaki bakiye; EFT hariç).
        var finalBalance: Money { deposit + netInterest }
        /// Bankanın karı: N günlük net kazanç − EFT ücreti.
        var profit: Money { netInterest - (eftFee ?? 0) }
    }

    /// Plana para ayrılmayan banka.
    nonisolated struct BankRef: Hashable, Sendable, Codable, Identifiable {
        var id: UUID
        var name: String
        var annualRatePercent: Decimal
        var rateIsNet: Bool
        /// nil: EFT ücreti eklenmeden önce kaydedilmiş plan.
        var eftFee: Money?
    }

    /// Aynı kurallarla tek bir bankaya yatırılabilecek en iyi seçenek. Plan en az
    /// bunun kadar kar ettirir; fark, parayı bölmenin getirisidir.
    nonisolated struct Baseline: Hashable, Sendable, Codable {
        var bankName: String
        var deposit: Money
        var netInterest: Money
        /// nil: EFT ücreti eklenmeden önce kaydedilmiş plan, 0 sayılır.
        var eftFee: Money?

        /// N günlük net kazanç − EFT ücreti.
        var profit: Money { netInterest - (eftFee ?? 0) }
    }

    var amount: Money
    var nights: Int
    /// Kademe payı: vade sonu bakiyesindeki 1 günlük net faizin yüzde kaçı
    /// (hesap anındaki değer; ayar sonradan değişse de kayıt doğru kalır).
    var bufferPercent: Decimal
    /// Bir bankaya para ayrılması için bankanın karının (net kazanç − EFT) AŞMASI
    /// gereken tutar (hesap anındaki). nil: bu kural eklenmeden önce kaydedilmiş plan.
    var minimumProfit: Money?
    /// Hesapta kullanılan toplam stopaj (yüzde değeri).
    var withholdingPercent: Decimal
    /// Para ayrılan bankalar, Düzenle'deki sırayla.
    var allocations: [Allocation]
    var unusedBanks: [BankRef]
    /// Hiçbir bankaya kazancı artırarak (ve kar eşiğini aşarak) eklenemeyen tutar.
    var unallocated: Money
    var bestSingleBank: Baseline?

    var totalDeposited: Money { allocations.reduce(0) { $0 + $1.deposit } }
    var totalGross: Money { allocations.reduce(0) { $0 + $1.grossInterest } }
    var totalDeductions: Money { allocations.reduce(0) { $0 + $1.deductions } }
    var totalNet: Money { allocations.reduce(0) { $0 + $1.netInterest } }
    var totalEftFees: Money { allocations.reduce(0) { $0 + ($1.eftFee ?? 0) } }
    /// Toplam kar: net kazanç − EFT ücretleri. Planlayıcının en yükselttiği değer.
    var totalProfit: Money { allocations.reduce(0) { $0 + $1.profit } }
    /// Toplam karın gün ortalaması (`totalProfit / nights`), kuruşa yuvarlanmış.
    var averageDailyProfit: Money {
        guard nights > 0 else { return 0 }
        return RoundingPolicy.standard.round2(totalProfit / Decimal(nights))
    }
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
