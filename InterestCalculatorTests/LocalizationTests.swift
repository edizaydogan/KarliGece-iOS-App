//
//  LocalizationTests.swift
//  InterestCalculatorTests
//
//  Dil seçimi: Localizable.xcstrings'in İngilizcesi eksiksiz ve biçim
//  belirteçleri Türkçe anahtarla uyumlu (uyumsuz belirteç çalışma anında
//  çöker), metinler cihazın dilinden bağımsız olarak seçilen dilde çözülür,
//  sayılar seçilen dil + bölgeyle biçimlenir. Yerel ayarlar sabit verilir
//  (en_TR, en_US, tr_TR): simülatörün dili/bölgesi sonucu değiştirmesin.
//  AppState MainActor olduğu için suite @MainActor; save() ÇAĞRILMAZ.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Dil seçimi")
@MainActor
struct LocalizationTests {

    private let english = Locale(identifier: "en_TR")
    private let turkish = Locale(identifier: "tr_TR")

    // MARK: - Katalog

    /// Kaynak katalog (uygulama paketine derlenmiş hali değil): test, simülatörde
    /// de host dosya sistemini okuyabilir.
    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("InterestCalculator/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(json?["strings"] as? [String: [String: Any]])
    }

    /// Metindeki biçim belirteçleri: argüman sırası (1'den) → tür ("@", "lld").
    /// `%%` atlanır; konumsuz belirteçler soldan sırayla numaralanır. Konumlu ve
    /// konumsuz karışırsa nil: CoreFoundation bu durumda argümanı yanlış türle
    /// okur ve çöker.
    private func specifiers(in text: String) -> [Int: String]? {
        let pattern = /%(?:(\d+)\$)?(@|lld|%)/
        var result: [Int: String] = [:]
        var next = 1
        var positional = false, sequential = false
        for match in text.matches(of: pattern) where match.output.2 != "%" {
            if let position = match.output.1.flatMap({ Int($0) }) {
                positional = true
                result[position] = String(match.output.2)
            } else {
                sequential = true
                result[next] = String(match.output.2)
                next += 1
            }
        }
        return positional && sequential ? nil : result
    }

    @Test("Her metnin İngilizcesi var; belirteçleri Türkçe anahtarla aynı tür ve sırada")
    func catalogIsCompleteAndConsistent() throws {
        var problems: [String] = []
        for (key, entry) in try catalog() {
            if entry["shouldTranslate"] as? Bool == false { continue }
            let expected = specifiers(in: key)
            guard let en = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any] else {
                problems.append("çevirisi yok: \(key)")
                continue
            }
            var values: [String] = []
            if let unit = en["stringUnit"] as? [String: Any], var value = unit["value"] as? String {
                // Çoğul ikamesi (%#@ad@) kendi argümanını kendi belirteciyle okur.
                for (name, raw) in en["substitutions"] as? [String: [String: Any]] ?? [:] {
                    let argument = raw["argNum"] as? Int ?? 0
                    let format = raw["formatSpecifier"] as? String ?? "?"
                    value = value.replacingOccurrences(of: "%#@\(name)@", with: "%\(argument)$\(format)")
                }
                values.append(value)
            }
            if let plural = (en["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
                for form in plural.values {
                    if let value = (form["stringUnit"] as? [String: Any])?["value"] as? String {
                        values.append(value)
                    }
                }
            }
            if values.isEmpty { problems.append("boş çeviri: \(key)") }
            for value in values where specifiers(in: value) != expected {
                problems.append("belirteç uyumsuz: \(key) → \(value)")
            }
        }
        #expect(problems.isEmpty, "\(problems.sorted().joined(separator: "\n"))")
    }

    // MARK: - Çözümleme

    @Test("Metin seçilen dilde çözülür; çevirisi olmayan Türkçe kalır")
    func resolvesInSelectedLanguage() {
        #expect(english.localized("Görünüm") == "Appearance")
        #expect(turkish.localized("Görünüm") == "Görünüm")
        #expect(english.localized("Adsız banka \(4)") == "Unnamed bank 4")
        #expect(turkish.localized("Adsız banka \(4)") == "Adsız banka 4")
        #expect(english.localized("Katalogda olmayan metin \(5)") == "Katalogda olmayan metin 5")
    }

