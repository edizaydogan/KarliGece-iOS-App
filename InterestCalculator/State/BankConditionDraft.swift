//
//  BankConditionDraft.swift
//  InterestCalculator
//
//  Canlı düzenleme için taslak katmanı. Motor tipleri normalize invariantlı ve
//  UUID'siz olduğu için düzenlemeye uygun değildir; taslak UUID'li ve String
//  alanlıdır (yarım yazılmış sayı normalize edilmez, ForEach stabil id ister).
//

import Foundation

/// Bir banka koşulunun düzenlenebilir (ham String) taslağı.
struct BankConditionDraft: Identifiable, Hashable {

    /// Vadesiz şartının türü (UI seçici için).
    enum IdleKind: Hashable, CaseIterable {
        case none, percentage, fixedAmount, tiered
    }

    /// Kademeli şartta tek satırın taslağı. Üst sınır boşsa "ve üzeri" yakalayıcı.
    struct TierDraft: Identifiable, Hashable {
        let id: UUID
        var upperBoundText: String
        var amountText: String

        init(id: UUID = UUID(), upperBoundText: String = "", amountText: String = "") {
            self.id = id
            self.upperBoundText = upperBoundText
            self.amountText = amountText
        }
    }

    let id: UUID
    var name: String
    var annualRateText: String
    var rateBasis: RateBasis
    var idleKind: IdleKind
    var idlePercentageText: String
    var idleFixedAmountText: String
    var tierDrafts: [TierDraft]
    var minTotalBalanceText: String
    var maxInterestBearingText: String

    init(
        id: UUID = UUID(),
        name: String = "",
        annualRateText: String = "",
        rateBasis: RateBasis = .gross,
        idleKind: IdleKind = .none,
        idlePercentageText: String = "",
        idleFixedAmountText: String = "",
        tierDrafts: [TierDraft] = [],
        minTotalBalanceText: String = "",
        maxInterestBearingText: String = ""
    ) {
        self.id = id
        self.name = name
        self.annualRateText = annualRateText
        self.rateBasis = rateBasis
        self.idleKind = idleKind
        self.idlePercentageText = idlePercentageText
        self.idleFixedAmountText = idleFixedAmountText
        self.tierDrafts = tierDrafts
        self.minTotalBalanceText = minTotalBalanceText
        self.maxInterestBearingText = maxInterestBearingText
    }

    /// Yeni banka için boş taslak (AppState'in başlangıç bankası).
    static var blankDefault: BankConditionDraft { BankConditionDraft(name: "") }

    /// Önizleme/örnek: Golden #1 senaryosu (%45 brüt, %10 vadesiz).
    static var sample: BankConditionDraft {
        BankConditionDraft(name: "Örnek Banka", annualRateText: "45",
                           idleKind: .percentage, idlePercentageText: "10")
    }

    /// Taslağı motor tipine çevirir. Ham metinler locale-agnostik ayrıştırılır;
    /// geçersiz/boş sayısal alanlar güvenli varsayılana düşer (motor zaten toplam
    /// fonksiyon olduğu için tanılamayı kendisi üretir).
    func makeCondition() -> BankCondition {
        let rate = Percentage.percent(DecimalInputParser.parse(annualRateText) ?? 0)

        let idle: IdleRequirement
        switch idleKind {
        case .none:
            idle = .none
        case .percentage:
            idle = .percentage(.percent(DecimalInputParser.parse(idlePercentageText) ?? 0))
        case .fixedAmount:
            idle = .fixedAmount(DecimalInputParser.parse(idleFixedAmountText) ?? 0)
        case .tiered:
            let tiers = tierDrafts.map { draft in
                TierTable<TierRequirement>.Tier(
                    upperBound: DecimalInputParser.parse(draft.upperBoundText),  // boş → sınırsız
                    value: .fixedAmount(DecimalInputParser.parse(draft.amountText) ?? 0)
                )
            }
            idle = .tiered(TierTable(normalizing: tiers, fallback: .fixedAmount(0)))
        }

        return BankCondition(
            id: id,
            name: name,
            rateRule: .flat(rate),
            rateBasis: rateBasis,
            idleRequirement: idle,
            minTotalBalance: DecimalInputParser.parse(minTotalBalanceText),
            maxInterestBearingAmount: DecimalInputParser.parse(maxInterestBearingText)
        )
    }
}
