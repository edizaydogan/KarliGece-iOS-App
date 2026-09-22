//
//  DecimalInputParser.swift
//  InterestCalculator
//
//  Locale-agnostik ondalık ayrıştırıcı. Foundation'ın hazır parseStrategy'si
//  "1234.56" gibi girdilerde 100x/1000x hata üretir (istisna atmadan); bu yüzden
//  ayrıştırma elle yapılır ve yalnız en_US_POSIX ile Decimal'e çevrilir.
//

import Foundation

/// Kullanıcının yazdığı serbest metni `Money`'ye çeviren locale-agnostik
/// ayrıştırıcı. `nil` = ayrıştırılamadı; NaN ASLA dışarı çıkmaz.
nonisolated enum DecimalInputParser {

    /// Serbest metni ondalık tutara çevirir. Kural:
    /// - `,` ve `.` ikisi de varsa: sonuncusu ondalık, diğeri binlik.
    /// - Tek tür ayırıcı bir kez geçiyorsa ve ardında TAM 3 hane YOKSA ondalık,
    ///   aksi halde binlik (`"1.234"` -> 1234 bilinçli tercihtir).
    static func parse(_ raw: String) -> Money? {
        // 1. Temizlik
        var s = raw
        // U+2212 (matematiksel eksi) -> ASCII '-'
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        // Boşluk türleri (normal, kırılmaz, dar kırılmaz)
        for whitespace in ["\u{0020}", "\u{00A0}", "\u{202F}"] {
            s = s.replacingOccurrences(of: whitespace, with: "")
        }
        // Rakam, ',', '.', '-' dışındaki her şeyi (para simgeleri dahil) at.
        var kept = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if scalar == "-" || scalar == "," || scalar == "." || (scalar.value >= 48 && scalar.value <= 57) {
                kept.append(scalar)
            }
        }
        s = String(kept)

        if s.isEmpty || s == "-" { return nil }

        // İşaret
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }
        // Ortada/fazladan '-' -> geçersiz
        if s.contains("-") || s.isEmpty { return nil }

        let hasComma = s.contains(",")
        let hasDot = s.contains(".")

        // Ondalık ayırıcıyı belirle (nil = ondalık yok, tüm ayırıcılar binlik)
        let decimalSeparator: Character?
        if hasComma && hasDot {
            let lastComma = s.lastIndex(of: ",")!
            let lastDot = s.lastIndex(of: ".")!
            decimalSeparator = lastComma > lastDot ? "," : "."
        } else if hasComma || hasDot {
            let separator: Character = hasComma ? "," : "."
            let occurrences = s.filter { $0 == separator }.count
            if occurrences == 1 {
                let parts = s.split(separator: separator, omittingEmptySubsequences: false)
                let trailingDigits = parts.count == 2 ? parts[1].count : 0
                // Ardında TAM 3 hane varsa binlik; yoksa ondalık.
                decimalSeparator = (trailingDigits == 3) ? nil : separator
            } else {
                decimalSeparator = nil
            }
        } else {
            decimalSeparator = nil
        }

        // en_US_POSIX biçimine normalize et: binlikleri sil, ondalığı '.' yap.
        var normalized = ""
        for character in s {
            if character == "," || character == "." {
                if character == decimalSeparator {
                    normalized.append(".")
                }
                // aksi halde binlik ayırıcı -> at
            } else {
                normalized.append(character)
            }
        }

        if normalized.isEmpty || normalized == "." { return nil }
        if negative { normalized = "-" + normalized }

        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        // NaN ASLA motora geçmez.
        if value.isNaN { return nil }
        return value
    }
}