    @Test("İngilizce çoğul biçimleri: tek argümanlı ve ikameli")
    func englishPlurals() {
        #expect(english.localized("Net kazanç (\(1) gece)") == "Net earnings (1 night)")
        #expect(english.localized("Net kazanç (\(3) gece)") == "Net earnings (3 nights)")
        #expect(turkish.localized("Net kazanç (\(3) gece)") == "Net kazanç (3 gece)")
        #expect(english.localized("\(1) banka · \("₺5,00")") == "1 bank · ₺5,00")
        #expect(english.localized("\(2) banka · \("₺5,00")") == "2 banks · ₺5,00")
        #expect(english.localized("\("₺5,00") · \(1) gün") == "₺5,00 · 1 day")
        #expect(english.localized("\("₺5,00") · \(10) gün") == "₺5,00 · 10 days")
        #expect(turkish.localized("\(2) banka · \("₺5,00")") == "2 banka · ₺5,00")
    }

    @Test("Birim etiketi: Türkçede tekil/çoğul aynı, İngilizcede ayrı")
    func singularUnits() {
        #expect(turkish.localized("gece (tekil)") == "gece")
        #expect(turkish.localized("gün (tekil)") == "gün")
        #expect(english.localized("gece (tekil)") == "night")
        #expect(english.localized("gece") == "nights")
        #expect(english.localized("gün (tekil)") == "day")
        #expect(english.localized("gün") == "days")
    }

    // MARK: - Yerel ayar ve biçim

    @Test("Dilin yerel ayarı: seçilen dil + cihazın bölgesi")
    func localeCombinesLanguageAndDeviceRegion() {
        for language in AppLanguage.allCases {
            #expect(language.locale.language.languageCode?.identifier == language.rawValue)
            #expect(language.locale.region == Locale.current.region)
        }
    }

    @Test("Yüzde işaretinin yeri yerel ayardan: tr %45, en_US 45%")
    func percentPlacement() {
        #expect(Decimal(45).percentText(fractionDigits: 0...2, locale: turkish) == "%45")
        #expect(Decimal(string: "17.5")!.percentText(fractionDigits: 0...2, locale: turkish) == "%17,5")
        #expect(Decimal(45).percentText(fractionDigits: 0...2, locale: Locale(identifier: "en_US")) == "45%")
        #expect(Decimal(45).percentText(fractionDigits: 2...2, locale: Locale(identifier: "en_US")) == "45.00%")
    }

    @Test("Presentation cümleleri seçilen dilde")
    func presentationTexts() {
        let entry = HoldingEntry(id: UUID(), day: CalendarDay(index: 9408), kind: .interest(nights: 3),
                                 change: 1, balanceAfter: 1)
        #expect(HoldingText.title(for: entry, locale: english) == "Interest · 3 nights")
        #expect(HoldingText.title(for: entry, locale: turkish) == "Faiz · 3 gece")
        #expect(TierSummaryText.rangeText(lower: nil, upper: 50_000, locale: english) == "Below ₺50.000")
        #expect(TierSummaryText.rangeText(lower: nil, upper: 50_000, locale: turkish) == "50.000 ₺'nin altı")
        #expect(MaxPlanText.rateCaption(percent: 42, isNet: false, locale: english) == "%42 · gross")
        #expect(MaxPlanText.rateCaption(percent: 42, isNet: true, locale: turkish) == "%42 · net")
        let us = Locale(identifier: "en_US")
        #expect(ResultMessages.warnings(for: [.idlePercentageAboveOneHundred], locale: us).map(\.text)
                == ["Idle percentage capped at 100%."])
        #expect(ResultMessages.warnings(for: [.idlePercentageAboveOneHundred], locale: turkish).map(\.text)
                == ["Vadesiz yüzdesi %100'e sınırlandı."])
        #expect(HoldingText.dayText(CalendarDay(index: 9408), locale: english).contains("Oct"))
        #expect(HoldingText.dayText(CalendarDay(index: 9408), locale: turkish).contains("Eki"))
    }

    // MARK: - AppState

    @Test("Adsız bankanın adı uygulamanın diline uyar")
    func unnamedBankFollowsLanguage() {
        let state = AppState(loadPersisted: false)
        state.banks = [.sample, .blankDefault]
        #expect(state.language == .turkish)
        #expect(state.displayName(for: state.banks[1]) == "Adsız banka 2")
        state.language = .english
        #expect(state.displayName(for: state.banks[1]) == "Unnamed bank 2")
        #expect(state.displayName(for: state.banks[0]) == "Örnek Banka")
    }
}
