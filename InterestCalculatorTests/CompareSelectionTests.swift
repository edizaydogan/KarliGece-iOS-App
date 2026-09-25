//
//  CompareSelectionTests.swift
//  InterestCalculatorTests
//
//  Karşılaştır sütun seçimi: tohum, otomatik doldurma, yer değiştirme, konumsal
//  doldurma ve gizli 3. yuva. Saf değer tipi — yalnız UUID'lerle çalışır.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Karşılaştır Seçimi")
struct CompareSelectionTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    @Test("Tohum 1. sütuna gelir; tohum nil ise listedeki ilk banka")
    func seed() {
        #expect(CompareSelection(seed: b).resolvedIDs(in: [a, b]) == [b, a])
        #expect(CompareSelection(seed: nil).resolvedIDs(in: [a, b]) == [a, b])
    }

    @Test("Varsayılan 2 sütun; 3 bankada setColumnCount(3) üçüncüyü otomatik doldurur")
    func autoFill() {
        var selection = CompareSelection(seed: b)
        #expect(selection.resolvedIDs(in: [a, b, c]) == [b, a])
        selection.setColumnCount(3)
        #expect(selection.resolvedIDs(in: [a, b, c]) == [b, a, c])
    }

    @Test("Sütun sayısı banka sayısına ve 2...3 aralığına kırpılır", .tags(.boundary))
    func clamping() {
        var selection = CompareSelection(seed: a)
        selection.setColumnCount(3)
        #expect(selection.resolvedIDs(in: [a, b]) == [a, b])
        #expect(selection.resolvedIDs(in: [a]).isEmpty)
        #expect(selection.resolvedIDs(in: []).isEmpty)

        selection.setColumnCount(7)
        #expect(selection.columnCount == 3)
        selection.setColumnCount(0)
        #expect(selection.columnCount == 2)
    }

    @Test("Başka sütundaki bankayı seçmek iki sütunun yerini değiştirir")
    func swapsInsteadOfDuplicating() {
        var selection = CompareSelection(seed: a)
        selection.select(b, forColumn: 0, in: [a, b])
        #expect(selection.resolvedIDs(in: [a, b]) == [b, a])
    }

    @Test("Sütunlarda olmayan bankayı seçmek yalnız o sütunu değiştirir")
    func replacesOnlyThatColumn() {
        var selection = CompareSelection(seed: a)
        selection.select(c, forColumn: 1, in: [a, b, c])
        #expect(selection.resolvedIDs(in: [a, b, c]) == [a, c])
    }

    @Test("Silinen banka kendi konumunda dolar, diğer sütunlar kaymaz")
    func positionalFill() {
        var selection = CompareSelection(seed: a)
        selection.setColumnCount(3)
        selection.select(c, forColumn: 2, in: [a, b, c, d])   // [a, b, c]
        // 2. sütunun bankası (b) silinir: a ve c yerinde, boşluğa d gelir.
        #expect(selection.resolvedIDs(in: [a, c, d]) == [a, d, c])
    }

    @Test("3 → 2 → 3 geçişinde gizli 3. yuvanın seçimi geri gelir")
    func hiddenThirdSlot() {
        var selection = CompareSelection(seed: a)
        selection.setColumnCount(3)
        selection.select(d, forColumn: 2, in: [a, b, c, d])   // [a, b, d]
        selection.setColumnCount(2)
        #expect(selection.resolvedIDs(in: [a, b, c, d]) == [a, b])
        selection.setColumnCount(3)
        #expect(selection.resolvedIDs(in: [a, b, c, d]) == [a, b, d])
    }

    @Test("Tohum listede yoksa (silinmişse) 1. sütun ilk kullanılmamış bankayla dolar")
    func missingSeed() {
        #expect(CompareSelection(seed: UUID()).resolvedIDs(in: [a, b]) == [a, b])
    }

    @Test("Listede olmayan bankayı seçmek hiçbir şeyi değiştirmez")
    func unknownIDIgnored() {
        var selection = CompareSelection(seed: a)
        selection.select(UUID(), forColumn: 1, in: [a, b])
        #expect(selection.resolvedIDs(in: [a, b]) == [a, b])
    }

    @Test("Değişmez · her seçimden sonra sütunlarda tekrar yok", .tags(.invariant))
    func neverDuplicates() {
        let banks = [a, b, c, d]
        for count in [2, 3] {
            for column in 0..<count {
                for id in banks {
                    var selection = CompareSelection(seed: c)
                    selection.setColumnCount(count)
                    selection.select(id, forColumn: column, in: banks)
                    let resolved = selection.resolvedIDs(in: banks)
                    #expect(resolved.count == count)
                    #expect(Set(resolved).count == resolved.count)
                    #expect(resolved[column] == id)
                }
            }
        }
    }
}
