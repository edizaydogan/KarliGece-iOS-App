//
//  DecimalInputParserTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Sayı Ayrıştırma")
struct DecimalInputParserTests {

    struct ParseCase: CustomTestStringConvertible {
        let input: String
        let expected: Decimal?
        var testDescription: String { "\"\(input)\" → \(expected.map { "\($0)" } ?? "nil")" }
    }

    @Test("Ayrıştırma tablosu", arguments: [
        ParseCase(input: "1.234,56", expected: d("1234.56")),   // tr_TR normal
        ParseCase(input: "1234,56", expected: d("1234.56")),
        ParseCase(input: "1234.56", expected: d("1234.56")),    // Foundation 123456 üretir
        ParseCase(input: "1,234.56", expected: d("1234.56")),   // Foundation 1.234 üretir
        ParseCase(input: "\u{20BA}1.234,56", expected: d("1234.56")), // ₺ temizlenir
        ParseCase(input: "100.000", expected: d("100000")),     // tam 3 hane → binlik
        ParseCase(input: "1\u{00A0}234,56", expected: d("1234.56")), // kırılmaz boşluk
        ParseCase(input: "1.234", expected: d("1234")),         // bilinçli: binlik
        ParseCase(input: "1.50", expected: d("1.5")),           // 2 hane → ondalık
        ParseCase(input: "1.500", expected: d("1500")),         // 3 hane → binlik
        ParseCase(input: "-1.234,56", expected: d("-1234.56")),
        ParseCase(input: "", expected: nil),
        ParseCase(input: "-", expected: nil),
        ParseCase(input: "abc", expected: nil),
    ])
    func parseTable(_ c: ParseCase) {
        #expect(DecimalInputParser.parse(c.input) == c.expected)
    }

    @Test("Çöp girdi nil döner — NaN asla motora geçmez")
    func garbageIsNil() {
        // Not: "1e5x" gibi rakam İÇEREN girdiler spec gereği rakamlara indirgenir
        // (harfler atılır → "15"), bu yüzden "çöp" sayılmaz. Gerçek çöp: rakamsız.
        for junk in ["", "-", "abc", ",", ".", "--5"] {
            #expect(DecimalInputParser.parse(junk) == nil)
        }
    }

    // Foundation'ın hazır parseStrategy'sinin neden kullanılmadığını belgeler.
    @Test("Negatif kontrol: Foundation tr_TR '1234.56'yı YANLIŞ ayrıştırır")
    func foundationParseStrategyPitfall() {
        let strategy = Decimal.FormatStyle(locale: Locale(identifier: "tr_TR")).parseStrategy
        let foundationResult = try? strategy.parse("1234.56")
        // Ölçülen: 123456 (100x hata). Bizim ayrıştırıcı doğru olanı verir.
        #expect(foundationResult != d("1234.56"))
        #expect(DecimalInputParser.parse("1234.56") == d("1234.56"))
    }
}
