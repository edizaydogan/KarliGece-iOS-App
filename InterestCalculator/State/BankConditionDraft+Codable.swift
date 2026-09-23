//
//  BankConditionDraft+Codable.swift
//  InterestCalculator
//
//  Taslağın kalıcılığı State katmanındadır. `RateBasis` bir MOTOR tipidir ve
//  Codable DEĞİLDİR (motor tipleri Codable olmaz); burada string olarak kodlanır.
//  Böylece kalıcılık eklenirken motor katmanı saf kalır.
//

import Foundation

extension BankConditionDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, annualRateText, rateBasis, idleKind
        case idlePercentageText, idleFixedAmountText, tierDrafts
        case minTotalBalanceText, maxInterestBearingText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let basis: RateBasis = (try container.decode(String.self, forKey: .rateBasis)) == "net" ? .net : .gross
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            annualRateText: try container.decode(String.self, forKey: .annualRateText),
            rateBasis: basis,
            idleKind: try container.decode(IdleKind.self, forKey: .idleKind),
            idlePercentageText: try container.decode(String.self, forKey: .idlePercentageText),
            idleFixedAmountText: try container.decode(String.self, forKey: .idleFixedAmountText),
            tierDrafts: try container.decode([TierDraft].self, forKey: .tierDrafts),
            minTotalBalanceText: try container.decode(String.self, forKey: .minTotalBalanceText),
            maxInterestBearingText: try container.decode(String.self, forKey: .maxInterestBearingText)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(annualRateText, forKey: .annualRateText)
        try container.encode(rateBasis == .net ? "net" : "gross", forKey: .rateBasis)
        try container.encode(idleKind, forKey: .idleKind)
        try container.encode(idlePercentageText, forKey: .idlePercentageText)
        try container.encode(idleFixedAmountText, forKey: .idleFixedAmountText)
        try container.encode(tierDrafts, forKey: .tierDrafts)
        try container.encode(minTotalBalanceText, forKey: .minTotalBalanceText)
        try container.encode(maxInterestBearingText, forKey: .maxInterestBearingText)
    }
}
