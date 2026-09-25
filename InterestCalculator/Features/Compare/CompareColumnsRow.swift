//
//  CompareColumnsRow.swift
//  InterestCalculator
//
//  Karşılaştır tablosunun TEK hiza kaynağı: N eşit genişlikli hücre ve aralarında
//  saç teli dikey çizgi. Başlık satırı ve tüm metrik satırları bunu kullanır; bu
//  yüzden aynı metrik her sütunda aynı hizada durur. Hücreler üstten hizalanır
//  (fark satırı olan ve olmayan hücrelerde ana değer aynı yükseklikte kalsın).
//

import SwiftUI

struct CompareColumnsRow<Cell: View>: View {
    @Environment(\.displayScale) private var displayScale
    let count: Int
    let cell: (Int) -> Cell

    init(count: Int, @ViewBuilder cell: @escaping (Int) -> Cell) {
        self.count = count
        self.cell = cell
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<count, id: \.self) { column in
                if column > 0 {
                    Rectangle()
                        .fill(Color.rime)
                        .frame(width: 1 / displayScale)
                        .accessibilityHidden(true)
                }
                cell(column)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
            }
        }
        // Dikey çizgiler satırın en uzun hücresi kadar uzasın.
        .fixedSize(horizontal: false, vertical: true)
    }
}
