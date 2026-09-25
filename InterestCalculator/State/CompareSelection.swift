//
//  CompareSelection.swift
//  InterestCalculator
//
//  Karşılaştır sütunlarının banka seçimi. Saf değer tipi: yalnız banka id'leriyle
//  çalışır, AppState'e ve taslaklara dokunmaz — bu yüzden Özet'in seçimini
//  YAPISAL olarak değiştiremez. Karşılaştır ekranının @State'inde yaşar ve kalıcı
//  değildir; 1. yuva, ekran ilk açıldığında Özet'in seçili bankasıyla BİR KEZ
//  tohumlanır.
//

import Foundation

nonisolated struct CompareSelection: Hashable, Sendable {

    /// Aynı anda gösterilebilecek en fazla sütun.
    static let maxColumns = 3

    /// Konumsal yuvalar (daima `maxColumns` eleman). Boş ya da geçersiz yuva,
    /// çözümlemede listede henüz kullanılmamış ilk bankayla doldurulur.
    private(set) var slots: [UUID?]

    /// Gösterilen sütun sayısı (2...3). Banka sayısı daha azsa çözümleme kırpar.
    private(set) var columnCount: Int = 2

    init(seed: UUID?) {
        slots = [seed] + Array(repeating: nil, count: Self.maxColumns - 1)
    }

    /// Banka listesine göre sütunların banka id'leri; banka 2'den azsa boş (boş
    /// durum). Listede olmayan ya da önceki bir yuvayı tekrarlayan id boşaltılır;
    /// boş yuvalar KENDİ KONUMLARINDA listede kullanılmamış ilk id'lerle dolar —
    /// böylece bir banka silinince diğer sütunlar yerinden kaymaz.
    func resolvedIDs(in bankIDs: [UUID]) -> [UUID] {
        guard bankIDs.count >= 2 else { return [] }
        let count = min(max(columnCount, 2), Self.maxColumns, bankIDs.count)

        var chosen = Array(slots.prefix(count))
        var used = Set<UUID>()
        for index in chosen.indices {
            if let id = chosen[index], bankIDs.contains(id), !used.contains(id) {
                used.insert(id)
            } else {
                chosen[index] = nil
            }
        }
        var unused = bankIDs.filter { !used.contains($0) }.makeIterator()
        for index in chosen.indices where chosen[index] == nil {
            chosen[index] = unused.next()
        }
        return chosen.compactMap { $0 }
    }

    /// `column` sütununa `id` bankasını atar. Banka başka bir sütunda zaten
    /// gösteriliyorsa iki sütun YER DEĞİŞTİRİR (tekrar oluşmaz). Gizli yuvalar
    /// (ör. 2 sütundayken 3. yuva) korunur.
    mutating func select(_ id: UUID, forColumn column: Int, in bankIDs: [UUID]) {
        var ids = resolvedIDs(in: bankIDs)
        guard ids.indices.contains(column), bankIDs.contains(id) else { return }
        if let other = ids.firstIndex(of: id) {
            ids.swapAt(column, other)
        } else {
            ids[column] = id
        }
        for (index, value) in ids.enumerated() {
            slots[index] = value
        }
    }

    /// Sütun sayısını 2...3 aralığına kırparak ayarlar.
    mutating func setColumnCount(_ count: Int) {
        columnCount = min(max(count, 2), Self.maxColumns)
    }
}
